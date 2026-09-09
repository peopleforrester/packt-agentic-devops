# ABOUTME: Validates the agentgateway custom resources against the CRD schemas vendored in
# ABOUTME: charts-vendor, so a schema mistake fails here instead of at sync time on a cluster.
#
# Every one of these assertions exists because the first draft of these manifests got it wrong, and
# each mistake produces the same unhelpful symptom: the Application syncs, the resource is rejected
# or silently ignored, and the gateway has no data path. Reading the CRD is the only way to know.
import glob
import os
import tarfile

import pytest

yaml = pytest.importorskip("yaml")
jsonschema = pytest.importorskip("jsonschema")

from conftest import REPO_ROOT

CRD_CHART = os.path.join(REPO_ROOT, "charts-vendor", "agentgateway-crds-v1.3.0.tgz")
MANIFEST_GLOB = os.path.join(
    REPO_ROOT, "solution", "platform", "2-ai-plane", "agentgateway-runtime", "manifests", "*.yaml"
)


def _load_crd_schemas():
    """Return {(group, version, kind): openAPIV3Schema} from the vendored CRD chart."""
    schemas = {}
    with tarfile.open(CRD_CHART) as tar:
        for member in tar.getmembers():
            if not member.name.endswith(".yaml"):
                continue
            handle = tar.extractfile(member)
            if handle is None:
                continue
            for doc in yaml.safe_load_all(handle.read()):
                if not doc or doc.get("kind") != "CustomResourceDefinition":
                    continue
                spec = doc["spec"]
                for version in spec["versions"]:
                    schemas[(spec["group"], version["name"], spec["names"]["kind"])] = (
                        version["schema"]["openAPIV3Schema"]
                    )
    return schemas


def _manifest_docs():
    for path in sorted(glob.glob(MANIFEST_GLOB)):
        for doc in yaml.safe_load_all(open(path)):
            if doc:
                yield os.path.basename(path), doc


@pytest.fixture(scope="module")
def crd_schemas():
    assert os.path.exists(CRD_CHART), f"vendored CRD chart missing: {CRD_CHART}"
    schemas = _load_crd_schemas()
    assert schemas, "no CRD schemas found in the vendored chart"
    return schemas


def test_manifests_exist():
    docs = list(_manifest_docs())
    kinds = {d["kind"] for _f, d in docs}
    assert "Gateway" in kinds, "no Gateway: the controller would have no data path"
    assert "AgentgatewayBackend" in kinds, "no backend for the model endpoint"
    assert "AgentgatewayPolicy" in kinds, "no prompt-guard policy"


def test_every_agentgateway_cr_validates(crd_schemas):
    checked = 0
    failures = []
    for filename, doc in _manifest_docs():
        api_version = doc.get("apiVersion", "")
        if "/" not in api_version:
            continue
        group, version = api_version.split("/", 1)
        key = (group, version, doc.get("kind"))
        if key not in crd_schemas:
            # Gateway API types come from a different source; covered by their own assertions below.
            continue
        errors = sorted(
            jsonschema.Draft202012Validator(crd_schemas[key]).iter_errors(doc),
            key=lambda e: list(e.path),
        )
        checked += 1
        for err in errors:
            path = ".".join(str(p) for p in err.path) or "<root>"
            failures.append(f"{filename}:{doc['kind']}/{doc['metadata']['name']} {path}: {err.message}")
    assert checked, "no agentgateway CRs were validated; the group or version has changed"
    assert not failures, "CRs do not match the vendored CRD schemas:\n  " + "\n  ".join(failures)


def test_api_group_is_agentgateway_dev():
    # The group is `agentgateway.dev`. `gateway.agentgateway.dev` looks plausible and is wrong;
    # the API server rejects it and the resource never exists.
    for filename, doc in _manifest_docs():
        if doc["kind"].startswith("Agentgateway"):
            assert doc["apiVersion"].startswith("agentgateway.dev/"), (
                f"{filename}: {doc['kind']} uses {doc['apiVersion']}"
            )


