# Decisions

Locked decisions for the Packt workshop. Newest at the bottom. These are the source of truth when the build spec and reality disagree.

## D1. Backbone: Amazon EKS, one cluster per student

EKS, one cluster per student, provisioned live. Managed control plane plus a T3 node group. vcluster is not used. Kubernetes 1.35. (June 17, 2026)

## D2. Component set is not a target number

Build the right set of IDP components. The count is whatever it adds up to. CI checks that every entry is version-pinned, not that there are N of them. (June 17, 2026)

## D3. vLLM stays on T3

The in-cluster model runs on t3.2xlarge with the model pre-warmed and a pre-warmed-request fallback. T3 is the last Intel x86 burstable family; the vLLM CPU image is x86. No dedicated compute node. (June 17, 2026)

## D4. Attendee cluster TTL

Warm before 11:00 AM EDT, torn down about 2 hours after close. No take-home persistence; the repo is the take-home. (June 17, 2026)

## D5. Demo agent model routing

Attendee clusters route the in-cluster agents to the in-cluster vLLM over an OpenAI-compatible endpoint. No external API spend, no external credentials. (June 18, 2026)

## D6. Live build scope: bare cluster, students build everything

The only thing pre-staged is a bare cluster, up, with credentials handed to the student at the start. ArgoCD is not installed, the repo is not cloned, nothing is synced. The student's own agentic CLI, driven by the spec document, builds everything from Phase 0, including installing ArgoCD and cloning the repo. Precedent: at KCD Texas, students completed the full build in about 20 minutes of a 90-minute session. Nothing is compiled from source live; the build deploys pre-built images via GitOps, which is why it is fast. (June 19, 2026)

## D7. Pacing: the spec forces stops between phases

The spec document forces a stop between each phase. The presenter presents during the stops, and everyone resumes together. This is the sync mechanism; it does not depend on lockstep enforcement beyond the spec gates. Holds at the workshop's audience scale. (June 19, 2026)

## D8. Phase structure

Roughly nine phases, Phase 0 through Phase 8, mapping the abstract's three modules plus the wrap onto phases. The presenter proposes the breakdown in the attendee spec; Michael signs off. (June 19, 2026)

## D9. Cluster provisioning is Michael's

Michael provisions all 300 clusters, including the t3.2xlarge sizing and the per-cluster in-cluster vLLM. This is out of the build scope here. Each cluster runs its own small in-cluster vLLM, which is the simulated inference; no student gets access to a large external LLM. (June 19, 2026)

## D10. Prerequisite: bring your own agentic CLI

Students bring their own paid agentic coding CLI plan, Claude Code or an equivalent. The workshop does not provide it. The tool must be able to register and run inside the remote cluster system the student is given. (June 19, 2026)

## D11. AI-plane policies precede the AI plane

The AI-plane Kyverno policies are defined in audit mode in Phase 4, as the AI gateway plane lands, so kagent and agentgateway are governed from birth. Phase 8 flips them from audit to enforce and runs the live denial demo. Governance precedes the workload. (June 19, 2026)

## D13. Accepted agentic CLIs; the two LLM roles are distinct

Per-vendor spikes (June 19, 2026) verified which CLIs actually work for the workshop (headless in the remote shell, governed gate, lifecycle hooks for audit). Working set:

- Claude Code (primary): paid plan, OpenAI-compatible base URL works, PreToolUse/PostToolUse hooks.
- OpenAI Codex CLI: paid, GA hooks.
- GitHub Copilot CLI (the new agentic `copilot`, GA Feb 2026): paid Copilot tier, governed default, preToolUse/postToolUse hooks. Not the old suggest-only `gh copilot`.
- Google Antigravity CLI (GA May 2026): free Individual preview, governed via Terminal Execution Policy Off, Inspect hooks. This is Google's successor; Gemini CLI itself goes dark for free/Pro/Ultra plans June 18, 2026.
- Amazon Kiro CLI 2.0 (GA April 2026): free tier includes the CLI, governed via `--trust-tools`, pre/post hooks. This is AWS's successor; Amazon Q Developer CLI signups are blocked from May 15, 2026.
- opencode (MIT, free): BYO-key, points at the in-cluster vLLM directly, governed and audited via the `tool.execute.before/after` plugin (native interactive ask hangs headless).
- Goose (Apache-2.0, free): BYO-key, points at the in-cluster vLLM, governed and audited via the PreToolUse/PostToolUse hooks engine (not GOOSE_MODE).
- Cursor CLI: works headless with hook-based governance, but locked to Cursor's hosted models (no in-cluster vLLM) and beta safeguards. Weakest fit.

Name the dead products explicitly so students do not bring them: Gemini CLI (use Antigravity), Amazon Q Developer CLI (use Kiro). Free and open-source options for students without a paid plan: opencode and Goose, both vLLM-ready.

Two LLM roles, not to be confused: the agentic CLI is the builder and runs on the student's own model (their plan, their spend, by design, or the in-cluster vLLM if they use opencode/Goose). The model the deployed platform agents call is the small in-cluster vLLM, with no external spend. The no-external-spend rule applies to the deployed demo agent, not to the student's build CLI. (June 19, 2026)

## D14. RESOLVED: per-agent attribution works across the modern agentic CLIs

The earlier claim that the B17 attribution beat works cleanly only on Claude Code and Codex was wrong, corrected by the per-vendor spikes. Every CLI in the D13 working set now ships lifecycle hooks suitable for a per-action audit trail: Claude Code (PreToolUse/PostToolUse), Codex (GA hooks), GitHub Copilot CLI (preToolUse/postToolUse), Antigravity (Inspect hooks), Kiro (pre/post hooks), opencode (tool.execute.before/after), Goose (PreToolUse/PostToolUse engine), Cursor (six CLI events as of April 2026). The config differs per CLI, but each can ship a structured line per tool invocation to Loki. B17 is achievable across the accepted set; the presenter demonstrates it on Claude Code, and the repo can document the hook config for the others. No narrowing needed. (June 19, 2026)

## D12. Tempo over Jaeger; KEDA is not Karpenter

Tracing backend is Grafana Tempo, not Jaeger, to keep traces, logs, metrics, and dashboards under one Grafana pane. Jaeger is documented as an alternative path. KEDA (event-driven pod autoscaling) is a platform capability students learn; it is not a Karpenter substitute. Node provisioning is the fixed managed node group, and self-managed Karpenter is not used (see D9). (June 19, 2026)
