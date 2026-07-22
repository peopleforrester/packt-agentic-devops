# ABOUTME: Static gate on the student VTT's provisioning contract: Pod Identity for AWS, an
# ABOUTME: in-cluster Gitea remote on main, and no credential ever written into git config.
#
# These run without a cluster on purpose. Every failure they catch cost a live debug cycle on a
# real cluster at least once, and at fleet scale each one would repeat across 250 clusters.
import os
import re

import yaml

from conftest import REPO_ROOT

VTT_DIR = os.path.join(REPO_ROOT, "scripts", "provision", "vtt")
ENTRYPOINT = os.path.join(REPO_ROOT, "images", "web-terminal", "entrypoint.sh")
DOCKERFILE = os.path.join(REPO_ROOT, "images", "web-terminal", "Dockerfile")
AWS_CREDS = os.path.join(VTT_DIR, "student-aws-creds.sh")
MANIFEST = os.path.join(VTT_DIR, "web-terminal.yaml")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _code(path):
    # Comment lines explain what we deliberately do NOT do, so a naive substring search on the
    # whole file matches the rationale and fails on correct code. Assert against code only.
    return "\n".join(
        line for line in _read(path).splitlines() if not line.lstrip().startswith("#")
    )


# --- AWS access: Pod Identity, never a static key -------------------------------------------

def test_student_aws_creds_does_not_mint_iam_users_or_access_keys():
    # The old approach created an IAM user per cluster and rotated its access key on every run,
    # because AWS returns a secret key exactly once. That made provisioning non-idempotent and
    # left 250 users and 250 keys to revoke. Pod Identity replaced it (decision D21).
    body = _code(AWS_CREDS)
    for forbidden in ("iam create-user", "iam create-access-key", "AWS_SECRET_ACCESS_KEY"):
        assert forbidden not in body, f"{forbidden} is back; D21 replaced static keys with Pod Identity"


def test_student_aws_creds_uses_pod_identity_association():
    body = _read(AWS_CREDS)
    assert "create-pod-identity-association" in body
    assert "pods.eks.amazonaws.com" in body, "trust policy must name the Pod Identity service principal"


def test_student_aws_role_is_scoped_to_its_own_cluster():
    # ~50 student clusters share one account. A wildcard here lets every student enumerate every
    # other student's resources.
    body = _code(AWS_CREDS)
    assert "eks:DescribeCluster" in body
    assert ':cluster/${CLUSTER}"' in body, "DescribeCluster must be pinned to this cluster's ARN"
    assert "ReadOnlyAccess" not in body, "the managed ReadOnlyAccess policy is far too broad here"


def test_student_aws_creds_verifies_the_identity_from_inside_the_pod():
    # At fleet scale an unverified provisioning step is 250 unverified steps.
    body = _read(AWS_CREDS)
    assert "sts get-caller-identity" in body
    assert "kubectl -n \"${NS}\" exec" in body or "kubectl -n ${NS} exec" in body


def test_student_aws_creds_requires_the_pod_identity_agent():
    # Without the addon the pod silently gets no credentials, so fail at provisioning, not live.
    assert "eks-pod-identity-agent" in _read(AWS_CREDS)


def test_entrypoint_does_not_shadow_pod_identity_with_a_credentials_file():
    # A credentials file sits ahead of Pod Identity in the CLI's credential chain, so a stale one
    # silently masks a working identity.
    body = _read(ENTRYPOINT)
    assert "AWS_CONTAINER_CREDENTIALS_FULL_URI" in body
    assert 'rm -f "$HOME/.aws/credentials"' in body


def test_entrypoint_always_sets_a_region():
    # With no static-key secret there is no other source of region, and every aws call would fail.
    body = _read(ENTRYPOINT)
    config_write = body.index('cat > "$HOME/.aws/config"')
    guard = body.index("if [[ -n \"${AWS_ACCESS_KEY_ID:-}\"")
    assert config_write < guard, "~/.aws/config must be written unconditionally, before the key guard"


# --- Git: the student pushes to in-cluster Gitea, on main, with no password in git config ----

def test_entrypoint_clones_gitea_rather_than_repointing_the_baked_clone():
    # The baked clone is shallow and single-branch, so its refspec only ever requests the branch it
    # was cloned with. Repointing origin at Gitea made every fetch fail with "couldn't find remote
    # ref" behind a `|| true`, leaving the student on a branch ArgoCD does not reconcile.
    body = _code(ENTRYPOINT)
    assert "git clone --quiet \"${_remote}\"" in body
    assert "checkout -q -B main origin/main" not in body, (
        "the checkout-against-a-shallow-clone approach is the bug this replaced"
    )