def test_listener_allows_routes_from_other_namespaces():
    # `Same` silently refuses every generated agent route, because those live in `kagent`.
    gateways = [d for _f, d in _manifest_docs() if d["kind"] == "Gateway"]
    assert gateways, "no Gateway found"
    for gateway in gateways:
        for listener in gateway["spec"]["listeners"]:
            frm = listener.get("allowedRoutes", {}).get("namespaces", {}).get("from")
            assert frm != "Same", (
                f"listener {listener['name']} uses from: Same, which refuses the kagent routes "
                "the golden path generates"
            )


def test_the_selector_has_something_that_satisfies_it():
    docs = list(_manifest_docs())
    gateways = [d for _f, d in docs if d["kind"] == "Gateway"]
    labelled = {}
    for _f, doc in docs:
        if doc["kind"] == "Namespace":
            labelled[doc["metadata"]["name"]] = doc["metadata"].get("labels", {})
    for gateway in gateways:
        for listener in gateway["spec"]["listeners"]:
            ns = listener.get("allowedRoutes", {}).get("namespaces", {})
            if ns.get("from") != "Selector":
                continue
            wanted = ns["selector"]["matchLabels"]
            satisfied = any(
                all(labels.get(k) == v for k, v in wanted.items()) for labels in labelled.values()
            )
            assert satisfied, (
                f"listener {listener['name']} selects {wanted} but no namespace here carries it, "
                "so no route can attach"
            )


def test_prompt_guard_fails_closed():
    # A guardrail that fails open is one an attacker only has to knock over.
    # Scoped to policies that carry a prompt guard. An AgentgatewayPolicy may instead configure
    # access logging, tracing or TLS parameters, and those legitimately have no guard block.
    policies = [
        d for _f, d in _manifest_docs()
        if d["kind"] == "AgentgatewayPolicy"
        and "promptGuard" in (d["spec"].get("backend", {}).get("ai", {}) or {})
    ]
    assert policies, "no prompt-guard AgentgatewayPolicy found"
    for policy in policies:
        guard = policy["spec"]["backend"]["ai"]["promptGuard"]
        for side in ("request", "response"):
            entries = guard.get(side) or []
            assert entries, f"{policy['metadata']['name']} has no {side} guard"
            for entry in entries:
                mode = entry["webhook"].get("failureMode")
                assert mode == "FailClosed", (
                    f"{policy['metadata']['name']} {side} guard failureMode is {mode!r}; "
                    "unreachable scanner must refuse, not pass unscanned"
                )


def test_ai_backend_points_at_the_kserve_predictor():
    # Scoped to AI backends on purpose. An AgentgatewayBackend may instead carry `mcp`, `a2a`,
    # `aws` or `static`, and the MCP backend legitimately points somewhere else.
    backends = [
        d for _f, d in _manifest_docs()
        if d["kind"] == "AgentgatewayBackend" and "ai" in d["spec"]
    ]
    assert backends, "no AI AgentgatewayBackend found"
    for backend in backends:
        provider = backend["spec"]["ai"]["provider"]
        assert provider.get("host", "").startswith("qwen3-predictor."), (
            f"backend host is {provider.get('host')!r}; KServe names the Service after the "
            "InferenceService, so this must be qwen3-predictor.*"
        )
        assert "openai" in provider, "provider key is `openai`, lower case"


def test_mcp_backend_targets_the_mcp_server():
    # MCP tool calls must traverse the gateway too. A backend with no targets renders a route that
    # accepts traffic and forwards it nowhere.
    backends = [
        d for _f, d in _manifest_docs()
        if d["kind"] == "AgentgatewayBackend" and "mcp" in d["spec"]
    ]
    assert backends, "no MCP AgentgatewayBackend: agent tool calls would have to go direct"
    for backend in backends:
        targets = backend["spec"]["mcp"].get("targets") or []
        assert targets, f"{backend['metadata']['name']} declares no MCP targets"
        for target in targets:
            assert target.get("name"), "each MCP target requires a name"


# --- governance fixtures and the policy that judges them -----------------------------------------

# Fixtures live beside the component they exercise, as a SIBLING of manifests/. The Application
# syncs manifests/ only, so a fixture meant to be refused is never reconciled. That convention
# already existed here; this follows it rather than introducing a second one under tests/.
FIXTURE_DIR = os.path.join(
    REPO_ROOT, "solution", "platform", "2-ai-plane", "ai-policies", "fixtures")
