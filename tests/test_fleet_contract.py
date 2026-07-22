# ABOUTME: Static gate on the fleet provisioning contract: the cluster module's node shape, the
# ABOUTME: driver's safety guards, and the state layout that keeps 250 clusters across 5 accounts apart.
#
# These run without AWS on purpose. Every assertion here is a failure someone already paid for on a
# live cluster, and at fleet scale each one would repeat across 250 clusters in five accounts.
import os
import re

import yaml

from conftest import REPO_ROOT

PROVISION = os.path.join(REPO_ROOT, "scripts", "provision")
CLUSTER_TF = os.path.join(PROVISION, "cluster", "main.tf")
LAB_VPC_TF = os.path.join(PROVISION, "lab-vpc", "main.tf")
FLEET_SH = os.path.join(PROVISION, "fleet", "fleet.sh")
FLEET_LIB = os.path.join(PROVISION, "fleet", "lib.sh")
VTT_MANIFEST = os.path.join(PROVISION, "vtt", "web-terminal.yaml")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _code(path):
    # Comments explain what we deliberately do NOT do, so a substring search over the whole file
    # matches the rationale and fails on correct code. Assert against code lines only.
    return "\n".join(
        line for line in _read(path).splitlines() if not line.lstrip().startswith("#")
    )


def _driver():
    # The driver is fleet.sh plus the lib.sh it sources; the guards live in lib.sh so every entry
    # point (fleet.sh, sweep.sh, routes.sh, the gates) inherits them rather than re-implementing.
    return _code(FLEET_SH) + "\n" + _code(FLEET_LIB)


def _tf_variable_block(body, name):
    match = re.search(rf'variable\s+"{name}"\s*\{{(.*?)\n\}}', body, re.S)
    assert match, f"expected a {name} variable to be declared"
    return match.group(1)


# --- Node shape: the disk trap ---------------------------------------------------------------

def test_cluster_module_sizes_root_via_block_device_mappings():
    # terraform-aws-modules/eks manages a launch template for this node group, and disk_size is
    # SILENTLY IGNORED when a launch template exists. A bare disk_size left the root volume at the
    # AL2023 default of 20 GB, DiskPressure evicted the platform, and the cluster looked healthy
    # to terraform the whole time. dev-cluster was fixed; the fleet module must match it.
    body = _code(CLUSTER_TF)
    assert "block_device_mappings" in body, "root volume must be sized via block_device_mappings"
    assert not re.search(r"^\s*disk_size\s*=", body, re.M), (
        "disk_size is silently ignored under a managed launch template; use block_device_mappings"
    )


def test_cluster_root_volume_is_large_enough_for_the_platform():
    # Measured: the full platform pulls ~30 GB of images (the baked vLLM image dominates) for ~35 GB
    # used. The volume must stay under kubelet's 85% image-GC high threshold, so the baked vLLM
    # image is never garbage-collected mid-workshop, and well above the 10% hard-eviction floor.
    body = _read(CLUSTER_TF)
    match = re.search(r"volume_size\s*=\s*(\d+)", body)
    assert match, "no root volume_size found in the cluster module"
    size = int(match.group(1))
    assert size >= 50, f"root volume {size} GB is under the measured 35 GB need plus GC headroom"


def test_cluster_node_group_is_the_single_student_shape():
    body = _code(CLUSTER_TF)
    assert '"t3.2xlarge"' in body, "the per-student shape is one t3.2xlarge"
    for field in ("min_size", "max_size", "desired_size"):
        assert re.search(rf"{field}\s*=\s*1", body), f"{field} must be 1: single-node student cluster"
    assert "AL2023_x86_64_STANDARD" in body, "x86 AMI required: the vLLM image is x86_64"


# --- Pod density: prefix delegation ----------------------------------------------------------

def test_cluster_enables_prefix_delegation_and_raises_max_pods():
    # Without prefix delegation a t3.2xlarge caps at 58 pods and the platform needs ~75, so ~15
    # pods (Backstage, seeds, the kagent agents) stay Pending. AL2023 nodeadm computes max-pods
    # from a static per-instance map that ignores prefix delegation, so BOTH are required.
    body = _code(CLUSTER_TF)
    assert "ENABLE_PREFIX_DELEGATION" in body, "vpc-cni prefix delegation is required"
    assert "maxPods: 110" in body, "nodeadm must set maxPods explicitly; it ignores prefix delegation"


