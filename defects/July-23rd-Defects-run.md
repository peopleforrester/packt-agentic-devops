# July 23 2026 workshop defects and run report

ABOUTME: Defects, per-student cluster state, and utilization from the live 2026-07-23 Packt
ABOUTME: Agentic DevOps workshop. Student findings aggregated read-only while the run was in progress.

Status: workshop still in progress when this was gathered. Student-reported items were pulled
non-disruptively (read-only exec / kubectl get) so the running sessions were never touched.

## Utilization: provisioned vs used

- **Provisioned clusters: 100** (20 per account across accen-dev, aws1-student31/32/33/34).
- **Claimed by real students: 21** (student2-9, 12-18, 52-57). ~21% of the fleet.
- Test/gate claims: 7. Reserved dead pool rows: 160 (the 250-row pool trimmed to 90 live).
- So 79 clusters were provisioned and never claimed. For a run this size the fleet was heavily
  over-provisioned; the next run can size to registered headcount plus a margin.

## Confirmed platform/solution defects (validated this run)

| # | Area | Defect | Status | Fix |
|---|---|---|---|---|
| D1 | Phase 2 Tempo | 2.10.x returns empty on flushed-block queries (grafana/tempo#6436); trace test fails | CONFIRMED, reproduced | Re-pinned to Tempo 2.9.0 / chart 1.25.0 (shipped) |
| D2 | Phase 2 OTel collector | daemonset mode creates no Service, so the test ingest path `opentelemetry-collector.svc:4318` does not resolve | CONFIRMED | Direction captured: add a Service or switch to deployment mode (not yet applied, verify chart values) |
| D3 | Phase 3 Backstage | catalog empty / `/app/examples/` missing | REFUTED on baseline (student-generated config) | Spec/guidance item |
| D4 | Phase 3 Backstage | `NotAllowedError` fetching catalog-info from Gitea despite `reading.allow` | REFUTED on baseline (allow host mismatch in student config) | Spec/guidance item |
| D5 | Test suite | contract + VTT tests still read `platform/`, which moved to `solution/platform/`; 4 errored, 2 passed vacuously, so the suite stopped guarding the solution | CONFIRMED | Repointed all six refs at `solution/platform/` via one PLATFORM constant (shipped) |
| D6 | VTT terminal | 2Gi ttyd OOM-kills under a real build, dropping the session | CONFIRMED (student54) | Raised to 8Gi in-place on all 100 + admins, manifest bumped (shipped) |
| D7 | VTT terminal | endpoints tab and paste bridge did not land text | CONFIRMED | Robust dual-target paste (later superseded, see D8) |
| D8 | VTT terminal | paste double-pasted in Chrome, did nothing in Firefox (synthetic ClipboardEvent) | CONFIRMED | Use xterm `window.term.paste()`; shipped + deployed to admins |
| D9 | Claim portal | pool held 250 sequential names for 90 live banded clusters; students past ~20 got dead URLs | CONFIRMED | Pool trimmed to 90 live, 13 stuck students released (done live) |
| D10 | Security | terminals are unauthenticated guessable URLs; a student reached the admin cluster | CONFIRMED, GO-LIVE BLOCKER | Fix required before next run (see docs/fleet/09-lessons-learned.md) |
| D11 | Phase 2 test | the trace-test OTLP payload hardcodes `startTimeUnixNano:"1"` (1970), so the span is stored but falls outside Tempo's default search window and `/api/search` misses it | CONFIRMED (student14 diagnosed; payload is in `tests/test_phase_2_observability.py`) | Stamp the probe span with a current time, or widen the search range. Compounds with D1 |
| D12 | Phase 2 Grafana | Tempo and Loki are not provisioned as Grafana datasources by the kube-prometheus-stack values, so the datasource test fails | CONFIRMED by 4 independent students (52, 53, 15, 18) | Add Loki + Tempo datasources to the grafana values in the solution |
| D13 | Agent guidance | the agent tries `eks:CreateAccessEntry` and is denied (by design), which blocks the build early | CONFIRMED, widespread (student7, 54, 55) | Tell the agent up front in the spec/prompt: it is already cluster-admin, do not create access entries |
| D14 | Phase 6 vLLM | the vLLM predictor OOM-kills at a 10Gi limit (KV cache) | CONFIRMED (student17, validated live) | Raise the vLLM InferenceService memory limit |

## Student-reported defects (aggregated from Claude sessions, read-only)

No student wrote a standalone defect file; every finding lives in their Claude session history.
The full session transcripts are staged locally (not committed here, they contain conversation
content). The signal, by theme:

**Phase 2 Tempo trace test dominated the run** (roughly 15 of 21 students hit it). Between them they
independently diagnosed every sub-cause, which is strong corroboration:
- **Upstream 2.10.x query bug (D1):** student4 found "Tempo 2.10 vParquet4 search bug empty results,
  known issue single binary"; student9 "accepted (partialSuccess) never becomes searchable, not the
  timestamp and not the collector"; student12 confirmed "Tempo is receiving the traces
  (tempo_distributor_spans_received_total = 2)".
- **Test payload timestamp (D11):** student14 found the test's OTLP payload hardcodes
  `startTimeUnixNano:"1"`, putting the span outside the search range.
- **Missing Grafana datasources (D12):** student52, 53, 15, 18 all hit "no Tempo/Loki Grafana
  datasources that the test requires".
- **Collector daemonset has no Service (D2):** student18, 56 described the daemonset collector ingest.

**Other confirmed findings:**
- **CreateAccessEntry denial (D13):** student7 ("before any phase can install anything"), student54
  and student55 (full `AccessDeniedException` on `eks:CreateAccessEntry`, both noting it is by design).
- **Backstage NotAllowedError (D4):** student5 dug into `GiteaUrlReader.cjs.js` in the catalog backend.
- **vLLM 10Gi OOM (D14):** student17 ("OOMKilled the pod at KVCACHE with a 10Gi limit, validated live").

The takeaway: the students did the root-cause work the broken contract tests should have caught
before the run. Their sessions are the best source for the exact fixes.

## Per-student cluster state and artifacts (T-90 snapshot; clusters close 3pm CDT / 4pm EDT)

Phase reached is inferred from which ArgoCD Applications are Healthy. "Generated" is the
student-authored manifests found untracked in their `platform/` (their own build output).

| Cluster | Email | Phase | Apps healthy | Student-generated manifests | Claude session |
|---|---|---|---|---|---|
| student2 | prashant.j2@gmail.com | Phase 1 | 6/6 | - | 1.6M |
| student3 | kamathaditya223@gmail.com | Phase 0 | 0/1 | - | none |
| student4 | francislinhares@gmail.com | Phase 2 | 11/11 | argo-events, argo-rollouts, argo-workflows, keda | 3.6M |
| student5 | kaszynska.a.anna@gmail.com | **Phase 8** | 26/26 | demo-agent, kagent-crds, kagent, llm-guard, mcp-server | 4.0M |
| student6 | ccie2246@gmail.com | **Phase 8** | 23/23 | - | 3.7M |
| student7 | helge.tesgaard@gmail.com | Phase 3 | 23/23 | - | 3.2M |
| student8 | nesim@cuburn.com | Phase 0 | 0/1 | - | none |
| student9 | lucian.bumbuc@gmail.com | Phase 3 | 17/17 | - | 2.0M |
| student12 | pkoneru28@gmail.com | Phase 3 | 16/16 | - | 2.8M |
| student13 | michaelrishiforrester@gmail.com (your test) | Phase 0 | 0/1 | - | none |
| student14 | krkumarus@gmail.com | Phase 3 | 23/23 | - | 3.2M |
| student15 | krish90.gv@gmail.com | Phase 3 | 22/23 | - | 3.3M |
| student16 | hari.kulk@gmail.com | Phase 3 | 17/17 | - | 4.6M |
| student17 | n.littlepage@qns.cloud | Phase 2 | 11/11 | - | 2.6M |
| student18 | leandro.n.galo@gmail.com | Phase 2 | 11/11 | - | 1.7M |
| student52 | lastai@lastvirtualdomain.com | Phase 2 | 11/11 | - | 2.1M |
| student53 | srinivasb@shalusri.com | **Phase 8** | 37/38 | - | 3.4M |
| student54 | alexandre.cravid@gmail.com | Phase 1 | 6/6 | - | 1.8M |
| student55 | nareshdahagam@gmail.com | Phase 3 | 21/21 | - | 2.6M |
| student56 | nils.lagerfeld@web.de | Phase 2 | 11/11 | - | 3.6M |
| student57 | hrushipthube10@gmail.com | Phase 0 | 0/1 | - | none |

**Progress: 17 of 21 evolved past the booted state.** Reached Phase 8 (full build): student5,
student6, student53 (37/38 apps). Stuck at Phase 0, never started or abandoned early: student3,
student8 (nesim, had the terminal reconnect trouble), student13 (your own test claim), student57.
The bulk sit at Phase 2 to 3, which is exactly where the Tempo and Backstage defects live.
