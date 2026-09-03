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
    policies = [d for _f, d in _manifest_docs() if d["kind"] == "AgentgatewayPolicy"]
    assert policies, "no AgentgatewayPolicy found"
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