# --- Idempotency on reprovision --------------------------------------------------------------

def test_cluster_does_not_create_the_cloudwatch_log_group():
    # EKS auto-creates the control-plane log group and it survives destroy. If terraform also
    # creates it, reprovisioning a reused cluster name collides on "already exists".
    body = _code(CLUSTER_TF)
    assert re.search(r"create_cloudwatch_log_group\s*=\s*false", body), (
        "let EKS own the log group so a reused name never collides on reprovision"
    )


# --- Workload identity: Pod Identity, not IRSA (D16) -----------------------------------------

def test_cluster_uses_pod_identity_and_creates_no_oidc_provider():
    body = _code(CLUSTER_TF)
    assert re.search(r"enable_irsa\s*=\s*false", body), (
        "D16: Pod Identity, not IRSA. 250 clusters must not create 250 OIDC trust policies"
    )
    assert "eks-pod-identity-agent" in body, "the Pod Identity agent addon is required"


# --- Multi-account safety: nothing may default to one account --------------------------------

def test_cluster_module_requires_an_explicit_profile():
    # A default profile means a driver bug silently applies 50 clusters into whichever account the
    # default names, instead of failing. Across five accounts that is unrecoverable without a sweep.
    # Match an actual `default =` assignment, not the word "default" in the description prose.
    block = _tf_variable_block(_read(CLUSTER_TF), "profile")
    assert not re.search(r"^\s*default\s*=", block, re.M), (
        "profile must have no default; an implicit account is how a fleet lands in the wrong place"
    )


def test_lab_vpc_requires_an_explicit_profile():
    block = _tf_variable_block(_read(LAB_VPC_TF), "profile")
    assert not re.search(r"^\s*default\s*=", block, re.M), "profile must have no default"


# --- Node tagging: the fleet must self-tag ---------------------------------------------------

def test_node_instances_are_tagged_through_the_launch_template():
    # EKS managed node groups do NOT propagate terraform default_tags to the EC2 instances or their
    # volumes. On the validation run those were tagged by hand. At 250 that does not happen, and an
    # untagged instance is invisible to the orphan sweep, which filters on Workshop=packt.
    body = _code(CLUSTER_TF)
    assert "tag_specifications" in body, (
        "node instances must self-tag via the launch template; default_tags do not reach them"
    )


# --- The VTT load balancer: never Classic ----------------------------------------------------

def test_vtt_service_is_an_internet_facing_ip_target_nlb():
    # Un-annotated, the in-tree provider builds a CLASSIC ELB, whose quota is 20 per region against
    # a fleet need of 50 per account. And the OLDER in-tree "nlb" value places the LB in PRIVATE
    # subnets on a shared VPC, where no browser can reach it. Only "external" is correct.
    docs = [d for d in yaml.safe_load_all(_read(VTT_MANIFEST)) if d]
    svc = next(d for d in docs if d.get("kind") == "Service" and d["metadata"]["name"] == "web-terminal")
    ann = svc["metadata"]["annotations"]
    assert ann["service.beta.kubernetes.io/aws-load-balancer-type"] == "external", (
        "must be 'external' (the LB Controller); 'nlb' is the in-tree path and lands in private subnets"
    )
    assert ann["service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"] == "ip"
    assert ann["service.beta.kubernetes.io/aws-load-balancer-scheme"] == "internet-facing"


# --- The driver: guards that make a shared account survivable --------------------------------

def test_driver_refuses_any_name_outside_the_fleet_pattern():
    # The name is the state file, the terraform -var, the IAM role suffix and the resource tag, so a
    # refused name cannot produce an apply, a destroy, or a tagged resource. These accounts are
    # shared: a co-tenant project and Michael's own adwc-dev live alongside the fleet.
    assert re.search(r"\^student\[0-9\]\+\$", _driver()), (
        "assert_ours must pin names to ^student[0-9]+$"
    )


def test_driver_refuses_the_dev_cluster_by_name():
    assert "adwc-dev" in _driver(), "the driver must refuse adwc-dev explicitly; it is not the fleet's"


def test_driver_namespaces_state_by_account():
    # Flat per-name state keyed globally forced a NAME_OFFSET hack on the run this is ported from,
    # and a mismatched offset silently orphaned clusters. Namespacing by account removes the class.
    # Assert the path is built as <root>/<account>/<name>, i.e. two separators, not one.
    body = _driver()
    assert "STATE_ROOT" in body, "state paths must be built from a single rooted constant"
    for fmt in ("%s/%s/%s.tfstate", "%s/%s/%s.account"):
        assert fmt in body, f"state layout must nest by account (expected {fmt})"


