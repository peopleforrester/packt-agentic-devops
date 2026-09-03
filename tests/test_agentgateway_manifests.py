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


def test_backend_points_at_the_kserve_predictor():
    backends = [d for _f, d in _manifest_docs() if d["kind"] == "AgentgatewayBackend"]
    assert backends, "no AgentgatewayBackend found"
    for backend in backends:
        provider = backend["spec"]["ai"]["provider"]
        assert provider.get("host", "").startswith("qwen3-predictor."), (
            f"backend host is {provider.get('host')!r}; KServe names the Service after the "
            "InferenceService, so this must be qwen3-predictor.*"
        )
        assert "openai" in provider, "provider key is `openai`, lower case"
