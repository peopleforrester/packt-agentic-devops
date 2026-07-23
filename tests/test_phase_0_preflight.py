# ABOUTME: Phase 0 gate. Confirms a bare, correctly-versioned cluster and a valid,
# ABOUTME: fully-pinned components.yaml before any platform install.
import os
import subprocess

from conftest import REPO_ROOT, get_json, kubectl


def test_at_least_one_node_ready():
    obj = get_json("get", "nodes")
    ready = []
    for node in obj.get("items", []):
        conds = node.get("status", {}).get("conditions", [])
        if any(c.get("type") == "Ready" and c.get("status") == "True" for c in conds):
            ready.append(node["metadata"]["name"])
    assert ready, "no Ready nodes"


def test_server_version_is_pinned_line():
    obj = get_json("version")
    git_version = obj.get("serverVersion", {}).get("gitVersion", "")
    assert git_version.startswith(("v1.35", "v1.36")), (
        f"server version {git_version} is not 1.35 or 1.36"
    )


def test_argocd_namespace_absent():
    res = kubectl("get", "namespace", "argocd", check=False)
    assert res.returncode != 0, "argocd namespace already exists; cluster is not bare"


def test_no_argocd_applications_yet():
    # The CRD may not exist on a bare cluster; either way there must be no Applications.
    res = kubectl("get", "applications", "-A", check=False)
    if res.returncode == 0:
        assert res.stdout.strip() in ("", "No resources found"), "Applications already exist"


def test_components_yaml_valid_and_pinned():
    res = subprocess.run(
        ["python3", os.path.join(REPO_ROOT, "scripts", "check_components.py")],
        capture_output=True, text=True,
    )
    assert res.returncode == 0, f"check_components failed: {res.stdout}{res.stderr}"