AGENT_POLICY = os.path.join(
    REPO_ROOT, "solution", "platform", "1-foundation", "policy-baseline",
    "manifests", "require-agent-controls.yaml",
)


def _required_agent_annotations():
    policy = yaml.safe_load(open(AGENT_POLICY))
    pattern = policy["spec"]["rules"][0]["validate"]["pattern"]
    return set(pattern["metadata"]["annotations"])


def test_no_application_syncs_a_fixtures_directory():
    """The invariant that keeps fixtures safe is not where they sit, it is that nothing reconciles
    them. A fixture meant to be refused would otherwise be re-applied forever and present as a
    permanently failing Application rather than a passing test.

    Fixtures live beside their component, and each Application points at that component's
    manifests/ subdirectory, so fixtures/ is a sibling that is never synced. This asserts the
    property directly rather than matching on a path string, so moving a fixture cannot quietly
    break it.
    """
    for name in ("violating-agent.yaml", "known-good-agent.yaml"):
        assert os.path.exists(os.path.join(FIXTURE_DIR, name)), f"missing fixture: {name}"

    synced_paths = []
    for app_file in glob.glob(
        os.path.join(REPO_ROOT, "solution", "platform", "**", "application.yaml"), recursive=True
    ):
        for doc in yaml.safe_load_all(open(app_file)):
            if not doc or doc.get("kind") != "Application":
                continue
            path = (doc.get("spec", {}).get("source", {}) or {}).get("path")
            if path:
                synced_paths.append(path)

    assert synced_paths, "no Application source paths found; the check would pass vacuously"
    offenders = [p for p in synced_paths if "fixtures" in p.split("/")]
    assert not offenders, (
        f"an Application reconciles a fixtures directory: {offenders}. Fixtures that exist to be "
        "rejected must never be synced."
    )


def test_bad_fixture_actually_violates_the_policy():
    required = _required_agent_annotations()
    bad = yaml.safe_load(open(os.path.join(FIXTURE_DIR, "violating-agent.yaml")))
    present = set(bad["metadata"].get("annotations") or {})
    missing = required - present
    assert missing, (
        "violating-agent satisfies every annotation the policy requires, so it would be ADMITTED "
        f"and the denial demo would prove nothing. required={sorted(required)}"
    )
    # Exactly one missing, so a denial is attributable to a specific rule rather than to
    # "this manifest is broken in several ways".
    assert len(missing) == 1, (
        f"violating-agent is missing {sorted(missing)}; it should differ from known-good in one "
        "thing only, or the denial does not tell you which rule fired"
    )


def test_good_fixture_satisfies_the_policy():
    # The control. Without it, a policy that denies everything still passes the denial test.
    required = _required_agent_annotations()
    good = yaml.safe_load(open(os.path.join(FIXTURE_DIR, "known-good-agent.yaml")))
    present = set(good["metadata"].get("annotations") or {})
    missing = required - present
    assert not missing, f"known-good-agent is missing required annotations: {sorted(missing)}"


def test_the_two_fixtures_differ_only_in_the_guardrail_annotation():
    # If they differ in other ways, a denial could be caused by something other than the policy.
    bad = yaml.safe_load(open(os.path.join(FIXTURE_DIR, "violating-agent.yaml")))
    good = yaml.safe_load(open(os.path.join(FIXTURE_DIR, "known-good-agent.yaml")))
    assert bad["apiVersion"] == good["apiVersion"]
    assert bad["kind"] == good["kind"] == "Agent"
    assert bad["spec"]["type"] == good["spec"]["type"]
    assert bad["spec"]["declarative"]["modelConfig"] == good["spec"]["declarative"]["modelConfig"]


def test_agent_policy_ships_as_audit():
    # Install first, enforce last. An admission rule that rejects the platform's own workloads
    # before they are installed stalls the build and looks like a broken component.
    policy = yaml.safe_load(open(AGENT_POLICY))
    action = policy["spec"]["rules"][0]["validate"]["failureAction"]
    assert action == "Audit", (
        f"require-agent-controls ships as {action!r}; it must ship as Audit and be flipped to "
        "Enforce deliberately during the governance beat"
    )


