# ABOUTME: Phase 2 gate. Observability stack healthy, storage bound, the collector on
# ABOUTME: every node, Grafana datasources wired, and a trace reaching Tempo.
import json

import pytest

from conftest import assert_apps_healthy, get_json, incluster_curl, kubectl


def test_observability_apps_healthy():
    assert_apps_healthy(
        "kube-prometheus-stack", "loki", "tempo",
        "opentelemetry-operator", "opentelemetry-collector",
    )


def test_prometheus_and_alertmanager_pvcs_bound():
    obj = get_json("get", "pvc", "-n", "observability")
    relevant = [
        p for p in obj.get("items", [])
        if any(k in p["metadata"]["name"] for k in ("prometheus", "alertmanager"))
    ]
    assert relevant, "no Prometheus/Alertmanager PVCs found"
    for pvc in relevant:
        phase = pvc.get("status", {}).get("phase")
        assert phase == "Bound", f"{pvc['metadata']['name']} is {phase}, not Bound"


def test_collector_daemonset_ready_on_each_node():
    obj = get_json("get", "daemonset", "opentelemetry-collector-agent", "-n", "observability")
    status = obj.get("status", {})
    desired = status.get("desiredNumberScheduled", 0)
    ready = status.get("numberReady", 0)
    assert desired > 0 and ready == desired, f"collector ready {ready}/{desired}"


@pytest.mark.integration
def test_grafana_has_loki_and_tempo_datasources():
    pw = kubectl(
        "get", "secret", "-n", "observability", "-l", "app.kubernetes.io/name=grafana",
        "-o", "jsonpath={.items[0].data.admin-password}",
    ).stdout
    import base64
    password = base64.b64decode(pw).decode() if pw else ""
    url = "http://admin:%s@kube-prometheus-stack-grafana.observability.svc/api/datasources" % password
    body = incluster_curl(url, ns="observability")
    types = []
    try:
        types = [d.get("type") for d in json.loads(body.rsplit("\n", 1)[0])]
    except Exception:
        pass
    assert "loki" in types and "tempo" in types, f"datasources found: {types}"


@pytest.mark.integration
def test_trace_reaches_tempo():
    # Push a minimal OTLP/HTTP trace through the collector, then search Tempo for it.
    otlp = (
        '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name",'
        '"value":{"stringValue":"phase2-probe"}}]},"scopeSpans":[{"spans":[{'
        '"traceId":"00000000000000000000000000abc123","spanId":"0000000000abc123",'
        '"name":"phase2-probe-span","kind":1,"startTimeUnixNano":"1","endTimeUnixNano":"2"}]}]}]}'
    )
    incluster_curl(
        "http://opentelemetry-collector.observability.svc:4318/v1/traces",
        "-X", "POST", "-H", "Content-Type: application/json", "--data", otlp,
        ns="observability",
    )
    found = incluster_curl(
        "http://tempo.observability.svc:3200/api/search",
        "--get", "--data-urlencode", 'q={ resource.service.name = "phase2-probe" }',
        ns="observability",
    )
    assert "traceID" in found or "phase2-probe" in found, "probe trace not found in Tempo"