def test_driver_persists_account_membership():
    # Recomputing membership from offset arithmetic means passing a different n to down than to up
    # silently orphans clusters. Persist it at apply time and read it back on destroy.
    body = _driver()
    assert ".account" in body, "membership must be persisted per cluster, never recomputed"
    assert "assert_membership_matches" in body, (
        "destroy must verify the persisted account before acting"
    )


def test_destructive_verbs_are_dry_run_unless_explicitly_enabled():
    assert "PACKT_APPLY" in _driver(), "destroy/sweep/reap must be dry-run unless PACKT_APPLY=1"


def test_teardown_drains_load_balancers_before_destroy():
    # Terraform does not own the load balancers Kubernetes created. Skipping the drain orphans ~2 LBs
    # per cluster (400 at 250), and their ENIs hold the subnet so DeleteVpc fails.
    body = _code(FLEET_SH)
    drain = body.index("delete svc")
    destroy = body.index("terraform -chdir=\"${CLUSTER_DIR}\" destroy")
    assert drain < destroy, "LoadBalancer Services must be drained BEFORE terraform destroy"


# --- Every billable resource must be findable by tag ------------------------------------------

def test_dynamically_provisioned_volumes_are_tagged_as_ours():
    # The EBS CSI driver applies only its own kubernetes.io/* tags, so PVC volumes carried no
    # Workshop tag. Measured on the live fleet: 100 of 150 volumes were invisible to the orphan
    # sweep, which selects on Workshop=packt. That is two volumes per cluster, 500 at full size,
    # each one billing after its cluster is gone.
    sc_path = os.path.join(REPO_ROOT, "platform", "0-bootstrap", "gp3-storageclass.yaml")
    sc = yaml.safe_load(_read(sc_path))
    params = sc.get("parameters", {})
    tags = {v for k, v in params.items() if k.startswith("tagSpecification_")}
    assert any(t == "Workshop=packt" for t in tags), (
        "the default StorageClass must tag provisioned volumes Workshop=packt, "
        "or the orphan sweep cannot see them"
    )


def test_sweep_finds_csi_volumes_that_predate_the_storageclass_tags():
    # The StorageClass only tags NEW volumes. Anything already provisioned, or provisioned by a
    # chart bringing its own StorageClass, still needs a selector that does not rely on our tag.
    body = _read(os.path.join(PROVISION, "fleet", "sweep.sh"))
    assert "kubernetes.io/cluster/student" in body, (
        "sweep must also select CSI volumes by their kubernetes.io/cluster/<name> tag"
    )


# --- The P03 workshop fixture -----------------------------------------------------------------

def test_p03_seeded_fault_exists():
    # P03 is the single sanctioned on-screen failure: "one Application is failing to sync, find
    # it and fix the root cause in its values". The prompt library documented a pre-seeded bad
    # Grafana image tag, but no such fault existed anywhere in the platform tree, so Claude would
    # have correctly reported everything healthy and the demo beat would have had nothing to do.
    # This test exists so the fixture cannot silently disappear again.
    app = os.path.join(REPO_ROOT, "platform", "1-foundation", "kube-prometheus-stack",
                       "application.yaml")
    doc = yaml.safe_load(_read(app))
    grafana = doc["spec"]["source"]["helm"]["valuesObject"]["grafana"]
    tag = grafana.get("image", {}).get("tag")
    assert tag, "P03 needs a deliberately broken Grafana image tag; none is set"
    assert tag != "13.0.2", (
        "the Grafana tag has been 'fixed' in the repo. P03 depends on it being broken; "
        "13.0.2 is the value the STUDENT supplies during the workshop"
    )


def test_p03_fault_documents_the_correct_value():
    # A fixture nobody can repair is a liability. The correct tag must be discoverable from the
    # file itself, so a presenter recovering live does not have to go spelunking in a chart.
    app = os.path.join(REPO_ROOT, "platform", "1-foundation", "kube-prometheus-stack",
                       "application.yaml")
    body = _read(app)
    assert "13.0.2" in body, "the correct Grafana tag must be documented alongside the fault"
    assert "P03" in body, "the fixture must say which prompt depends on it"