def test_every_shipped_agent_satisfies_the_policy_it_enforces():
    # The reference agent violated ai-require-otel-annotations while the agents readers generate
    # from the golden path did not. The platform must not break the rule it teaches.
    required = _required_agent_annotations()
    agent_files = glob.glob(
        os.path.join(REPO_ROOT, "solution", "platform", "**", "*.yaml"), recursive=True
    )
    checked = 0
    for path in agent_files:
        # Fixtures are deliberately non-compliant; they are never synced and must be skipped or
        # this asserts the opposite of what the fixture exists to prove.
        if os.sep + "fixtures" + os.sep in path:
            continue
        for doc in yaml.safe_load_all(open(path)):
            if not doc or doc.get("kind") != "Agent":
                continue
            # Skeleton files carry ${{ values.* }} placeholders; annotations are still literal.
            present = set(doc["metadata"].get("annotations") or {})
            missing = required - present
            checked += 1
            assert not missing, (
                f"{os.path.relpath(path, REPO_ROOT)}: Agent "
                f"{doc['metadata'].get('name')} is missing {sorted(missing)}"
            )
    assert checked, "no Agent manifests found to check"


def test_generated_applications_use_the_scoped_project():
    appset = yaml.safe_load(open(os.path.join(
        REPO_ROOT, "solution", "platform", "3-self-service", "applicationset.yaml")))
    project = appset["spec"]["template"]["spec"]["project"]
    assert project != "default", (
        "generated Applications target the `default` project, which permits any repo, any "
        "namespace and any resource kind"
    )


def test_audit_logging_is_actually_configured():
    """The claim that agentgateway applies audit logging was made in reader-facing text long before
    anything configured it. The chart has no audit value key and no runtime policy set one, so the
    statement was simply false. This asserts the configuration exists, so the claim and the
    behaviour cannot drift apart again.
    """
    policies = [
        d for _f, d in _manifest_docs()
        if d["kind"] == "AgentgatewayPolicy"
        and (d["spec"].get("frontend", {}) or {}).get("accessLog")
    ]
    assert policies, (
        "no AgentgatewayPolicy configures frontend.accessLog. Reader-facing text says agent "
        "traffic is audited; without this it is not."
    )
    for policy in policies:
        otlp = policy["spec"]["frontend"]["accessLog"].get("otlp")
        assert otlp, f"{policy['metadata']['name']} logs nowhere; accessLog needs an otlp sink"
        assert otlp.get("backendRef", {}).get("name"), "otlp requires a backendRef name"


def test_mtls_gateway_validates_client_certificates():
    """The mTLS Gateway must validate client certs, and must do it the way the current API expects.

    This replaces a test that asserted the OPPOSITE. That test was written after checking
    listeners[].tls.frontendValidation, finding it absent from current Gateway API releases, and
    concluding client-cert mTLS was impossible. It is not: frontendValidation was the v1.3.0
    experimental spelling, removed in v1.4.0 because the capability moved to a Gateway-wide
    spec.tls.frontend, which is in the STANDARD channel. Checking one plausible field and reporting
    its absence as a capability gap cost a correct chapter's worth of claims.

    So this asserts the thing that is true rather than forbidding the thing that looked false.
    """
    gateways = [d for _f, d in _manifest_docs()
                if d["kind"] == "Gateway" and (d["spec"].get("tls") or {}).get("frontend")]
    assert gateways, (
        "no Gateway configures spec.tls.frontend. Reader-facing text says agent traffic is "
        "mTLS-protected; without this it is not."
    )
    for gw in gateways:
        validation = gw["spec"]["tls"]["frontend"]["default"]["validation"]
        assert validation["mode"] == "AllowValidOnly", (
            f"{gw['metadata']['name']} uses mode {validation['mode']!r}. AllowInsecureFallback "
            "accepts clients with no valid certificate, which defeats the control entirely."
        )
        refs = validation.get("caCertificateRefs") or []
        assert refs, "client validation needs a CA to validate against"
        for ref in refs:
            assert ref.get("name"), "each caCertificateRef needs a name"


