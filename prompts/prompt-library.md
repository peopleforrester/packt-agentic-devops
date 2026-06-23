# Prompt Library

Every live Claude Code prompt, rehearsed verbatim. Improvised prompting during delivery is
limited to Q&A. Each prompt maps to a beat ID from the build spec (section 7) and a backup
recording slot.

GitOps rule the prompts assume: Claude Code writes and commits manifests to the platform
repo, then ArgoCD syncs. It does not run mutating `kubectl` directly, with two sanctioned
exceptions: the bootstrap (installing ArgoCD and applying the first App-of-Apps) and the
B16 Kyverno denial demo. The `.claude/settings.json` allowlist enforces this; a mutating
`kubectl` verb triggers an approval prompt on screen, which is itself a teaching beat.

The "Known failure modes" lines below are the anticipated ones, grounded in the build and
the validation runs. Rehearsal (Phase 7) adds the observed ones and confirms the recovery
moves. Re-verify the kagent CRD shape against the pinned chart at the July freeze.

## Format for each entry

- ID, Beat, Prompt (exact text), Expected behavior, Known failure modes, Recovery move.

---

## Module 1: Cloud-native foundation

### P01 (B01) — Read the component manifest and explain the build
**Prompt:**
> Read `components.yaml` and `platform/0-bootstrap/root-app.yaml`. In a few sentences, explain
> how the App-of-Apps pattern is going to deploy this platform: what the root Application
> points at, how the per-component Applications are discovered, and how sync waves order the
> rollout. Do not apply anything yet.

**Expected behavior:** Reads both files, explains that `platform-foundation` points ArgoCD at
`platform/1-foundation` and recurses for `*/application.yaml`, that each component Application is
Helm- or manifest-sourced with a pinned version, and that sync-wave annotations order the
rollout (cert-manager first, Backstage last). Read-only, no tool that mutates the cluster.
**Known failure modes:** Claude offers to apply immediately. It pads the explanation past the
time budget.
**Recovery move:** The prompt says "do not apply yet" and "a few sentences"; if it overruns,
cut it off and move to P02.

### P02 (B02) — Apply the foundation App-of-Apps
**Prompt:**
> Apply the foundation App-of-Apps at `platform/0-bootstrap/root-app.yaml` into the `argocd`
> namespace. This is the bootstrap exception to the GitOps rule. Then watch the ArgoCD UI as
> the sync waves cascade and tell me when the foundation plane is all green.

**Expected behavior:** Runs `kubectl apply -n argocd -f platform/0-bootstrap/root-app.yaml`
(approval prompt appears and is approved on screen), then watches sync status. ArgoCD UI is
the visual centerpiece; waves cascade cert-manager -> secrets/policy -> observability ->
Argo extensions -> Backstage.
**Known failure modes:** Image pull pressure delays a wave. Backstage is last and slowest. A
component flaps Progressing before Healthy.
**Recovery move:** Sync waves are tuned; give it the budgeted time. If a non-Backstage app
hangs past budget, it is a candidate for the recorded backup; do not live-debug here (B03 is
the only sanctioned on-screen failure).

### P03 (B03) — Diagnose and heal the scripted sync failure
**Prompt:**
> One Application is failing to sync. Find which one from the ArgoCD status, read the error,
> and fix the root cause in its values. Commit the fix and watch ArgoCD heal it.

**Expected behavior:** Identifies the pre-seeded fault (a bad Grafana image tag), opens the
values file, corrects the tag to the pinned version, commits to Git. ArgoCD self-heals and
the app goes Healthy. This is the rehearsed-until-boring recovery beat.
**Known failure modes:** Claude fixes a symptom (deletes the pod) instead of the values root
cause. It changes more than the one bad field.
**Recovery move:** If it strays, redirect: "fix it in the values file and commit, do not touch
the cluster directly." The fault and its fix are fixed fixtures; if config drifts, the reset
script restores the known-good seeded fault.

*(B04, Backstage opening in the browser, is a presenter action, not a Claude prompt.)*

---

## Module 2: The AI plane (the centerpiece)

### P05 (B05) — Apply the AI plane and review the gateway
**Prompt:**
> Apply the AI-plane App-of-Apps at `platform/0-bootstrap/ai-plane-app.yaml`. Once kgateway is
> Healthy, show me the Gateway API resources it created and explain what the Gateway and
> GatewayClass represent here.

**Expected behavior:** Applies `platform-ai-plane`; ArgoCD syncs the AI plane (CRDs first via
server-side apply, then controllers). Reviews the kgateway Gateway/GatewayClass and explains
the Gateway API role.
**Known failure modes:** CRDs not established before a dependent Application syncs. Client-side
apply hits the CRD annotation size limit.
**Recovery move:** Sync waves + ServerSideApply handle ordering; if a CRD race appears, a
refresh resolves it once CRDs are established. Budget for the CRD wave.

