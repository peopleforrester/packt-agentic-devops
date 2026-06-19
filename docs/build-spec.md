# Build Spec: Agentic DevOps with Claude (Packt, July 23, 2026)

**Spec version:** 1.1 (revised June 15, 2026: backbone resolved to Amazon EKS with one cluster per student, vcluster removed, versions pinned, ingress-nginx and MetalLB dropped, CNCF and CRD facts corrected against June 2026 research. See `docs/research-findings-june-2026.md`.)
**Owner:** Michael Rishi Forrester
**Executor:** Claude Code
**Target repo:** `github.com/peopleforrester/agentic-devops-with-claude`
**Hard deadline:** All Phase gates green by July 16, 2026. Final rehearsal July 20 or 21. Delivery July 23, 9:00 AM EDT.

---

## How to use this file

This is the single source of truth for building the workshop. Claude Code: read this entire file before writing anything. Work phase by phase. Each phase ends with a verification gate. Do not start the next phase until the current gate passes. When this spec says STOP AND ASK, stop and ask Michael. Do not improvise around an open decision.

Verify current Claude Code configuration capabilities (CLAUDE.md behavior, settings, permissions, hooks, subagents) against the Claude Code docs at code.claude.com/docs/en (the old docs.claude.com/en/docs/claude-code path redirects there) before generating any Claude Code config files. The verified June 2026 schema is recorded in `docs/research-findings-june-2026.md` section 6. Do not rely on memory for product details.

---

## 1. What this is

A four-hour live virtual workshop for Packt, up to 300 attendees, one presenter, no TAs. Attendees watch and optionally follow along as Claude Code builds a 33-component AI-native Internal Developer Platform on a real Kubernetes cluster: a cloud-native foundation (Backstage, the Argo stack, the OTel observability plane, policy and secrets tooling) plus an AI plane (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry with OTel GenAI semantic conventions, KServe with vLLM, llm-d).

The meta-narrative is the product: Claude Code is the agent doing the platform engineering work, live. Every artifact this spec produces either makes that live performance reliable or makes the take-home repo worth keeping.

The predecessor (27 components, KCD Texas, May 15, 2026) proved the format. This build extends it with the seven AI-plane components and hardens it for a four-hour solo-delivery virtual format.

---

## 2. Non-negotiable constraints (the solo-delivery doctrine)

These override everything else in this spec. If a design choice conflicts with one of these, the design choice loses.

1. **Students build on their own clusters; that is the workshop.** Each attendee builds the platform on their own provided cluster with their own agentic CLI, driven by the spec. The presenter's pre-staged sandbox is the guaranteed reference and the recorded backups are the safety net, so a broken or slow attendee build never breaks the session: the attendee watches the beat, picks up the known-good state at the next phase boundary, and keeps going. The reliability guarantee lives on the presenter side; the hands-on build is the attendee experience.
2. **Every live demo beat has three layers of safety:** a checkpoint to reset to, a reset script that runs in under 5 minutes, and a recorded backup video of the exact beat.
3. **Nothing is built from source live.** Backstage, custom images, anything with a long build: pre-built, pre-pushed, pre-pulled.
4. **Nothing waits on the network live.** All images pre-pulled to node caches or served from a mirror registry. All Helm charts vendored into the repo.
5. **No secrets on screen, ever.** Presenter API keys live in environment variables loaded before OBS starts. The repo contains zero real credentials. Sealed Secrets and External Secrets Operator handle the in-cluster story.
6. **Claude Code runs governed, not unleashed.** Explicit permission allowlists in project settings. Never `--dangerously-skip-permissions` on screen. This is a teaching beat, not just hygiene: the workshop about agent governance demonstrates agent governance on its own agent.
7. **Every timing block has a bail-out point.** If a beat overruns its budget, the runbook says exactly what gets cut and what gets played from recording.

---

## 3. Deliverables inventory

By the end of this build, the following exist and pass their gates:

