# Decisions

Locked decisions for the Packt workshop. Newest at the bottom. These are the source of truth when the build spec and reality disagree.

## D1. Backbone: Amazon EKS, one cluster per student

EKS, one cluster per student, provisioned live. Managed control plane plus a T3 node group. vcluster is not used. Kubernetes 1.35. (June 17, 2026)

## D2. Component set is not a target number

Build the right set of IDP components. The count is whatever it adds up to. CI checks that every entry is version-pinned, not that there are N of them. (June 17, 2026)

## D3. vLLM stays on T3

The in-cluster model runs on t3.2xlarge with the model pre-warmed and a pre-warmed-request fallback. T3 is the last Intel x86 burstable family; the vLLM CPU image is x86. No dedicated compute node. (June 17, 2026)

## D4. Attendee cluster TTL

Warm before 9:00 AM EDT, torn down about 2 hours after close. No take-home persistence; the repo is the take-home. (June 17, 2026)

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

The prerequisite CLI is Claude Code (primary) or an equivalent that runs headless in the remote shell with a governed approval gate: OpenAI Codex CLI, opencode, Codename Goose, or Cursor CLI. Do not list Google Gemini CLI or Amazon Q Developer CLI: both are being sunset within weeks of the workshop (Gemini CLI personal plans cut off June 18, 2026; Amazon Q signups closed May 15, 2026).

Two LLM roles, not to be confused: the agentic CLI is the builder and runs on the student's own paid plan (their model, their external spend, by design). The model the deployed platform agents call is the small in-cluster vLLM, with no external spend and no external credentials. There is no contradiction: the no-external-spend rule applies to the deployed demo agent, not to the student's build CLI. (June 19, 2026)

## D14. OPEN: per-agent attribution is clean only on Claude Code and Codex

The B17 per-agent attribution beat relies on PreToolUse/PostToolUse hooks shipping to Loki. Of the accepted CLIs, only Claude Code and Codex give a clean lifecycle audit trail. Decision needed: either narrow the accepted CLI list to Claude Code and Codex, or frame B17 as a Claude-Code-specific demo with a documented fallback (git history plus shell session logging) for students on other CLIs. OPEN, for Michael. (June 19, 2026)

## D12. Tempo over Jaeger; KEDA is not Karpenter

Tracing backend is Grafana Tempo, not Jaeger, to keep traces, logs, metrics, and dashboards under one Grafana pane. Jaeger is documented as an alternative path. KEDA (event-driven pod autoscaling) is a platform capability students learn; it is not a Karpenter substitute. Node provisioning is the fixed managed node group, and self-managed Karpenter is not used (see D9). (June 19, 2026)
