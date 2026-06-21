# ABOUTME: Phase 3 gate. Backstage and the delivery extensions healthy, the catalog and
# ABOUTME: ArgoCD plugin answering, and the extension CRDs established.
import json

import pytest

from conftest import assert_apps_healthy, crd_established, incluster_curl


def test_portal_apps_healthy():
    assert_apps_healthy(
        "backstage", "keda", "argo-workflows", "argo-events", "argo-rollouts"
    )


def test_extension_crds_established():
    for crd in (
        "scaledobjects.keda.sh",
        "workflows.argoproj.io",
        "sensors.argoproj.io",
        "rollouts.argoproj.io",
    ):
        assert crd_established(crd), f"CRD not Established: {crd}"


@pytest.mark.integration
def test_backstage_catalog_returns_entities():
    body = incluster_curl(
        "http://backstage.backstage.svc:7007/api/catalog/entities",
        ns="backstage",
    )
    payload = body.rsplit("\n", 1)[0]
    entities = json.loads(payload)
    assert isinstance(entities, list) and len(entities) >= 1, "catalog returned no entities"


@pytest.mark.integration
def test_backstage_argocd_plugin_returns_apps():
    body = incluster_curl(
        "http://backstage.backstage.svc:7007/api/proxy/argocd/api/v1/applications",
        ns="backstage",
    )
    assert '"items"' in body or "metadata" in body, "ArgoCD plugin proxy returned no apps"