| ID | Deliverable | Phase |
|---|---|---|
| D1 | Companion repo `agentic-devops-with-claude`, public, MIT licensed | 1 |
| D2 | `components.yaml` manifest, the single source of truth for the components, with CI pinned-version check | 1 |
| D3 | Foundation plane: App-of-Apps deploying all foundation components, sync-clean on a fresh cluster | 2 |
| D4 | AI plane: seven components deployed via the same GitOps path, all demo beats working | 3 |
| D5 | Self-service plane: Backstage scaffolder template for agent provisioning, ApplicationSet wiring, golden path end to end | 4 |
| D6 | Governance assets: Kyverno AI-plane policies, Loki per-agent attribution queries, Grafana dashboards | 5 |
| D7 | Delivery engineering: checkpoint tags, reset scripts, `copy-paste-commands.md`, preflight script, smoke test script | 6 |
| D8 | Claude Code live-driving kit: repo `CLAUDE.md`, project settings with permission allowlist, audit hook, prompt library | 6 |
| D9 | Run-of-show runbook with per-beat timing budgets and bail-out rules | 6 |
| D10 | Backup video checklist (recordings are Michael's job; the checklist and naming scheme are yours) | 6 |
| D11 | Attendee-facing README, prerequisites doc, and catch-up guide | 6 |
| D12 | Two full timed rehearsal reports | 7 |

---

## 4. Repository specification

```
agentic-devops-with-claude/
├── CLAUDE.md                      # Claude Code project memory (see section 10)
├── .claude/
│   └── settings.json              # permission allowlist, hooks config
├── README.md                      # attendee-facing, written last
├── LICENSE                        # MIT
├── components.yaml                # single source of truth, 33 entries
├── versions.lock.md               # pinned chart and image versions, generated at build time
├── docs/
│   ├── prerequisites.md
│   ├── catch-up-guide.md
│   ├── architecture.md            # one diagram source (Excalidraw export) + prose
│   ├── alternative-paths.md       # GPU acceleration, Amazon Bedrock (documented, not demoed)
│   └── runbook/
│       ├── run-of-show.md         # D9
│       ├── preflight-checklist.md
│       └── failure-recovery.md
├── platform/
│   ├── bootstrap/                 # ArgoCD install + root App-of-Apps
│   ├── foundation/                # one directory per foundation component
│   ├── ai-plane/                  # one directory per AI component
│   └── self-service/              # Backstage templates, ApplicationSets
├── charts-vendor/                 # vendored Helm charts (constraint 4)
├── prompts/
│   └── prompt-library.md          # every live Claude Code prompt, IDs P01..Pnn
├── scripts/
│   ├── provision/                 # cluster provisioning automation
│   ├── reset/                     # reset-to-checkpoint scripts
│   ├── preflight.sh
│   ├── smoke-test.sh
│   └── mirror-images.sh
└── copy-paste-commands.md         # attendee catch-up path, numbered, idempotent
```

Branch strategy: `main` is the delivered state. Checkpoints are annotated git tags: `checkpoint/module-0-start`, `checkpoint/module-1-end`, `checkpoint/module-2-end`, `checkpoint/module-3-end`. Reset scripts target these tags.

Naming: descriptive kebab-case everywhere. No UUIDs, no `final-v2` suffixes.

---

## 5. Component manifest

`components.yaml` enumerates the components, each with: name, plane (foundation, ai, self-service), upstream project URL, chart source, pinned version, namespace, and the module in which it appears live. The goal is the right set of components for a real AI-native IDP, not a target number. The count is whatever the right set adds up to. Do not engineer the list to hit a specific number.

Enumeration starting point:

**Foundation (26):**
1. Backstage core
2. Backstage TechDocs
3. Backstage software catalog
4. Backstage scaffolder
5. GitHub OAuth integration
6. ArgoCD plugin for Backstage
7. ArgoCD
8. Argo Workflows
9. Argo Events
10. Argo Rollouts
11. Sealed Secrets
12. Score
13. KEDA
14. External Secrets Operator
15. cert-manager
16. Kyverno
17. ingress-nginx (NOT VIABLE: end of life March 24, 2026, see count note below)
18. MetalLB (NOT VIABLE on EKS: AWS owns the LB layer, see count note below)
19. kube-prometheus-stack (umbrella)
20. Prometheus
21. Grafana
22. AlertManager
23. Loki
24. Tempo
25. OpenTelemetry Collector
26. Self-service templates and ApplicationSets

**AI plane (7):**
27. kgateway
28. agentgateway
29. kagent
30. LLM Guard
31. OpenLLMetry + OTel GenAI semantic conventions
32. KServe + vLLM
33. llm-d

Two forcing facts found during June 2026 research now drive the count, on top of the original overlap tension:

- ingress-nginx (item 17) reached end of life on March 24, 2026. The repo is read-only with no security patches, and the planned successor InGate was abandoned. It cannot ship as a live component.
- MetalLB (item 18) is decorative on EKS. AWS owns the load balancer and VIP layer through the AWS Load Balancer Controller, so MetalLB is inert at best and conflicting at worst.

The EKS-native replacement for both is the AWS Load Balancer Controller (one component covering ingress and LB). The stack also needs the AWS EBS CSI driver for PersistentVolumes (Prometheus, Loki, Tempo, Grafana), which the original list omitted.

Resolved: drop ingress-nginx and MetalLB. Add the AWS Load Balancer Controller as the EKS-native ingress and LB path, and the AWS EBS CSI driver for PersistentVolumes. Platform ingress can route through kgateway and Gateway API (kgateway is already in the AI plane) to keep a vendor-neutral ingress story on screen, with the AWS Load Balancer Controller provisioning the NLB in front. The exact list is a build detail, not a marketing number.

The kube-prometheus-stack umbrella ships Prometheus, Grafana, and AlertManager, so counting those as separate line items is a presentation choice. List them in whatever way reads honestly; do not pad or trim to hit a number.

CI check: a GitHub Action that fails if any `components.yaml` entry lacks a pinned version. No count assertion.

Version pinning: versions are resolved and recorded in `docs/research-findings-june-2026.md` as of June 15, 2026, and will seed `versions.lock.md`. Re-resolve once during the week of July 13, then freeze. No version changes after the freeze. Do not invent versions.

---

## 6. Infrastructure specification

### 6.0 Platform decision (resolved)

The backbone is Amazon EKS. One cluster per student, provisioned and provided live, up to 300 concurrent. The EKS control plane is managed by AWS. Each cluster runs a managed node group of T3 workers for the system and platform components. vcluster is not used. The provisioning automation in `scripts/provision/` targets EKS only.

Kubernetes version: pin to 1.35 or 1.36 (both in standard EKS support through the workshop horizon; 1.33 exits standard support July 29, 2026). cert-manager 1.20 requires K8s 1.31 or newer, satisfied by either pin. See `docs/research-findings-june-2026.md` section 5 for the EKS provisioning detail (add-ons, Pod Identity, eksctl vs terraform-aws-eks).

### 6.1 Presenter sandbox (the cluster that matters)

- One primary EKS cluster, sized to run all components plus a CPU-mode vLLM model with headroom. See section 6.6 for node group sizing and the vLLM worker question.
- One hot-spare cluster, pre-synced to `checkpoint/module-0-start`, promoted by a single script if the primary dies. The spare is non-negotiable. Four hours live with 300 people watching is exactly when a control plane decides to have a bad day.
- Both clusters pre-pull every image in `components.yaml` via `mirror-images.sh` plus a DaemonSet pre-puller.
- Load balancing and ingress: on EKS the AWS Load Balancer Controller is the LB and ingress path. It provisions an NLB for Service type=LoadBalancer and an ALB for Ingress, and supports Gateway API. MetalLB is not used on EKS: AWS owns the LB and VIP layer, so MetalLB is decorative at best and conflicting at worst. ingress-nginx is not used either: it reached end of life on March 24, 2026, the repo is read-only, and its planned successor InGate was abandoned. State both facts plainly in `architecture.md`.

### 6.2 Attendee clusters

Requirements:
- Browser-delivered terminal and kubeconfig, zero local setup (same promise as KCD Texas).
- Up to 300 concurrent environments, provisioned and warm before 9:00 AM EDT, torn down 2 hours after the session closes (session runs 9:00 AM to 1:00 PM EDT, so teardown is approximately 3:00 PM EDT). Environments do not persist for take-home; the repo is the take-home.
- Each environment is a bare cluster: up, with credentials handed to the attendee, and nothing else. ArgoCD is not installed and the repo is not cloned. The attendee's own agentic CLI, driven by the spec, installs ArgoCD, clones the repo, and builds every phase. Precedent: at KCD Texas the full build took about 20 minutes from a bare cluster.
- Per the doctrine, if attendee environments fail at scale, the workshop proceeds untouched.

### 6.3 Provisioning platform (resolved: EKS)

Resolved. One EKS cluster per student. The provisioning automation builds and tears down identical EKS clusters at scale. Working tool choice: terraform-aws-eks v21.20.0 for a declarative, state-tracked fleet, or eksctl v0.226.0 for imperative spin-up and teardown driven by a templated cluster config. EKS Blueprints is patterns-only since v5 and is not a provisioning framework. Self-managed Karpenter is not used: for 300 fixed-shape, short-lived clusters it adds a per-cluster controller for no benefit. Managed node groups carry the node layout.

Use EKS Pod Identity, not IRSA, for the AWS Load Balancer Controller. IRSA needs one OIDC provider and a per-cluster trust policy, which is 300 of them. Pod Identity uses a generic reusable trust policy with a simple per-cluster association.

### 6.4 Registry and rate limits

300 clusters pulling public images simultaneously will hit Docker Hub rate limits. Mandatory: either a pull-through cache registry baked into the provisioning, or every image re-hosted under a GHCR namespace controlled by Michael, referenced explicitly in all manifests. `mirror-images.sh` automates the re-hosting. No manifest in the repo references docker.io directly.

### 6.5 GitHub OAuth at scale

The Backstage GitHub OAuth integration works cleanly for the presenter. For 300 attendees it does not (each would need an OAuth app or membership in a demo org). Resolution: presenter cluster runs real GitHub OAuth; attendee clusters run Backstage guest auth with the OAuth wiring present in config but commented, with a doc note explaining the swap. This keeps the promise honest: the integration is demonstrated live, and attendees get the exact config to enable it at home.

### 6.6 Node group sizing (resolved: T3)

Layout per cluster: managed EKS control plane plus a node group of 2 to 3 T3 workers (t3.xlarge or t3.2xlarge), with the vLLM workload landing on a t3.2xlarge. T3 stays for the whole cluster. The reasons:

- T3 is the last Intel (x86) instance in the burstable T family. t3a is AMD, and t4g moves to ARM Graviton. The vLLM CPU image is x86 (`vllm-openai-cpu:...-x86_64`) and ARM CPU inference is less mature, so staying on T3 keeps the inference path on well-supported x86.
- The burstable-throttling concern does not bite this workload in practice. T3 throttles to baseline only after CPU credits are exhausted under sustained load. The inference beat is short and bursty (a small model answering one or a few prompts), and T3 Unlimited is the default, so the node keeps bursting through the demo. This is a bursty demo, not a sustained inference server.
- The cold-start risk is handled by pre-warming the model (weights loaded into vLLM before the beat) plus the pre-warmed-request fallback in section 7.2.

Not used: a dedicated non-burstable compute node per cluster (unnecessary for a short bursty demo and off the x86 T-series path), and per-cluster Karpenter mix-and-match (adds a controller to all 300 clusters and introduces 1 to 2 minutes of live node spin-up inside a timed beat).

Validate at the Phase 3 gate: benchmark Qwen3-1.7B on t3.2xlarge CPU against the latency gate (first token within 10 seconds). If it misses, drop to Qwen3-0.6B. Right-size the node count during Phase 2.

### 6.7 Demo agent model routing and credentials

The kagent demo agent (B07) needs a model to call. Where it calls and with whose credentials is resolved as follows.

Attendee clusters (all of them): the agent's kagent `ModelConfig` uses `provider: OpenAI` with `openAI.baseUrl: http://vllm.kserve.svc/v1`, pointing at the in-cluster vLLM that the workshop already serves. The model name must match vLLM's `--served-model-name` (set it to a clean string like `qwen3-1.7b`). vLLM runs without `--api-key` on the cluster network, so the kagent `apiKeySecret` fields carry a dummy value. Result: zero external API spend, zero external credentials, nothing to leak, and the same config across 300 identical clusters. This is also a faithful production pattern: self-hosted inference behind an OpenAI-compatible endpoint. Do not create per-cluster IAM users or per-cluster static-key secrets. That is secret sprawl with no real spend cap.

Presenter cluster: demonstrate one real cloud route to teach credential handling and spend control, where the blast radius is one cluster. Two acceptable routes:
- Amazon Bedrock via EKS Pod Identity: one IAM role, no static key, scoped by IAM to `bedrock:InvokeModel` on a single cheap model ID. Pair with an AWS Budget alert, and say plainly on screen that the budget is an alert, not a real-time cap (Bedrock billing data lags 8 to 24 hours), so the IAM model-id allowlist is the actual guardrail. This is honest, teachable governance.
- Anthropic API behind a LiteLLM proxy: a dedicated Anthropic workspace with a Console monthly spend limit (a genuine hard stop, the API returns 429 when exceeded) plus a LiteLLM virtual key with `max_budget` for a second request-level cap. Pin and test a known-good LiteLLM version against a live budget-enforcement test; there are open budget-bypass bugs, so do not run latest unverified.

Either presenter route teaches the lesson (workload identity or a secret-managed key, plus a real ceiling) without exposing attendee clusters to spend. See `docs/research-findings-june-2026.md` section 7 for the verified ModelConfig YAML and the spend-control detail.

---

## 7. Module build specs

Each module section below defines what gets built ahead of time, what happens live, and the demo beats with their safety layers. Every live beat gets an ID matching an entry in `prompts/prompt-library.md` and a backup recording slot in the checklist.

### 7.1 Module 1: Cloud-native foundation (0:15 to 1:15)

**Pre-staged:** Everything in `platform/foundation/` exists in the repo before the workshop. The cluster starts bare, mirroring the attendee start state. ArgoCD and the foundation are built live during the module.

**Live beats:**
- **B01:** Claude Code reads `components.yaml` and explains the App-of-Apps structure it is about to apply. Prompt P01.
- **B02:** Claude Code applies the root App-of-Apps. ArgoCD UI on screen, sync waves cascade. This is the visual centerpiece of Module 1.
- **B03:** Deliberate, scripted failure: one Application is pre-seeded with a values error (pick something visually obvious, like a bad image tag on Grafana). Claude Code diagnoses the sync failure from ArgoCD status, fixes the values file, commits, watches it heal. Prompt P03. This beat is rehearsed until boring.
- **B04:** Backstage opens in the browser, catalog populated, TechDocs renders, ArgoCD plugin shows live sync state.

**Sync wave engineering:** Order the waves so dependencies never race: cert-manager and MetalLB first, then ingress and secrets tooling, then observability, then Argo extensions, then Backstage last. 33 apps syncing at once can stampede a small API server; tune ArgoCD controller settings (`--kubectl-parallelism-limit`, repo server replicas) and document the tuning in `architecture.md`, because that tuning is itself teachable content.

**Gate:** fresh cluster from `module-0-start` to all-foundation-green in under 12 minutes, three consecutive runs.

### 7.2 Module 2: The AI plane (1:25 to 2:35), the centerpiece

**Pre-staged:** All seven component directories in `platform/ai-plane/`, the model image pre-pulled, the MCP demo server deployed but not yet routed.

**Live beats:**
- **B05:** kgateway installed via App-of-Apps extension; Gateway API resources reviewed by Claude Code on screen. Prompt P05.
- **B06:** agentgateway deployed as the agentic data plane. Show the routing config that mediates LLM, MCP, and A2A traffic. mTLS and audit logging on by default.
- **B07:** Claude Code writes a kagent Agent CRD live from a prompt describing the agent's job (suggested: a cluster-doctor agent that reads pod events and reports). The CRD commits to Git and reconciles through ArgoCD like everything else. This is the single most important beat of the workshop: an agent, declared as a Kubernetes resource, deployed by GitOps, written by an agent. Prompt P07 gets the most rehearsal time of any prompt. Get the CRD shape exactly right (verified June 2026, kagent v0.9.7): apiVersion `kagent.dev/v1alpha2` (not v1alpha1), the field is `systemMessage` (not `systemPrompt`), nested under `spec.type` and `spec.declarative`, with `runtime` python (Google ADK, the default since the AutoGen migration) and a `modelConfig` reference. Tools attach via `type: McpServer` with a `RemoteMCPServer` reference. Re-verify the CRD against the live kagent docs at the July freeze.
- **B08:** The kagent agent calls an MCP server through agentgateway. The audit log entry appears on screen.
- **B09:** Prompt injection demo. A scripted malicious prompt goes at the agent; LLM Guard intercepts and blocks. The blocked request appears in the audit log. The exact injection string lives in the repo as a test fixture so attendees can reproduce it. Expected result is deterministic; if LLM Guard config drifts, the reset script restores known-good config.
- **B10:** The OTel trace from B08 lands in Tempo. Open the trace, walk the spans, show GenAI semantic convention attributes (model, token counts, tool calls). Pre-built Grafana dashboard for the AI plane loads.
- **B11:** KServe + vLLM serves the CPU-mode model. One inference request, response on screen. Latency gate below.
- **B12:** llm-d shown as the scheduling layer: where distributed inference sits in the topology. This beat is allowed to be architecture-on-screen rather than a deep demo; llm-d at CNCF Sandbox maturity gets honest framing, not inflated claims.

**CPU model selection.** Default model of record: `Qwen/Qwen3-1.7B`, with `Qwen/Qwen3-0.6B` as the backup (same architecture and vLLM code path, one-line model-id swap, about 3x faster). These replace the spec's original trio (Qwen2.5-0.5B, SmolLM2-360M, TinyLlama-1.1B), all of which Qwen3 now outclasses. Disable thinking mode (`enable_thinking=false`) so CPU latency stays low and the output is direct chat. Serve via the prebuilt CPU image `vllm/vllm-openai-cpu:v0.23.0-x86_64` with `--device cpu --dtype bfloat16`, `VLLM_CPU_KVCACHE_SPACE` 8 to 16, and the `SYS_NICE` capability on the pod (thread binding is blocked by seccomp without it). Benchmark in Phase 3.

Gate: first visible token within 10 seconds, full response within 30, on t3.2xlarge (the resolved node, section 6.6). The plan, in order of safety:
- Serve Qwen3-1.7B live on t3.2xlarge with the model pre-warmed (weights loaded before the beat). This is the target.
- If the Phase 3 benchmark misses the gate, drop to Qwen3-0.6B served live.
- Safety net regardless: the pre-warmed request pattern, where the request is fired during the preceding beat and the response is revealed on cue. The runbook says so.

Do not let a slow CPU inference stall die on screen. The pre-warmed fallback exists for exactly this.

**Module 2 bail-out order** (cut from the bottom if overrunning): B12 goes to recording first, then B10 dashboard walkthrough shortens to the single trace, then B05 compresses to applied-and-verified. B07, B08, B09 are never cut; they are the workshop.

**Gate:** full Module 2 sequence executes end to end in under 55 minutes in rehearsal, twice.

### 7.3 Module 3: Self-service (2:45 to 3:25)

**Pre-staged:** Template skeletons exist; the live work is Claude Code completing and wiring them.

**Live beats:**
- **B13:** Claude Code writes a Backstage scaffolder template for an `agent-service`: a developer fills a form (agent name, purpose, model route, MCP tools allowed) and the template generates a repo with a kagent Agent CRD, agentgateway route, LLM Guard policy reference, and OTel instrumentation defaults. Prompt P13.
- **B14:** Claude Code writes the ApplicationSet that watches for these generated repos and auto-creates ArgoCD Applications.
- **B15:** The golden path fires: presenter plays developer, requests an agent through the Backstage portal, and the chain executes on screen: scaffolder, repo, ApplicationSet, ArgoCD sync, running agent, first trace in Tempo. Target: under 6 minutes form-to-trace. This beat closes the loop on the entire workshop and must be rehearsed as one continuous take.

**Gate:** golden path completes in under 6 minutes, three consecutive runs.

### 7.4 Wrap (3:35 to 4:00)

**Pre-staged:** Kyverno policies, Loki queries, and the commitment mechanic.

**Live beats:**
- **B16:** Kyverno AI-plane invariants applied and tested live. Minimum policy set:
  - Deny any pod in agent namespaces with egress to LLM endpoints that does not route through agentgateway.
  - Require every kagent Agent CRD to reference an LLM Guard policy.
  - Image allowlist for the AI plane namespaces (only the workshop GHCR namespace).
  - Require OTel annotations on agent workloads.
  Each policy ships with a violating manifest as a test fixture; the live beat is Claude Code attempting to apply a violating agent and Kyverno denying it.
- **B17:** Loki per-agent attribution: one query showing every action taken in the cluster attributed to a named agent identity, including Claude Code's own session via the audit hook (section 10). The room watches the agent that built the platform show up in the platform's own audit trail.
- **B18:** Commitment mechanic: chat prompt asking each attendee to post one specific change they will make in their platform within 30 days. The runbook includes the exact wording and three seeded examples to break the silence.

---

## 8. Delivery engineering

### 8.1 Checkpoints and resets

- `scripts/reset/reset-to-<checkpoint>.sh` for each checkpoint tag. Mechanism: hard-reset the GitOps repo working branch to the tag, force ArgoCD refresh and sync with prune, verify expected app count and health, exit nonzero on any mismatch. Each script completes in under 5 minutes on the sandbox. Test every reset script from every dirty state a failed beat could produce.
- A `promote-spare.sh` script that swaps presenter kubeconfig and Backstage URL to the hot spare in under 60 seconds.

### 8.2 copy-paste-commands.md

The attendee catch-up artifact. Rules:
- Numbered top to bottom, grouped by module, every command idempotent (safe to re-run).
- Jump-in points at every module boundary: an attendee who arrives at minute 90 runs one block and is current.
- No command depends on a previous command's interactive output.
- Tested by literally executing the file top to bottom on a fresh attendee environment with no human judgment applied. If that run does not produce a green platform, the file fails its gate.

### 8.3 Preflight and smoke test

- `preflight.sh` runs at 7:30 AM EDT on event day: both clusters healthy, all images cached, all checkpoints reachable, ArgoCD green at `module-0-start`, model server warm, OBS scenes listed (manual check item), API key env vars present (checks existence, never prints values), backup video files present at expected paths.
- `smoke-test.sh` validates the full final state: 33 components healthy, one golden-path run, one guarded inference, one Kyverno denial, one Tempo trace query. This is also the gate script for rehearsals.

### 8.4 Backup video checklist

Generate `docs/runbook/backup-video-checklist.md`: one row per beat ID (B01 through B18), columns for filename (`backup-B07-kagent-crd.mp4` pattern), duration, recorded date, verified-plays checkbox. Recording is Michael's task; this checklist is the contract for it.

---

## 9. Run-of-show runbook (D9)

Expand the contract's run of show into a per-beat runbook with these columns: clock time, beat ID, what is on screen, what Michael says (bullet cues, not a script), what Claude Code does (prompt ID), success signal, time budget, bail-out action, recovery action. The Module 2 bail-out ordering from 7.2 is encoded here. Include a hard rule: any beat that exceeds budget by 50 percent triggers its bail-out immediately, no live debugging beyond the rehearsed failure beats. The audience must never watch unrehearsed troubleshooting; B03 exists so they see recovery on the presenter's terms.

---

## 10. Claude Code live-driving kit

### 10.1 Repo CLAUDE.md

Contents: repo map, the components.yaml contract, GitOps rules (all changes flow through Git, never `kubectl apply` against the cluster directly except for the bootstrap and the scripted Kyverno denial demo), naming conventions, namespaces, and the writing standards from section 12 for any docs it generates. Keep it under 200 lines; it is project memory, not a manual.

### 10.2 Permissions posture

`.claude/settings.json` with an explicit allowlist: git operations on this repo, `kubectl` read verbs, `argocd` CLI, `helm template`, file edits within the repo. Mutating `kubectl` verbs require approval. Verify the current settings schema against the Claude Code docs before writing this file. The visible permission prompt during B16 (Claude Code asks before applying the violating manifest, then Kyverno denies it anyway) is a deliberate two-layer governance moment: agent-level control, then infrastructure-level control. Defense in depth, shown not told.

### 10.3 Audit hook

A hook that logs every Claude Code tool invocation (timestamp, tool, command summary) as structured JSON shipped to Loki with an agent identity label. This powers B17. Verified June 2026: register PreToolUse and PostToolUse command hooks. The stdin payload carries `session_id`, `hook_event_name`, `cwd`, `tool_name`, and `tool_input`; PostToolUse adds `tool_response` (the result field is `tool_response`, not `tool_output`). Current Claude Code docs are at code.claude.com/docs/en/hooks (the old docs.claude.com path redirects there). Re-verify event names and payload shape at the July freeze. See `docs/research-findings-june-2026.md` section 6 for the full schema.

### 10.4 Prompt library

`prompts/prompt-library.md`: every live prompt, IDs P01 onward, exact text, expected behavior, known failure modes observed in rehearsal, and the recovery move. These prompts are rehearsed verbatim. Improvised prompting during delivery is limited to Q&A.

---

## 11. Build phases and gates

| Phase | Work | Gate |
|---|---|---|
| 0 | Environment verification: provision dev cluster, verify Claude Code config against docs, confirm tool versions | Dev cluster up, docs checked, versions recorded |
| 1 | Repo skeleton, components.yaml, CI pinned-version check, vendored charts, versions.lock.md | CI green, every entry pinned, Michael sign-off on the component list |
| 2 | Foundation plane | Fresh cluster to foundation-green under 12 min, three runs |
| 3 | AI plane, model benchmark, all Module 2 beats working | Module 2 sequence under 55 min, twice; model latency gate decided |
| 4 | Self-service plane | Golden path under 6 min, three runs |
| 5 | Governance assets | All Kyverno fixtures behave; B17 query returns Claude Code's own audit entries |
| 6 | Delivery engineering and live-driving kit (requires provisioning decision from 6.3) | Resets tested from dirty states; copy-paste file passes its literal-execution test; preflight and smoke test green |
| 7 | Two full timed rehearsals, runbook corrections after each | Both rehearsals complete inside 220 minutes of content with all bail-outs untriggered or recovered cleanly |

Phase reports: at each gate, write a short report to `docs/runbook/phase-reports/` stating what passed, what was flaky, and what changed in the runbook as a result. Flaky means it failed once in three runs; flaky items get fixed or moved behind a recording, never shipped as live beats on hope.

---

## 12. Writing standards for every generated document

These apply to README, docs, runbook prose, and any attendee-facing text. They are hard rules.

- No em-dashes, no en-dashes. Commas, colons, periods.
- Banned words and phrases: delve, leverage, robust, seamless, comprehensive, under the hood, navigate complexities, genuinely, in today's landscape.
- No "it's not X, it's Y" inversions as a formula. No triadic rhetorical lists as a default pattern. No mirrored parallel closing sentences.
- Voice: first person where the presenter speaks, direct and declarative everywhere. State things plainly. No hedging filler.
- Claims about project maturity, performance, and adoption stay evidence-grounded. CNCF Sandbox projects get described as Sandbox projects. If evidence for a number does not exist, the doc says so.
- "Tools don't transform organizations. People do." is preserved verbatim if quoted, never paraphrased.

---

## 13. Risk register

| Risk | Mitigation |
|---|---|
| ArgoCD sync stampede with 33 apps | Sync waves, controller tuning, gate at Phase 2 |
| Backstage build or boot time | Pre-built image only, never source; boot validated in preflight |
| Docker Hub rate limits across 300 clusters | GHCR re-hosting or pull-through cache, no docker.io references (6.4) |
| CPU inference too slow on screen | Latency gate with pre-warmed fallback (7.2) |
| Primary cluster failure mid-session | Hot spare plus promote script under 60 seconds (8.1) |
| GitHub OAuth impossible at attendee scale | Guest auth on attendee clusters, real OAuth on presenter cluster (6.5) |
| MetalLB irrelevant on EKS, ingress-nginx EOL | Resolved: AWS Load Balancer Controller is the LB and ingress path on EKS; both dropped, stated honestly in architecture.md (6.1) and reflected in the component count (section 5) |
| LLM Guard dormant (no commits since Sept 2025, now owned by Palo Alto Networks) | Pin v0.3.16, vendor the known-good config, treat as a fixed dependency; the B09 injection block is deterministic and reset-restorable; flag the maturity honestly on screen |
| OTel GenAI semantic conventions still Development grade | Present `gen_ai.*` attributes as current but unstable; note the dedicated semantic-conventions-genai repo and OTEL_SEMCONV_STABILITY_OPT_IN; do not claim stability |
| Attendee platform outage | Doctrine constraint 1: presenter sandbox carries the session |
| Stack composition challenged publicly | Every component is a real, current, maintained IDP component with a pinned version and an honest maturity label; no dead projects in the live stack (section 5) |
| Claude Code does something unexpected live | Allowlist permissions, rehearsed prompts, B03 as the only sanctioned on-screen failure, bail-out rule in section 9 |
| Anthropic API outage during delivery | Backup recordings cover every Claude-dependent beat; runbook includes a degraded-mode path where Modules continue from recordings with live cluster verification between them |

---

## 14. Open decisions requiring Michael (collect at Phase boundaries, not mid-phase)

1. Component list: RESOLVED in approach. Build the right IDP component set, drop ingress-nginx and MetalLB, add the AWS Load Balancer Controller and AWS EBS CSI driver. The count is not a constraint. Michael reviews the final list at the Phase 1 gate.
2. Provisioning platform: RESOLVED. Amazon EKS, one cluster per student, managed control plane plus a T3 node group.
3. vLLM worker node: RESOLVED. Stay on T3 (t3.2xlarge), pre-warm the model, keep the pre-warmed-request fallback (sections 6.6 and 7.2). Benchmark at the Phase 3 gate.
4. CPU model: defaulted to Qwen3-1.7B with Qwen3-0.6B backup. Confirm after the Phase 3 benchmark.
5. Attendee cluster TTL: RESOLVED. Warm before 9:00 AM EDT, torn down 2 hours after the session closes (approximately 3:00 PM EDT). No take-home persistence; the repo is the take-home (section 6.2).
6. Alternative-path docs depth: RESOLVED. Reference-level. `docs/alternative-paths.md` gives accurate config snippets and official links for GPU serving and Amazon Bedrock, marked explicitly as not tested live. Upgrade a specific path to a tested walkthrough only on request.
7. Demo agent model routing and credentials: RESOLVED. Attendee clusters route the kagent demo agent to the in-cluster vLLM (no external spend, no external credentials). The presenter cluster shows one real cloud route, scoped and capped (section 6.7).

---

## 15. Definition of done

- All Phase gates green and reported.
- `smoke-test.sh` green on the primary and the hot spare on July 22.
- `preflight.sh` documented as the 7:30 AM event-day ritual.
- Repo public, README finished, license applied, no secrets in history (verified with a scanner).
- Backup video checklist fully checked.
- Two rehearsal reports on file, the second one boring.

The workshop succeeds when the live performance is the least risky thing Michael does that week, because everything that could surprise him already happened in rehearsal.
