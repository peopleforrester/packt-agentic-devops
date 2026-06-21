# Phase gate tests

One file per build phase. Each asserts the phase's spec test criteria against a live
cluster. Run them as the gate at the end of each phase.

## Running

All cluster access uses an explicit kubeconfig and verifies the context first (never the
shared default). Set both:

```bash
export KUBECONFIG_FILE=/tmp/<cluster>.kubeconfig
export EXPECTED_CONTEXT=<substring of the cluster context, e.g. adwc>
uv run --with pytest --with pyyaml python -m pytest tests/ -q
```

Without `KUBECONFIG_FILE`, the cluster-dependent tests skip (only the components-pinned
check in phase 0 runs). If the current context does not contain `EXPECTED_CONTEXT`, the
run aborts before touching anything.

## Markers

Tests tagged `integration` need a fully built cluster and in-cluster traffic (a trace
reaching Tempo, an injection blocked at agentgateway, a golden-path run). Skip them for a
fast structural gate:

```bash
uv run --with pytest python -m pytest tests/ -m "not integration" -q
```

## Note

A few integration checks assume response contracts (the agentgateway audit log, the
agent route path, the Loki agent-identity label) that should be confirmed against the
live deployment before the freeze; they are marked and commented in place.
