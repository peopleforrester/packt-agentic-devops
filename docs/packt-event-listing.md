# Agentic DevOps with Claude
**Building AI agents with Claude**

A hands-on workshop focused on building AI-powered DevOps agents using Anthropic's Claude. Learn how AI agents can automate CI/CD, monitoring, incident response, infrastructure operations, and developer workflows through real-world demos and practical sessions.

By Packt Publishing Limited

Online event
Thursday, July 23, 2026 • 9:00 AM - 1:00 PM EDT

---

## Overview

AI agents, platform intelligence, developer experience, observability, and the platform layer that actually makes agentic DevOps real.

**Build an AI-Native IDP with Claude Code as the Builder, Live, In Four Hours.**

Most platform teams in 2026 are not asking whether to add AI to their internal platforms. They are asking how to do it without weakening governance, fragmenting their tooling, or shipping a prototype that no one will run in production.

This workshop is designed for those who already operate cloud-native platforms and now need to evolve them into AI-native platforms deliberately, safely, and with clear business value.

Many platform teams are asking the same questions:

- How do we add AI to internal platforms without bolting on a vendor stack?
- Where do agents, MCP servers, and LLM inference belong in our platform topology?
- How does Claude Code actually fit into a real CI/CD and platform engineering workflow, beyond generating code snippets?
- What does an AI-native IDP look like in practice, on a real cluster, end to end?
- How do developer portals, golden paths, telemetry, and AI agents compose into one platform?
- How do we evolve from cloud-native platform engineering to AI-native platform operations without creating unnecessary risk?

This workshop is built to answer those questions by building the platform in front of you. Claude Code is the agent doing the platform engineering work, live, on a real cluster, for four hours. By the end of the session, attendees have a 33-component AI-native Internal Developer Platform they can take home.

---

## This hands-on workshop covers

- AI-native platform architecture and design
- Backstage developer portals and self-service platforms
- ArgoCD, Argo Workflows, and the GitOps delivery layer
- The AI plane: kgateway, agentgateway, kagent, LLM Guard
- KServe and vLLM for in-cluster model serving
- OpenLLMetry and OpenTelemetry GenAI semantic conventions for agent observability
- llm-d for distributed inference scheduling
- Claude Code as a platform engineering force multiplier

## Who should attend

Platform engineers, DevOps engineers, SREs, cloud engineers, architects, tech leads, and engineering leaders building AI-native, self-service platforms on Kubernetes.

## What you will walk away with

- A working 33-component AI-native IDP, GitOps-driven, deployed during the session on a provisioned cluster
- A clear understanding of how AI agents, MCP servers, and LLM inference fit into a cloud-native platform topology
- Hands-on exposure to using Claude Code as the agent that builds, integrates, and debugs platform infrastructure, not just code snippets
- Practical patterns for modern platform tools (Backstage, ArgoCD, kagent) and how they compose with the AI plane
- A working approach to building self-service developer experiences that include agent provisioning as a first-class workload
- A clear view of how telemetry, observability, and policy compose across both the cloud-native and AI planes
- A practical framework to define your AI-native platform roadmap and connect it to developer productivity and business outcomes

## What makes this workshop different

**Claude Code builds the platform, live, in front of you.**
Not "here is how to add AI to your platform." Not "here are some agentic patterns." Claude Code, the agent, sits at the keyboard and scaffolds Helm values, generates Backstage scaffolder templates, writes the ArgoCD App-of-Apps wiring, defines kagent Agent CRDs, and resolves ArgoCD sync issues live. The workshop demonstrates what agentic DevOps actually looks like by doing it.

**The whole platform, deployed in four hours.**
Thirty-three components on a real Kubernetes cluster, GitOps-driven, observable, and governed by the end of the session. Attendees leave with a running system, not a slide deck.

**AI as part of the platform, not a bolt-on.**
kgateway, agentgateway, and kagent compose with Backstage, ArgoCD, and Kyverno through the same GitOps path everything else uses. AI-native does not require platform replacement; it requires platform extension.

**CNCF-native and vendor-neutral by default.**
Most components are CNCF (kgateway, kagent, llm-d all Sandbox as of 2026; KServe Incubating; OpenTelemetry Graduated) or Linux Foundation (agentgateway, vLLM via PyTorch Foundation). The two exceptions (LLM Guard from Protect AI, OpenLLMetry from Traceloop) are MIT-licensed open source projects that emit OpenTelemetry GenAI semantic conventions and ride on top of the CNCF observability stack. No commercial licensing required.

**The AI plane is observable from day one.**
Every agent call, every MCP invocation, every LLM request flows through OpenTelemetry with GenAI semantic conventions, landing in Tempo for traces and Grafana for dashboards using the same observability stack you already run.

**Designed for the practitioner who will run this in production.**
This is for platform engineers, DevOps engineers, and SREs who will be on the hook when things fail. Not just experimenting, but making decisions others will depend on. The architecture, the GitOps patterns, and the governance defaults are all production-grade.

**Built for scale: 300 attendees, one presenter, no local setup required to follow.**
The build-along is supported by a full companion GitHub repo with copy-paste commands, reset scripts, and recorded backups of every demo, and the presenter provisions clusters for attendees so nobody loses time on local setup. Watching has full value; following along is encouraged but never required.

---

## Prerequisites

- A Claude Code subscription (attendees bring their own)
- Cluster access is provided; no local Kubernetes setup required
- A modern web browser (cluster access is delivered via browser)
- Working familiarity with Kubernetes, Helm, and GitOps (Argo CD or Flux experience helpful)

No prior Backstage experience required.

---

## About the instructor

**Michael Rishi Forrester** is AI Workforce Transformation Lead at Accenture LearnVantage and founder of The Performant Professionals. He has 25+ years in operations and DevOps, holds CKA, CKAD, and CKS certifications along with ~10 AWS certifications, and delivered the 27-component predecessor of this workshop at KCD Texas, May 15, 2026, where it was the third-most-requested submission of the conference. He spoke at KubeCon EU Amsterdam in March 2026 (two sessions, one co-delivered with Mumshad Mannambeth), devopsdays Atlanta, SREday Austin, LLMday Austin, and KCD Texas, and is a confirmed speaker at Agentic Engineering Days Zurich in November 2026. He is an independent practitioner with no Anthropic affiliation; the content is vendor-neutral by design.
