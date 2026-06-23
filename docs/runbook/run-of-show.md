# Run of Show

The per-beat delivery runbook (deliverable D9). Built in Phase 6 and corrected after each rehearsal.

Each beat row carries: clock time, beat ID, what is on screen, Michael's cues (bullets, not a script), what Claude Code does (prompt ID), success signal, time budget, bail-out action, recovery action.

Hard rule: any beat that exceeds its budget by 50 percent triggers its bail-out immediately. No live debugging beyond the one rehearsed failure beat (B03). The audience never watches unrehearsed troubleshooting.

## Timeline

| Clock | Module |
|---|---|
| 0:00 to 0:15 | Opening and ground rules |
| 0:15 to 1:15 | Module 1: cloud-native foundation |
| 1:15 to 1:25 | Break |
| 1:25 to 2:35 | Module 2: the AI plane |
| 2:35 to 2:45 | Break |
| 2:45 to 3:25 | Module 3: self-service |
| 3:25 to 3:35 | Break |
| 3:35 to 4:00 | Wrap: governance, observability, commitment |

## Module 2 bail-out order

Cut from the bottom if overrunning: B12 to recording first, then the B10 dashboard walkthrough shortens to the single trace, then B05 compresses to applied-and-verified. B07, B08, and B09 are never cut.

---

## Opening (0:00 to 0:15)

On screen: title slide, then the bare cluster terminal and the empty ArgoCD UI. No build yet.
Michael says:
- What this is: an AI-native IDP built live on Kubernetes by an agent, governed not unleashed.
- The promise: you can follow on your own cluster, and if your build breaks you rejoin at the next phase boundary. The reference build on screen always carries the session.
- The two LLM roles: the building agent runs on your own plan; the platform's deployed agents call a small in-cluster model with no external spend.
- Ground rule shown, not told: the agent runs on an allowlist; mutating actions ask first.

---

## Module 1: cloud-native foundation (0:15 to 1:15)

### B01 · 0:15 · budget 6 min · prompt P01
- On screen: editor with `components.yaml` and `platform/0-bootstrap/root-app.yaml`.
- Michael says: this manifest is the single source of truth; watch the agent read it and explain the plan before touching anything.
- Agent: reads both files, explains the App-of-Apps and sync waves. Read-only.
- Success signal: a short, correct explanation of root app to per-component apps to sync waves.
- Bail-out (past 9 min): cut the explanation, move to B02.
- Recovery: none needed; read-only beat.

### B02 · 0:21 · budget 20 min · prompt P02
- On screen: ArgoCD UI, sync waves cascading.
- Michael says: this is the bootstrap exception, the one direct apply; everything after flows through Git. Watch the waves: cert-manager first, Backstage last.
- Agent: applies `root-app.yaml` (approval prompt approved on screen), watches to all-green.
- Success signal: foundation plane all Healthy. Validated path: green in well under the 12 min gate; the budget holds narration room.
- Bail-out (past 30 min, non-Backstage app stuck): play the foundation-green recording, pick up at B03.
- Recovery: do not live-debug; B03 is the only sanctioned failure.

### B03 · 0:43 · budget 12 min · prompt P03
- On screen: the one failing Application in ArgoCD, then the values fix and the heal.
- Michael says: this is what platform engineering actually feels like; watch the agent diagnose from status, fix the root cause, and let GitOps heal it.
- Agent: finds the seeded bad Grafana tag, fixes the values file, commits; ArgoCD self-heals.
- Success signal: the app returns to Healthy after the commit, no direct cluster edit.
- Bail-out (past 18 min): play the B03 recording.
- Recovery: if config drifted, the reset script restores the known-good seeded fault before the beat.

### B04 · 0:55 · budget 8 min · no prompt (presenter)
- On screen: Backstage in the browser, catalog populated, TechDocs rendered, ArgoCD plugin showing live sync.
- Michael says: the developer portal is the front door; this is where self-service lands in Module 3.
- Success signal: catalog, TechDocs, and the ArgoCD plugin all render.
- Bail-out (Backstage slow): play the Backstage tour recording; boot is validated in preflight so this is rare.
- Recovery: hot-spare Backstage URL via `promote-spare.sh` if the portal is down.

