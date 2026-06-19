# Agentic DevOps with Claude: Workshop Agenda

**Building an AI-Native Internal Developer Platform, live, with Claude Code as the builder.**

- **Format:** Live virtual, hands-on build-along
- **Date:** Thursday, July 23, 2026
- **Time:** 9:00 AM to 1:00 PM EDT (4 hours)
- **Delivered by:** Packt
- **Instructor:** Michael Rishi Forrester

## What this is

One idea sits behind the whole session: AI-native is platform extension, not replacement. The AI plane composes with your cloud-native stack through the same GitOps path everything else uses, and an agent can do the platform engineering work itself, governed, not unleashed. You watch it happen on a real cluster, and you take the platform home.

Tools don't transform organizations. People do. These four hours are built for the people who will run this platform after the session ends.

## Summary

Over four hours, Claude Code builds an AI-native Internal Developer Platform on a real Kubernetes cluster, live, in front of you. You watch an agent do real platform engineering work: scaffolding Helm values, writing ArgoCD App-of-Apps wiring, defining kagent Agent CRDs, generating Backstage scaffolder templates, and resolving sync issues. By the end you have a working 33-component AI-native IDP you can take home: a cloud-native foundation (Backstage, the Argo stack, the OpenTelemetry observability plane, policy and secrets tooling) plus the AI plane that makes it AI-native (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry, KServe with vLLM, llm-d).

The format is proven. The 27-component predecessor ran at KCD Texas in May 2026, where most attendees had a working Backstage IDP within twenty minutes. This version adds the time and the seven AI-plane components that take a cloud-native IDP to an AI-native one.

## Who should attend

Platform engineers, DevOps engineers, SREs, cloud engineers, architects, and tech leads who already operate cloud-native platforms and now need to evolve them into AI-native platforms without weakening governance or replacing their stack.

## Prerequisites

- A Claude Code subscription (bring your own)
- A modern web browser. Cluster access is delivered in the browser; no local Kubernetes setup required
- Working familiarity with Kubernetes, Helm, and GitOps (Argo CD or Flux experience helps)
- No prior Backstage experience required

## How you'll participate

Pick your level. Every one of them has full value, and nothing depends on your machine: every outcome the workshop promises is achieved on the presenter's cluster, so following along is a bonus, never a requirement.

- **Watch.** Follow the live build and the reasoning behind each decision, with zero setup. You leave understanding the architecture, the GitOps patterns, and the governance model, because you saw them built, and debugged, in real time.
- **Follow along.** We provide a cluster in your browser, no local install. At each module you run the same numbered, idempotent commands the build uses, and build your own copy in parallel. Fall behind, and a single jump-in block at each module boundary brings you current in one step.
- **Take it home.** Everything is in the companion GitHub repo: every manifest, Helm chart, ArgoCD App, Backstage template, and the exact Claude Code prompts, plus reset scripts and recordings of each demo. Re-run the whole build at your own pace afterward.
- **Engage.** Ask questions throughout. Watch a deliberate failure get diagnosed and healed, and watch policy block a bad change live. Close by committing to one specific change you will make in your own platform within 30 days.

## Agenda

| Time (EDT) | Module | What happens |
|---|---|---|
| 9:00 to 9:15 | Opening and ground rules | The frame is set: Claude Code is the agent doing the platform work today, governed, not unleashed. |
| 9:15 to 10:15 | Module 1: Cloud-native foundation | Claude Code applies one ArgoCD App-of-Apps and the foundation reconciles live. Backstage, the Argo stack, the observability plane, policy and secrets tooling. By the end, a working IDP. |
| 10:15 to 10:25 | Break | |
| 10:25 to 11:35 | Module 2: The AI plane (the centerpiece) | Claude Code adds the seven AI components. A kagent Agent CRD is written and deployed by GitOps. The agent calls an MCP server through agentgateway. LLM Guard blocks a prompt-injection attempt. An OpenTelemetry trace lands in Tempo. KServe with vLLM serves a small model. |
| 11:35 to 11:45 | Break | |
| 11:45 to 12:25 | Module 3: Self-service for your team | Claude Code writes a Backstage scaffolder template and an ArgoCD ApplicationSet. A developer requests a new agent service through the portal and the golden path fires end to end. |
| 12:25 to 12:35 | Break | |
| 12:35 to 1:00 | Wrap: governance, observability, commitment | Kyverno policies enforce AI-plane invariants. Per-agent attribution in Loki shows every action, including Claude Code's own. Each attendee commits to one specific change for their own platform. Final Q&A. |

## What you will walk away with

This is the promise. By 1:00 PM EDT you have a working platform, not a slide deck:

- A working 33-component AI-native IDP, GitOps-driven, deployed during the session
- A companion GitHub repo with every manifest, Helm chart, ArgoCD App, Backstage template, and Claude Code prompt used in the workshop
- A clear view of where agents, MCP servers, and LLM inference belong in a cloud-native platform topology
- Practical patterns for Backstage, ArgoCD, and kagent, and how they compose with the AI plane
- A working approach to self-service developer experiences that treat agent provisioning as a first-class workload
- A view of how telemetry, observability, and policy compose across both the cloud-native and AI planes
- A 30-day commitment to one specific change in your own platform

## What makes it different

Claude Code builds the platform. Not a slide deck about adding AI to platforms, and not a set of patterns. The agent sits at the keyboard and does the work, live, on a real cluster, for four hours. The stack is CNCF-native and vendor-neutral by default, so you are not locked into a single commercial AI platform. Watching has full value; following along is encouraged but never required, because every outcome is achieved on the presenter's cluster and clusters are provided for attendees.

## Instructor

**Michael Rishi Forrester**, AI Workforce Transformation Lead at Accenture LearnVantage and founder of The Performant Professionals. 25 plus years in operations and DevOps. CKA, CKAD, and CKS certified, with roughly ten AWS certifications. He delivered the 27-component predecessor of this workshop at KCD Texas in May 2026, the third-most-requested submission of the conference, and spoke at KubeCon EU Amsterdam in March 2026. He is an independent practitioner with no Anthropic affiliation; the content is vendor-neutral by design.