def test_entrypoint_keeps_credentials_out_of_the_git_remote():
    # Embedding them writes the password into .git/config and prints it from `git remote -v`,
    # putting it on screen whenever a student shares their terminal.
    body = _read(ENTRYPOINT)
    assert "credential.helper store" in body
    assert 'remote set-url origin "${GITEA_REPO_URL}"' in body, (
        "the stored remote must be the clean URL, not the credentialed one"
    )


def test_dockerfile_baked_clone_tracks_main():
    # main is what ArgoCD reconciles; the fallback clone must not strand a student on staging.
    assert "--branch main" in _read(DOCKERFILE)


# --- Manifest ------------------------------------------------------------------------------

def test_manifest_has_no_pod_level_run_as_group_without_a_user():
    # runc rejects the sandbox with "group specified without user" and the whole VTT stays down.
    docs = [d for d in yaml.safe_load_all(_read(MANIFEST)) if d]
    for doc in docs:
        if doc.get("kind") != "Deployment":
            continue
        sc = doc["spec"]["template"]["spec"].get("securityContext", {})
        if "runAsGroup" in sc:
            assert "runAsUser" in sc, "pod-level runAsGroup without runAsUser breaks the sandbox"


def test_ttyd_container_allows_privilege_escalation_for_sudo():
    # sudo is setuid. With allowPrivilegeEscalation false a student cannot install anything, and
    # the workshop guarantees a dead end the moment they need a tool we did not predict.
    docs = [d for d in yaml.safe_load_all(_read(MANIFEST)) if d]
    dep = next(d for d in docs if d.get("kind") == "Deployment")
    ttyd = next(c for c in dep["spec"]["template"]["spec"]["containers"] if c["name"] == "ttyd")
    assert ttyd["securityContext"]["allowPrivilegeEscalation"] is True


def test_service_requests_an_external_nlb_not_a_classic_elb():
    # Without these annotations the in-tree provider builds a Classic ELB. AWS discourages Classic
    # and the per-region quota is 20 against a fleet need of 50 per account. The older in-tree
    # `aws-load-balancer-type: nlb` must not come back: on a shared VPC it lands in private subnets.
    docs = [d for d in yaml.safe_load_all(_read(MANIFEST)) if d]
    svc = next(d for d in docs if d.get("kind") == "Service")
    ann = svc["metadata"]["annotations"]
    assert ann["service.beta.kubernetes.io/aws-load-balancer-type"] == "external"
    assert ann["service.beta.kubernetes.io/aws-load-balancer-scheme"] == "internet-facing"
    assert ann["service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"] == "ip"


def test_apply_script_installs_a_default_storageclass_before_the_vtt():
    # EKS ships no default StorageClass since 1.30, so the VTT's PVC hangs Pending on a fresh
    # cluster and the terminal never starts. This would have hit all 250 clusters.
    body = _read(os.path.join(VTT_DIR, "apply.sh"))
    assert "gp3-storageclass.yaml" in body
    assert body.index("gp3-storageclass.yaml") < body.index("web-terminal.yaml")


def test_gitea_admin_credentials_are_nested_under_the_gitea_key():
    # The chart reads admin under `gitea:`. Top-level is valid YAML in the wrong place, so helm
    # lint passes and every API call 401s at runtime.
    with open(os.path.join(VTT_DIR, "gitea", "values.yaml"), encoding="utf-8") as fh:
        values = yaml.safe_load(fh)
    assert "admin" in values.get("gitea", {}), "admin must be nested under the gitea key"
    assert "admin" not in {k for k in values if k != "gitea"}


def test_no_manifest_pins_a_workshop_repo_to_github():
    # ArgoCD must reconcile from the in-cluster Gitea. 250 clusters polling one GitHub repo through
    # 5 NAT IPs gets throttled, and a student cannot push to a repo they do not own.
    offenders = []
    platform = os.path.join(REPO_ROOT, "platform")
    for root, _dirs, files in os.walk(platform):
        for name in files:
            if not name.endswith((".yaml", ".yml")):
                continue
            path = os.path.join(root, name)
            text = _read(path)
            if re.search(r"repoURL:\s*\S*github\.com[/:]peopleforrester/packt-agentic-devops", text):
                offenders.append(os.path.relpath(path, REPO_ROOT))
    assert not offenders, f"these Applications still source from GitHub: {offenders}"
