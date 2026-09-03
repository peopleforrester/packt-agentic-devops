<!-- ABOUTME: Authoritative mapping from the names the book uses for tests and scripts to the -->
<!-- ABOUTME: names in this repo, so the book text can be corrected mechanically. -->

# Book-to-repo name mapping

The book refers to several test files by names this repo does not use. The **repo names are
canonical** and the book text should be corrected to match them.

Repo names follow `spec/phases/phase-N-*.md`, so a reader working phase by phase runs the test whose
number matches the phase they are on. The book's names were written before that alignment settled.

## Tests

| Book says | Repo file | Covers |
|---|---|---|
| `test_phase_4_runtime.py`, `test_gateway_contract.py` | `tests/test_phase_4_ai_gateway.py` | Gateway API CRDs established, kgateway and agentgateway pods ready, AI policies in Audit, a Gateway programmed |
| `test_agent_ready.py` | `tests/test_phase_5_agent_runtime.py` | Agent CRD is `v1alpha2`, demo agent reconciled Ready, injection fixture blocked by LLM Guard, `gen_ai` spans reach the collector |
| `test_mcp_contract.py` | `tests/test_phase_5_agent_runtime.py` | MCP assertions live with the agent runtime rather than in a separate file |
| `test_phase_6_serving.py` | `tests/test_phase_6_model_serving.py` | InferenceService Ready, `SYS_NICE` and `VLLM_CPU_KVCACHE_SPACE` present, chat completions answer with the served model, inference trace carries model and tokens |
| `test_golden_path.py` | `tests/test_phase_7_self_service.py` | ApplicationSet exists, template registered in the catalog, ApplicationSet generates Applications, generated agents governed |
| `test_contract.py` | `tests/test_phase_7_self_service.py` | The service contract is asserted as part of the golden path |
| `test_observability.py` | `tests/test_phase_2_observability.py` | Observability plane, asserted at the phase where it is built |

Two names in the book have no single counterpart because the assertions were merged into the phase
file rather than split out: `test_gateway_contract.py` and `test_mcp_contract.py`. Splitting them
back out would create files that duplicate a phase gate, so the book should cite the phase test.

Not referenced by the book, present here, and worth citing:

| Repo file | Covers |
|---|---|
| `tests/test_phase_8_governance.py` | Policies flipped to Enforce, violating agent denied, good agent admitted, Loki has agent tool invocations |
| `tests/test_fleet_contract.py` | Static manifest defect classes, no cluster required |
| `tests/test_version_gate.py` | The Kubernetes version floor, no cluster required |
| `tests/test_vtt_provisioning.py` | Workshop distribution machinery |

## Scripts

| Book says | Status |
|---|---|
| `scripts/check_components.py` | Present, with `scripts/test_check_components.py` |
| `scripts/probe_model.py` | **Added.** Asks `/v1/models` what is actually served and compares to the expected id |
| `scripts/inference_probe.py` | **Added.** Sends a real completion; separates "Ready" from "answers" |
| `scripts/benchmark_inference.py` | **Added.** Sequential latency percentiles, cold first request reported separately |
| `scripts/trace_probe.py` | **Added.** Distinguishes no traces from traces missing `gen_ai.*` attributes |
| `scripts/verify_audit_event.py` | **Added.** Counts audit lines and how many are attributable |
| `scripts/requirements-trace.txt` | **Added.** One pinned dependency |

## Fixtures

The book names `fixtures/missing-guardrail.yaml`, `fixtures/injection-fixture.yaml`,
`tests/fixtures/agent-missing-owner.yaml` and `tests/fixtures/agent-known-good.yaml`. This repo puts
fixtures **beside the component they exercise**, as a sibling of `manifests/`, because each
Application syncs `manifests/` only and a fixture that exists to be rejected must never be
reconciled.

| Book says | Repo file |
|---|---|
| `fixtures/missing-guardrail.yaml`, `tests/fixtures/agent-missing-owner.yaml` | `solution/platform/2-ai-plane/ai-policies/fixtures/violating-agent.yaml` |
| `tests/fixtures/agent-known-good.yaml` | `solution/platform/2-ai-plane/ai-policies/fixtures/known-good-agent.yaml` |
| `fixtures/injection-fixture.yaml` | `solution/platform/2-ai-plane/llm-guard/fixtures/injection-fixture.yaml` |

Three more exist that the book does not cite: `violating-endpoint.yaml`, `violating-otel.yaml`,
`violating-image.yaml`, one per AI policy.

Shared plumbing lives in `scripts/_cluster.py`; the pure logic is covered by `scripts/test_probes.py`,
which needs no cluster.

## Why not rename the repo files instead

Renaming would break the alignment with `spec/phases/`, which is what a reader follows, and would
orphan any existing link to a test file. The mapping is one table; the alignment is structural.