---

## Module 2: the AI plane (1:25 to 2:35), the centerpiece

### B05 · 1:25 · budget 8 min · prompt P05
- On screen: AI-plane App-of-Apps applied; kgateway Gateway and GatewayClass.
- Michael says: same GitOps path as the foundation, now for the agent infrastructure.
- Agent: applies `ai-plane-app.yaml`, reviews the Gateway API resources once kgateway is Healthy.
- Success signal: kgateway Healthy; Gateway and GatewayClass shown and explained.
- Bail-out (past 12 min): compress to applied-and-verified, skip the resource walk.
- Recovery: on a CRD race, refresh once CRDs are established.

### B06 · 1:33 · budget 6 min · prompt P06
- On screen: agentgateway routing config; mTLS and audit-logging settings.
- Michael says: this is the agentic data plane, a sibling of kgateway, mediating LLM, MCP, and A2A traffic.
- Agent: shows the routing config, confirms mTLS and audit logging on by default.
- Success signal: routing config and the two security defaults shown.
- Bail-out (past 9 min): state the role, move on.
- Recovery: correct any sibling-vs-data-plane or maturity overclaim live.

### B07 · 1:39 · budget 12 min · prompt P07 · NEVER CUT
- On screen: the agent writing a kagent Agent CRD, committing it, ArgoCD reconciling it.
- Michael says: this is the beat. An agent, declared as a Kubernetes resource, deployed by GitOps, written by an agent. Watch the CRD shape.
- Agent: writes the `platform-helper` Agent plus ModelConfig (v1alpha2, `systemMessage` under `spec.declarative`, routed at the in-cluster vLLM), commits, reconciles.
- Success signal: the Agent reaches Ready and is reconciled by ArgoCD, not applied by hand.
- Bail-out: not cut. If the CRD shape drifts, tighten to the rehearsed prompt; worst case reveal the committed `demo-agent.yaml`.
- Recovery: the known-good artifact exists at `platform/2-ai-plane/demo-agent/manifests/demo-agent.yaml`.

### B08 · 1:53 · budget 6 min · prompt P08 · NEVER CUT
- On screen: the agent calling the MCP server through agentgateway; the audit log entry.
- Michael says: the agent reaches a tool through the governed data plane, and it is audited.
- Agent: triggers the agent-to-MCP call via agentgateway; the audit entry appears.
- Success signal: a successful MCP call and its audit-log line on screen.
- Bail-out: not cut. If the audit line lags, the trace in B10 still lands.
- Recovery: confirm the MCP route exists (the server is pre-deployed).

### B09 · 1:59 · budget 6 min · prompt P09 · NEVER CUT
- On screen: the injection fixture sent at the agent; LLM Guard blocking it; the blocked request in the audit log.
- Michael says: governance the agent cannot talk its way past; the block is deterministic and in the repo.
- Agent: fires the committed injection fixture; LLM Guard blocks; the block is audited.
- Success signal: the request is blocked and the block appears in the audit log.
- Bail-out: not cut. If the block is silent, point at the audit line directly.
- Recovery: the verdict is deterministic against pinned v0.3.16; the reset script restores known-good config.

### B10 · 2:05 · budget 8 min · prompt P10
- On screen: the trace in Tempo, spans walked, GenAI attributes; the AI-plane Grafana dashboard.
- Michael says: the call from B08 as telemetry; the model, token counts, and tool calls as span attributes, framed honestly as unstable conventions.
- Agent: opens the trace, walks spans, highlights `gen_ai.*`, loads the dashboard.
- Success signal: trace open with GenAI attributes; dashboard rendered.
- Bail-out (past 12 min): shorten to the single trace, skip the dashboard walk.
- Recovery: fire the call slightly ahead so the trace has propagated.

