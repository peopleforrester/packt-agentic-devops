# Agentic DevOps with Claude
**Building AI agents with Claude**

A 4-hour hands-on workshop for Packt Publishing.

- **Presenter:** Michael Rishi Forrester
- **Date:** Thursday, July 23, 2026, 11:00 AM EDT
- **Duration:** 4 hours
- **Format:** Live virtual, hands-on build-along
- **Audience size:** Up to 300 attendees

---

## Summary

Attendees build an AI-native Internal Developer Platform from scratch in four hours, with Claude Code as the agent doing the platform engineering work in front of them. By the end of the session, every attendee has a working 33-component IDP on a provisioned cluster: the cloud-native foundation (Backstage, ArgoCD, the Argo stack, the OTel observability plane) plus the AI plane that makes it AI-native (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry, KServe + vLLM, llm-d).

The workshop format is proven. The 27-component predecessor was delivered at KCD Texas on May 15, 2026, where it was the third-most-requested submission of the conference and most attendees had a working Backstage IDP within twenty minutes. The Packt version expands the time, keeps the build-along format, and adds the seven AI-plane components that take a cloud-native IDP to an AI-native one.

---

## Target audience

Platform engineers, DevOps engineers, SREs, cloud engineers, architects, and tech leads who already operate cloud-native platforms and now need to evolve them into AI-native platforms.

### Audience profile

**Primary persona: the platform practitioner under pressure to add AI.**

- **Role titles:** platform engineer, senior DevOps engineer, SRE, cloud engineer, staff engineer, platform architect, tech lead on an internal developer platform team.
- **Seniority:** mid to senior individual contributor. Owns platform decisions. Writes IaC, Helm charts, Backstage templates, and CI/CD pipelines hands-on.
- **Org context:** their company has a working cloud-native platform (Kubernetes, Argo, GitOps) and is under pressure from engineering leadership to add AI capabilities. They need to do this without rebuilding the platform from scratch.
- **What they already know:** Kubernetes, Helm, GitOps, CI/CD, Argo CD or Flux. They have used Claude or Claude Code at least once. They have heard of Backstage.
- **What they need:** a working AI-native platform reference architecture they can point to and copy. A clear answer to where agents, MCP servers, and LLM inference belong in the platform topology.

**Why they register:**
- They want a proven, working AI-native IDP they can take home, not a slide deck of patterns.
- They want to see Claude Code build real platform infrastructure end to end on a real cluster.
- They want the CNCF-native, vendor-neutral path so they are not locked into a single commercial AI platform.

**Secondary audiences:** engineering managers who need to understand what their team is signing up for; solutions architects at AI infrastructure companies who need to speak credibly about agentic DevOps; Backstage and IDP practitioners who want to see how to evolve their portal into an AI-native one.

---

## What makes this workshop different

**Claude Code builds the platform.** Not "here is how to add AI to your platform." Not "here are some agentic patterns." Claude Code, the agent, sits in front of attendees and scaffolds Helm values, generates Backstage scaffolder templates, writes the ArgoCD App-of-Apps wiring, defines kagent Agent CRDs, and resolves ArgoCD sync issues live. The workshop demonstrates what agentic DevOps actually looks like by doing it.

**The whole platform, deployed in four hours.** Thirty-three components on a real Kubernetes cluster, GitOps-driven, observable, and governed by the end of the session. Attendees leave with a running system, not a slide deck.

**AI as part of the platform, not a bolt-on.** kgateway, agentgateway, and kagent compose with Backstage, ArgoCD, and Kyverno through the same GitOps path everything else uses. AI-native does not require platform replacement; it requires platform extension.

**CNCF-native and vendor-neutral by default.** Most components are CNCF (kgateway, kagent, and llm-d are Sandbox as of 2026; KServe Incubating; OpenTelemetry Graduated) or Linux Foundation (agentgateway under the Agentic AI Foundation; vLLM under the PyTorch Foundation). The two exceptions are LLM Guard from Protect AI (MIT) and OpenLLMetry from Traceloop (Apache-2.0), open source projects that work with OpenTelemetry GenAI semantic conventions and ride on top of the CNCF observability stack. No commercial licensing required.

**Built for live virtual at scale.** Up to 300 attendees, one presenter, supported by a full companion GitHub repo with copy-paste commands, reset scripts, and recorded backups of every demo. The presenter provisions clusters for attendees, so nobody loses time on local setup. Watching has full value; following along is encouraged but never required.

---

## What attendees build

Twenty-six components are the cloud-native foundation built in Module 1 and Module 3, deployed via a single ArgoCD App-of-Apps:

Backstage (with TechDocs, software catalog, and scaffolder), GitHub OAuth integration, ArgoCD plugin for Backstage, ArgoCD, Argo Workflows, Argo Events, Argo Rollouts, OpenBao, Score, KEDA, External Secrets Operator, cert-manager, Kyverno, ingress-nginx, MetalLB, Prometheus, kube-prometheus-stack, Grafana, Loki, Tempo, OpenTelemetry Collector, AlertManager, plus self-service Backstage scaffolder templates and ArgoCD ApplicationSets written live during Module 3.