### P06 (B06) — Review the agentgateway data plane
**Prompt:**
> agentgateway is deployed as the agentic data plane. Show me its routing configuration: how
> it mediates LLM, MCP, and A2A traffic, and confirm mTLS and audit logging are on by default.

**Expected behavior:** Reads the agentgateway config, explains it sits as a sibling of
kgateway mediating agent traffic, and points at the mTLS + audit-logging settings.
**Known failure modes:** Claude conflates agentgateway with kgateway's data plane (it is a
sibling, not kgateway's data plane). It overclaims maturity.
**Recovery move:** Correct the framing live if needed: agentgateway is a Linux Foundation
(Agentic AI Foundation) project, a sibling of kgateway. Honest maturity labels.

### P07 (B07) — Write the kagent Agent CRD  *(the workshop; most rehearsal time)*
**Prompt:**
> Write a kagent Agent that acts as a platform helper: it answers questions about this
> platform's components and golden paths, keeps answers short and concrete, and says so when
> it does not know. Route it at the in-cluster vLLM through a ModelConfig, not any external
> provider. Put it in the `kagent` namespace, commit it under
> `platform/2-ai-plane/demo-agent/manifests/`, and let ArgoCD reconcile it.

**Expected behavior:** Produces the Agent plus its ModelConfig (and the dummy key Secret) with
the exact known-good shape:
- `apiVersion: kagent.dev/v1alpha2`, `kind: Agent`, `spec.type: Declarative`.
- `spec.declarative.systemMessage` (NOT `systemPrompt`), `spec.declarative.modelConfig: vllm-qwen3`.
- ModelConfig `provider: OpenAI`, `model: qwen3-1.7b`, `openAI.baseUrl:
  http://qwen3-predictor.kserve.svc.cluster.local/v1`, key from a Secret (vLLM ignores it).
- The `agentic-platform.io/llm-guard-policy` annotation so it satisfies the Kyverno
  require-llm-guard-reference policy.
Commits to Git; ArgoCD syncs; the agent reconciles like any other resource. An agent,
declared as a Kubernetes resource, deployed by GitOps, written by an agent.
**Known failure modes:** The big ones, all from stale training data: `v1alpha1` instead of
`v1alpha2`; `systemPrompt` instead of `systemMessage`; field not nested under
`spec.declarative`; a real external provider instead of the vLLM ModelConfig; baseUrl pointed
at the wrong Service name.
**Recovery move:** The known-good artifact already lives at
`platform/2-ai-plane/demo-agent/manifests/demo-agent.yaml`. If Claude drifts on the CRD shape,
the prompt is tightened in rehearsal until the output matches; worst case, reveal the
committed file. This prompt gets the most rehearsal of any.

### P08 (B08) — Agent calls an MCP server through agentgateway
**Prompt:**
> Have the platform-helper agent call the MCP server through agentgateway, then show me the
> audit log entry for that call.

**Expected behavior:** Triggers the agent-to-MCP call routed via agentgateway; the audit log
entry appears on screen (the routing and audit are the point).
**Known failure modes:** The MCP server is deployed but not routed. The audit log lag hides the
entry within the time budget.
**Recovery move:** The MCP server is pre-deployed; confirm the route exists. If the audit entry
lags, the trace lands in B10 anyway; do not stall.

### P09 (B09) — Prompt injection blocked by LLM Guard
**Prompt:**
> Send the prompt-injection test fixture at the agent. Show me LLM Guard intercepting and
> blocking it, and the blocked request in the audit log.

**Expected behavior:** Fires the repo's injection fixture; LLM Guard blocks deterministically;
the block shows in the audit log. The exact injection string is a committed fixture so
attendees can reproduce it.
**Known failure modes:** LLM Guard config drift changes the verdict. The block is silent (no
visible audit line).
**Recovery move:** The verdict is deterministic against the pinned v0.3.16 config; if it drifts,
the reset script restores known-good config before the beat.

### P10 (B10) — The trace lands in Tempo
**Prompt:**
> Open the trace from the agent's MCP call in Tempo. Walk the spans and point out the GenAI
> semantic-convention attributes: model, token counts, tool calls. Then load the AI-plane
> Grafana dashboard.

**Expected behavior:** Opens the trace, walks spans, highlights `gen_ai.*` attributes (framed
as current but unstable, Development grade), loads the pre-built dashboard.
**Known failure modes:** The trace has not propagated to Tempo yet. `gen_ai.*` attributes
overclaimed as stable.
**Recovery move:** Fire the call slightly ahead so the trace is present; present GenAI
conventions honestly as unstable. This beat shortens to a single trace under time pressure.

