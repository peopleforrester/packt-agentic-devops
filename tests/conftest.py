# ABOUTME: Shared pytest helpers for the phase gate tests. All cluster access goes
# ABOUTME: through an explicit kubeconfig and a context guard, never the shared default.
import json
import os
import subprocess

import pytest

KUBECONFIG_FILE = os.environ.get("KUBECONFIG_FILE", "")
EXPECTED_CONTEXT = os.environ.get("EXPECTED_CONTEXT", "")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "integration: needs a fully built cluster and in-cluster traffic"
    )


def _run(args, timeout=60):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def needs_cluster():
    if not KUBECONFIG_FILE:
        pytest.skip("KUBECONFIG_FILE not set; cluster tests skipped")


@pytest.fixture(scope="session", autouse=True)
def _guard_context():
    # Verify we are pointed at the expected cluster before any test touches it.
    if not KUBECONFIG_FILE:
        return
    res = _run(["kubectl", "--kubeconfig", KUBECONFIG_FILE, "config", "current-context"])
    ctx = res.stdout.strip()
    if EXPECTED_CONTEXT and EXPECTED_CONTEXT not in ctx:
        pytest.exit(
            f"ABORT: context '{ctx}' does not match EXPECTED_CONTEXT '{EXPECTED_CONTEXT}'",
            returncode=2,
        )


def kubectl(*args, check=True, timeout=60):
    """Run kubectl bound to the explicit kubeconfig. Skips if none is set."""
    needs_cluster()
    res = _run(["kubectl", "--kubeconfig", KUBECONFIG_FILE, *args], timeout=timeout)
    if check and res.returncode != 0:
        raise AssertionError(f"kubectl {' '.join(args)} failed: {res.stderr.strip()}")
    return res


def get_json(*args):
    return json.loads(kubectl(*args, "-o", "json").stdout)


def app_status(name):
    obj = get_json("get", "application", name, "-n", "argocd")
    status = obj.get("status", {})
    return (
        status.get("sync", {}).get("status"),
        status.get("health", {}).get("status"),
    )


def assert_apps_healthy(*names):
    bad = []
    for name in names:
        sync, health = app_status(name)
        if sync != "Synced" or health != "Healthy":
            bad.append(f"{name}={sync}/{health}")
    assert not bad, "not Synced/Healthy: " + ", ".join(bad)


def crd_established(name):
    obj = get_json("get", "crd", name)
    conds = obj.get("status", {}).get("conditions", [])
    return any(c.get("type") == "Established" and c.get("status") == "True" for c in conds)


def incluster_curl(url, *curl_args, ns="default", timeout=120):
    """One-shot in-cluster curl. Returns stdout (body then a trailing http code)."""
    pod = "phasetest-curl-" + str(abs(hash(url)) % 100000)
    res = kubectl(
        "run", pod, "-n", ns, "--rm", "-i", "--restart=Never",
        "--image=curlimages/curl:8.11.0", "--command", "--",
        "curl", "-sS", "-m", "30", "-w", "\\n%{http_code}", *curl_args, url,
        check=False, timeout=timeout,
    )
    return res.stdout