def test_mtls_uses_the_current_field_not_the_removed_one():
    """Guard against reintroducing listeners[].tls.frontendValidation.

    It was removed in Gateway API v1.4.0. A manifest using it is not rejected: unknown fields are
    pruned by the API server against a structural schema, so the mTLS configuration would silently
    vanish and the Gateway would serve without client validation while every Application stayed
    green. Silent is the whole problem.
    """
    offenders = []
    for filename, doc in _manifest_docs():
        if doc["kind"] != "Gateway":
            continue
        for listener in doc["spec"].get("listeners", []):
            if "frontendValidation" in (listener.get("tls") or {}):
                offenders.append(f"{filename}: listener {listener.get('name')}")
    assert not offenders, (
        "these use listeners[].tls.frontendValidation, removed in Gateway API v1.4.0. It is pruned "
        "silently rather than rejected, so mTLS would be absent with no error: " + ", ".join(offenders)
    )


# --- the component count, which must come from the thing that deploys --------------------------

def test_stated_component_counts_match_components_yaml():
    """Any prose stating how many components there are must agree with components.yaml.

    Three sources previously gave three answers: components.yaml said 30, the prose enumeration
    came to 31, and the stated total in two customer-facing documents said 33. Nothing added up to
    33. The machine-readable file is authoritative because it is the one that actually deploys, so
    this asserts the prose against it rather than the other way round.

    Written as digits and as words, because "Thirty-three components" appeared in event copy and a
    digit-only check would have walked straight past it.
    """
    import re

    manifest = yaml.safe_load(open(os.path.join(REPO_ROOT, "components.yaml")))
    actual = len(manifest["components"])

    words = {
        "twenty": 20, "twenty-five": 25, "twenty-seven": 27, "twenty-eight": 28,
        "twenty-nine": 29, "thirty": 30, "thirty-one": 31, "thirty-two": 32,
        "thirty-three": 33, "thirty-four": 34, "thirty-five": 35,
    }
    digit_re = re.compile(r"\b(\d{2})\s+components\b", re.I)
    word_re = re.compile(r"\b(twenty|thirty)(-[a-z]+)?\s+components\b", re.I)

    offenders = []
    for root in (os.path.join(REPO_ROOT, "docs"), os.path.join(REPO_ROOT, "README.md")):
        paths = [root] if os.path.isfile(root) else glob.glob(
            os.path.join(root, "**", "*.md"), recursive=True)
        for path in paths:
            for lineno, line in enumerate(open(path, errors="replace"), 1):
                # Historical statements about a different event are not claims about this platform.
                if "kcd" in line.lower() or "predecessor" in line.lower():
                    continue
                found = []
                for m in digit_re.finditer(line):
                    found.append(int(m.group(1)))
                for m in word_re.finditer(line):
                    key = (m.group(1) + (m.group(2) or "")).lower()
                    if key in words:
                        found.append(words[key])
                for n in found:
                    if n != actual:
                        offenders.append(
                            f"{os.path.relpath(path, REPO_ROOT)}:{lineno} says {n}, "
                            f"components.yaml has {actual}"
                        )
    assert not offenders, (
        "stated component counts contradict components.yaml:\n  " + "\n  ".join(offenders)
    )


# --- the drift policy, whose failure modes are all silent ----------------------------------------

def test_drift_policy_matches_on_the_tracking_annotation():
    """The drift policy must scope on ArgoCD's tracking ANNOTATION, not a label.

    ArgoCD here uses annotation tracking, so managed resources never carry
    app.kubernetes.io/instance. A label-based selector makes the policy inert: it loads, reports
    healthy, matches nothing, and anything can drift. That is the failure this asserts against,
    and it was found on a live cluster only because someone dry-ran a patch that should have been
    refused and was not.
    """
    path = os.path.join(
        REPO_ROOT, "solution", "platform", "1-foundation", "policy-baseline",
        "manifests", "block-argocd-drift.yaml")
    policy = yaml.safe_load(open(path))
    rule = policy["spec"]["rules"][0]
    preconditions = str(rule.get("preconditions"))
    assert "argocd.argoproj.io/tracking-id" in preconditions, (
        "the drift policy does not gate on the tracking-id annotation, so it either matches "
        "nothing or matches ArgoCD's own bootstrap components"
    )
    for res in rule["match"]["any"]:
        selector = str(res.get("resources", {}).get("selector", ""))
        assert "app.kubernetes.io/instance" not in selector, (
            "label-based selection makes this policy inert under annotation tracking"
        )