### P11 (B11) — vLLM serves an inference
**Prompt:**
> Send one inference request to the vLLM model through its OpenAI-compatible endpoint and show
> me the response.

**Expected behavior:** One request to `qwen3-predictor.kserve.svc`, response on screen. Model
is pre-warmed. Validated latency: warm ~6s, cold ~11s; under the 30s gate.
**Known failure modes:** Cold model (slow first token). KV-cache/memory pressure (do not raise
KVCACHE on screen).
**Recovery move:** The model is pre-warmed and the request is fired during the preceding beat,
revealed on cue (the pre-warmed-request fallback). Never let a cold inference die on screen.

*(B12, llm-d, is architecture-on-screen, not a Claude prompt: show where distributed inference
sits in the topology, honest Sandbox framing. First to go to recording if Module 2 overruns.)*

---

## Module 3: Self-service

### P13 (B13) — Write the agent-service scaffolder template
**Prompt:**
> Write a Backstage scaffolder template for an `agent-service`. The form takes an agent name,
> purpose, model route, and the MCP tools it is allowed. On submit it generates a repo
> containing a kagent Agent CRD, an agentgateway route, an LLM Guard policy reference, and
> OTel instrumentation defaults. Commit it under `platform/3-self-service/agent-service/`.

**Expected behavior:** Completes the template skeleton: parameters for name/purpose/model/tools,
`fetch:template` over the skeleton, output including `catalog-info.yaml` and the agent
manifests. Commits to Git.
**Known failure modes:** Legacy scaffolder action names. Hardcodes choices the form should
parameterize. Skeleton placeholders (Gitea host/org) left literal.
**Recovery move:** The skeleton exists at `platform/3-self-service/agent-service/`; Claude
completes and wires it. Gitea host/org are templated and filled at provision time.

### P14 (B14) — Write the ApplicationSet
**Prompt:**
> Write the ApplicationSet that watches the in-cluster Gitea for repos generated by this
> template and auto-creates an ArgoCD Application for each. Commit it at
> `platform/3-self-service/applicationset.yaml`.

**Expected behavior:** Produces a Git-generator (or SCM-provider) ApplicationSet pointed at the
in-cluster Gitea org, templating one Application per generated repo.
**Known failure modes:** Generator points at the wrong Gitea URL. ApplicationSet CRD needs
server-side apply (annotation size).
**Recovery move:** Apply server-side. The Gitea org/host are the templated values.

### P15 (B15) — Fire the golden path
**Prompt (presenter plays developer; Claude assists if needed):**
> Through the Backstage portal, request a new agent: fill the form and submit. Then watch the
> chain on screen: scaffolder generates the repo, the ApplicationSet creates the Application,
> ArgoCD syncs it, the agent runs, and the first trace lands in Tempo.

**Expected behavior:** Form-to-trace in one continuous take, target under 6 minutes. Closes the
loop on the whole workshop.
**Known failure modes:** Any link in the chain stalls (scaffold, AppSet detection, sync, trace).
**Recovery move:** Rehearsed as one take three times; if a link stalls past budget, cut to the
recorded golden-path take.

---

## Wrap

### P16 (B16) — Kyverno denies a violating agent  *(sanctioned mutating kubectl)*
**Prompt:**
> Flip the AI-plane Kyverno policies from audit to enforce. Then try to apply the violating
> agent fixture (no LLM Guard reference) and show Kyverno denying it.

**Expected behavior:** Enforce mode on; `kubectl apply` of the violating fixture triggers the
on-screen approval prompt (agent-level control), Claude approves, then Kyverno denies the
resource (infrastructure-level control). Two layers of governance, shown not told.
**Known failure modes:** Policy in audit not enforce (admits the resource). Wrong fixture
(passes policy).
**Recovery move:** Each policy ships a violating fixture; confirm enforce mode first. The denial
is deterministic.

### P17 (B17) — Per-agent attribution in Loki
**Prompt:**
> Run the Loki query that shows every action in this cluster attributed to a named agent
> identity, including this Claude Code session's own actions from the audit hook.

**Expected behavior:** The query returns per-agent attributed actions, including Claude Code's
own tool invocations shipped by the PreToolUse/PostToolUse audit hook. The agent that built the
platform shows up in the platform's own audit trail.
**Known failure modes:** The audit hook did not ship lines (Loki label missing). Query filters
to the wrong label.
**Recovery move:** Verify the hook shipped during preflight; the query is pre-written and fixed.

*(B18, the commitment mechanic, is a chat prompt to the audience with three seeded examples in
the runbook, not a Claude prompt.)*
