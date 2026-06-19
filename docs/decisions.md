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