def test_drift_policy_cannot_block_the_controllers_it_protects():
    """Excluding the reconcilers is load-bearing, not defensive tidiness.

    Denying every non-ArgoCD principal on UPDATE/DELETE also blocks kubelet and the built-in
    controllers from maintaining the object, and blocks kagent from reconciling the Deployments it
    generates, which inherit the Agent's tracking-id. In the sibling repo that silently froze agent
    OTel configuration with no error naming a policy.
    """
    path = os.path.join(
        REPO_ROOT, "solution", "platform", "1-foundation", "policy-baseline",
        "manifests", "block-argocd-drift.yaml")
    rule = yaml.safe_load(open(path))["spec"]["rules"][0]
    subjects = rule["exclude"]["any"][0]["subjects"]
    names = {s.get("name") for s in subjects}
    for required in ("argocd-application-controller", "kagent-controller",
                     "system:serviceaccounts:kube-system", "system:nodes"):
        assert required in names, f"drift policy does not exclude {required}"

    # background scans carry no userInfo, so a background evaluation would ignore every exclude
    # above and match everything.
    policy = yaml.safe_load(open(path))
    assert policy["spec"]["background"] is False, (
        "background must be false: userInfo-based excludes are unavailable to background scans"
    )


# --- committed but unreconciled: the silent kind of dead manifest -------------------------------

def test_every_committed_manifest_is_actually_synced_by_something():
    """A manifest nothing reconciles is invisible: no error, no Degraded app, just absent behaviour.

    This caught a real one. The self-service Application used include: "applicationset.yaml", so a
    committed AppProject was never applied while the ApplicationSet pointed its generated
    Applications at that very project. Every generated Application would have failed with "project
    does not exist" and the parent Application would have stayed Synced and Healthy throughout.

    The check is deliberately narrow: for each Application that pins an `include` filter, assert
    every top-level manifest in the directory it syncs is matched by that filter. Directories
    synced without a filter take everything and need no assertion.
    """
    import fnmatch

    problems = []
    for app_file in glob.glob(
        os.path.join(REPO_ROOT, "solution", "platform", "**", "*.yaml"), recursive=True
    ):
        for doc in yaml.safe_load_all(open(app_file)):
            if not isinstance(doc, dict) or doc.get("kind") != "Application":
                continue
            source = doc.get("spec", {}).get("source", {}) or {}
            include = (source.get("directory") or {}).get("include")
            path = source.get("path")
            if not include or not path:
                continue
            # Application paths are repo-relative under platform/; the reference build is at
            # solution/platform/.
            local = os.path.join(REPO_ROOT, "solution", path)
            if not os.path.isdir(local):
                continue
            # Brace globs: ArgoCD accepts {a,b}; fnmatch does not, so expand them.
            patterns = [include]
            if include.startswith("{") and include.endswith("}"):
                patterns = [p.strip() for p in include[1:-1].split(",")]
            for entry in sorted(os.listdir(local)):
                full = os.path.join(local, entry)
                if not os.path.isfile(full) or not entry.endswith((".yaml", ".yml")):
                    continue
                if not any(fnmatch.fnmatch(entry, pat) for pat in patterns):
                    problems.append(
                        f"{doc['metadata']['name']}: {path}/{entry} is committed but excluded by "
                        f"include={include!r}, so nothing applies it"
                    )
    assert not problems, "committed manifests that no Application syncs:\n  " + "\n  ".join(problems)


def test_appproject_is_created_before_the_applicationset_that_uses_it():
    base = os.path.join(REPO_ROOT, "solution", "platform", "3-self-service")
    project = yaml.safe_load(open(os.path.join(base, "appproject.yaml")))
    appset = yaml.safe_load(open(os.path.join(base, "applicationset.yaml")))

    target = appset["spec"]["template"]["spec"]["project"]
    assert target == project["metadata"]["name"], (
        f"the ApplicationSet generates into project {target!r} but the committed AppProject is "
        f"{project['metadata']['name']!r}"
    )

    def wave(doc):
        return int(doc["metadata"].get("annotations", {}).get("argocd.argoproj.io/sync-wave", 0))

    assert wave(project) < wave(appset), (
        "the AppProject must sync before the ApplicationSet; an Application naming a project that "
        "does not exist yet is rejected and the set retries"
    )