### B11 · 2:14 · budget 6 min · prompt P11
- On screen: one inference request to vLLM and its response.
- Michael says: a real model, served in-cluster on CPU, behind an OpenAI-compatible endpoint.
- Agent: sends one request to the vLLM endpoint; response appears.
- Success signal: a coherent response. Validated latency: warm about 6s, cold about 11s, inside the 30s gate.
- Bail-out (slow first token): reveal the pre-warmed request fired during B10.
- Recovery: the model is pre-warmed; never let a cold inference die on screen.

### B12 · 2:21 · budget 5 min · no prompt (architecture) · FIRST TO CUT
- On screen: the topology diagram, where llm-d sits as the distributed-inference scheduling layer.
- Michael says: where this goes at scale, with honest Sandbox-maturity framing, not inflated claims.
- Success signal: the audience understands the placement; no live demo required.
- Bail-out: to recording first if Module 2 is over budget.
- Recovery: none; architecture-on-screen.

---

## Module 3: self-service (2:45 to 3:25)

### B13 · 2:45 · budget 12 min · prompt P13
- On screen: the agent completing the `agent-service` scaffolder template.
- Michael says: now the platform builds platforms; a form that generates a governed agent repo.
- Agent: completes the template (form params, fetch:template, catalog-info plus agent manifests), commits.
- Success signal: a valid template committed under `platform/3-self-service/agent-service/`.
- Bail-out (past 18 min): reveal the completed template, narrate the parameters.
- Recovery: the skeleton exists; Gitea host/org are templated and filled at provision time.

### B14 · 2:58 · budget 8 min · prompt P14
- On screen: the agent writing the ApplicationSet that watches Gitea for generated repos.
- Michael says: this is what auto-creates an ArgoCD Application per generated agent repo.
- Agent: writes the ApplicationSet pointed at the in-cluster Gitea org, commits.
- Success signal: ApplicationSet committed at `platform/3-self-service/applicationset.yaml`.
- Bail-out (past 12 min): reveal the committed ApplicationSet.
- Recovery: apply server-side; confirm the Gitea URL.

### B15 · 3:07 · budget 10 min · prompt P15 · one continuous take
- On screen: the golden path, form to trace: portal form, scaffold, repo, ApplicationSet, ArgoCD sync, running agent, first trace.
- Michael says: this closes the loop on the whole workshop; the developer asks, the platform delivers, and it is all audited.
- Agent: presenter plays developer and submits the form; the chain executes. Target under 6 minutes form-to-trace.
- Success signal: a new agent running and its first trace in Tempo.
- Bail-out (any link stalls past budget): cut to the recorded golden-path take.
- Recovery: rehearsed as one take three times; recording is the safety net.

---

## Wrap: governance, observability, commitment (3:35 to 4:00)

### B16 · 3:35 · budget 8 min · prompt P16 · sanctioned mutating kubectl
- On screen: Kyverno flipped to enforce; the violating agent fixture denied.
- Michael says: two layers of governance. The agent asks before applying (agent control), then Kyverno denies it anyway (infrastructure control). Defense in depth, shown not told.
- Agent: enforce mode on; applies the violating fixture (approval prompt on screen); Kyverno denies it.
- Success signal: the approval prompt, then the Kyverno denial.
- Bail-out (past 12 min): play the denial recording.
- Recovery: confirm enforce mode first; each policy ships its violating fixture.

### B17 · 3:44 · budget 6 min · prompt P17
- On screen: the Loki query attributing every action to a named agent identity, including this session's own.
- Michael says: the agent that built the platform shows up in the platform's own audit trail.
- Agent: runs the pre-written Loki query; per-agent attributed actions appear, including the audit-hook lines.
- Success signal: attributed actions including this session's own tool invocations.
- Bail-out (no lines): screenshot fallback from rehearsal.
- Recovery: verify the audit hook shipped during preflight.

### B18 · 3:51 · budget 6 min · no prompt (audience)
- On screen: the commitment prompt and three seeded examples.
- Michael says: the exact wording from the runbook; post one change you will make in your platform within 30 days.
- Success signal: chat activity; the seeded examples break the silence.
- Bail-out: read the three examples and move to close.
- Recovery: none.

### Close · 3:57 · budget 3 min
- Michael says: the repo is the take-home; everything built today is in it, pinned and reproducible. "Tools don't transform organizations. People do."