Seven components are the AI-plane additions built in Module 2:

1. **kgateway** as the AI-aware ingress gateway, Gateway API native
2. **agentgateway** as the unified data plane for agentic traffic, mediating LLM, MCP (tool federation), and A2A (agent-to-agent) traffic with mTLS, audit logging, and policy enforcement
3. **kagent** as the Kubernetes-native agent runtime, exposing agents as CRDs that reconcile through ArgoCD
4. **LLM Guard** as the input and output filtering layer for prompts and responses
5. **OpenLLMetry + OpenTelemetry GenAI semantic conventions** for agent observability, with traces flowing to Tempo and dashboards in Grafana
6. **KServe + vLLM** as the model serving runtime, demonstrated live with a small CPU-mode model so the workshop runs on standard clusters; GPU acceleration and Amazon Bedrock are documented in the companion repo as alternative paths
7. **llm-d** for distributed inference scheduling, showing where the platform layer for LLM serving sits

Total: 33 components.

---

## Run of show

| Time | Module | Outcome |
|---|---|---|
| 0:00 to 0:15 | Opening, calibration, ground rules | Recording starts. The meta-narrative is set: Claude Code is the agent doing the platform work today. |
| 0:15 to 1:15 | **Module 1: Cloud-native foundation.** Claude Code scaffolds and integrates the cloud-native baseline. One ArgoCD App-of-Apps reconciles live. | By the end of Module 1, attendees have a working IDP. |
| 1:15 to 1:25 | Break | |
| 1:25 to 2:35 | **Module 2: The AI plane.** Claude Code adds the seven AI components. A kagent Agent CRD is defined. The agent calls an MCP server through agentgateway. LLM Guard intercepts a prompt-injection attempt. An OTel trace lands in Tempo. KServe + vLLM serves a small CPU model. | By the end of Module 2, the IDP is AI-native. This is the centerpiece. |
| 2:35 to 2:45 | Break | |
| 2:45 to 3:25 | **Module 3: Self-service for your team.** Claude Code writes Backstage scaffolder templates and ArgoCD ApplicationSets. A developer requests a new agent service through the portal and watches the golden path fire end to end. | Attendees see how their team will use what they just built. |
| 3:25 to 3:35 | Break | |
| 3:35 to 4:00 | **Wrap: governance, observability, commitment.** Kyverno policies enforcing AI-plane invariants. Per-agent attribution in Loki. Each attendee posts one specific change they will make in their own platform within 30 days. Final Q&A. | Discussion plus commitment. |

Total: 220 minutes of content, 30 minutes of breaks.

---

## What attendees walk away with

- A working 33-component AI-native IDP, GitOps-driven, deployed during the session
- A GitHub repo with every manifest, Helm chart, ArgoCD App, Backstage template, and Claude Code prompt used in the workshop
- A clear understanding of how the AI plane composes with the cloud-native baseline through standard Kubernetes patterns (CRDs, Gateway API, OpenTelemetry)
- Demonstrated proof that Claude Code can do real platform engineering work
- A 30-day commitment to one specific change in their own platform

---

## Prerequisites

- A Claude Code subscription (attendees bring their own). Other agentic coding CLIs may work, but the workshop is tested only with Claude Code
- Cluster access is provided by the presenter; no local Kubernetes setup required
- A modern web browser (cluster access is delivered via browser, same as the KCD Texas format)

No prior Backstage experience required. Working familiarity with Kubernetes and GitOps assumed.

---

## About the presenter

Michael Forrester helps enterprises run agentic AI in production without getting burned by it. As Business Stream Lead for AI for Leadership and Organizations at Accenture LearnVantage, he leads the AI workforce transformation stream: advising leadership and engineering teams on adopting agentic AI, building reference implementations they can trust, and modernizing how that capability is delivered. Thirty years across operations, DevOps, and cloud infrastructure, most of it close to where systems actually break. His throughline is Agentic Covenants, a governance and security model for agentic AI built on a hard-won lesson: guardrails enforced by the AI tool itself are bypassable, and guardrails enforced by infrastructure are not. He builds MCP servers, runs Claude Code daily, and grounds everything in real Kubernetes and platform engineering rather than slideware. He speaks at KubeCon, SREday, LLMday, and KCD. Tools don't transform organizations. People do.

---

## Logistics

- **Date:** Thursday, July 23, 2026
- **Time:** 11:00 AM EDT, 4 hours
- **Format:** Live virtual, Packt platform
- **Recording:** yes, distributed to attendees
- **Companion repo:** `agentic-devops-with-claude`, open-source under speaker's GitHub
- **Mailing address for contract:** 3630 Drum Roll Lane, Snellville, GA 30039
- **Contracting entity (optional):** Performant Professionals, LLC, State of Georgia. Person-to-person also acceptable.
