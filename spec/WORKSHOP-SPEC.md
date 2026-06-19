# Workshop Build Spec (attendee-facing)

This is the spec your agentic CLI ingests during the workshop. It drives the build of an AI-native Internal Developer Platform on your cluster, phase by phase. The presenter builds the same thing in parallel and presents at each stop.

This is different from `docs/build-spec.md`, which is the internal spec for the team building the workshop. This file is for you, the attendee, and your agent.

## What you are building

An AI-native IDP on Amazon EKS: a cloud-native foundation (Backstage, the Argo stack, the OpenTelemetry observability plane, policy and secrets tooling) plus an AI plane that makes it AI-native (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry, KServe with vLLM, llm-d).

## Starting state

A bare Kubernetes cluster, up, with credentials. Nothing is installed. ArgoCD is not present and this repo is not yet cloned on the cluster side. Your agent does all of it.

## Non-negotiable rules

These bind your agent for the whole build.

1. **Work one phase at a time, and stop at the end of each phase.** Do not start the next phase until the user confirms. The stop is where the presenter explains what just happened.
2. **Test first.** For each phase, write the phase test, run it to confirm it fails, build the components, then run it to confirm it passes. No mocks, no stubs, no fallbacks.
3. **Everything after the bootstrap flows through Git and ArgoCD.** The only direct installs are ArgoCD itself (the bootstrap) and the one scripted policy-denial demo. Use server-side apply for CRDs (`kubectl apply --server-side --force-conflicts`); the ApplicationSet and Argo Workflows CRDs exceed the client-side apply annotation limit.
4. **Pin every version.** Use the versions in `components.yaml` and `versions.lock.md`. Do not invent versions or use what your training data remembers.
5. **Two model roles, do not confuse them.** Your agentic CLI is the builder doing platform engineering. The model the deployed platform agents call is the small in-cluster vLLM served in Phase 6, over an OpenAI-compatible endpoint. There is no external LLM in the platform and no external API spend.
6. **No secrets in Git.** Sealed Secrets and External Secrets Operator handle the in-cluster story.

## Completion gate per phase

A phase is done when its test passes and you have committed the phase's files. Output the phase completion promise, then stop and wait for the user.

## Phases

The build maps to the four-hour run of show: an opening, three modules, and a wrap. Nine phases, 0 through 8.

| Phase | Name | Module | What it delivers |
|---|---|---|---|
| 0 | Preflight | Opening | Confirm the bare cluster, credentials, agent registration, and tooling. Read this spec and `components.yaml`. Install nothing. |
| 1 | GitOps bootstrap and core foundation | Module 1 | Install ArgoCD (server-side), clone and point at the repo, then the App-of-Apps brings up cert-manager, Sealed Secrets, External Secrets Operator, and Kyverno. |
| 2 | Observability plane | Module 1 | kube-prometheus-stack, Loki, Tempo, the OpenTelemetry Collector and Operator. |
| 3 | Developer portal | Module 1 | Backstage (catalog, TechDocs, scaffolder, ArgoCD plugin), KEDA, and the Argo extensions (Workflows, Events, Rollouts). End of Module 1: a working IDP. |
| 4 | AI gateway plane | Module 2 | Gateway API CRDs, kgateway, agentgateway with mTLS and audit logging. |
| 5 | Agent runtime and safety | Module 2 | kagent and an Agent CRD, LLM Guard, OpenLLMetry wiring. The agent calls an MCP server through agentgateway; a prompt-injection attempt is blocked. |
| 6 | Model serving | Module 2 | KServe with a small in-cluster vLLM model, and llm-d shown as the scheduling layer. The agent trace lands in Tempo. End of Module 2: AI-native. |
| 7 | Self-service | Module 3 | A Backstage scaffolder template for an agent-service and the ArgoCD ApplicationSet that watches for it. The golden path fires end to end. |
| 8 | Governance and attribution | Wrap | Kyverno AI-plane policies, per-agent attribution in Loki, and your 30-day commitment. |

Each phase has a detailed file in `spec/phases/phase-N-*.md` with its goal, outputs, test criteria, completion promise, and pinned versions.

## How to run this

1. Read this file and `components.yaml`.
2. Start at Phase 0. Read `spec/phases/phase-0-preflight.md`.
3. For each phase: read the phase file, write the test, confirm it fails, build, confirm it passes, commit, output the completion promise, then stop and wait for the user.
4. Move to the next phase only when the user says go.

## Status

The phase breakdown above is proposed and awaiting sign-off. Phase 0 is written as the pattern. Phases 1 through 8 are detailed once the breakdown is approved.
