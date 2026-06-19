# Phase 7: Self-service (Module 3, budget 35 min)

**Goal:** A Backstage scaffolder template for an agent-service and the ArgoCD ApplicationSet that watches for it, then the golden path fired end to end.

**Inputs:** Modules 1 and 2 complete (portal, AI plane, model serving). The agent-service template provisions a kagent Agent, an agentgateway route, an LLM Guard policy reference, and OTel defaults, so it depends on everything built so far.

**Outputs:**
- A Backstage scaffolder template (`scaffolder.backstage.io/v1beta3`, Nunjucks) for an agent-service: a form takes agent name, purpose, model route, and allowed MCP tools, and generates a repo with a kagent Agent CRD, agentgateway route, LLM Guard policy reference, and OTel instrumentation defaults
- An ArgoCD ApplicationSet that watches for the generated repos and auto-creates Applications
- The golden path executed: presenter plays developer, requests an agent through the portal, and the chain runs (scaffolder, repo, ApplicationSet, ArgoCD sync, running agent, first trace in Tempo)

**Test criteria (tests/test_phase_7_self_service.py):**
- The scaffolder template is registered and renders without error
- The ApplicationSet exists and generates an Application for a generated repo
- A golden-path run produces a running agent and a first trace in Tempo
- The generated agent passes the audit-mode AI-plane policies (references an LLM Guard policy, carries OTel annotations)

**Completion promise:** `<promise>PHASE7_DONE</promise>`

**Key decisions:**
- The ApplicationSet CRD requires server-side apply (it exceeds the client-side annotation limit).
- The template output must satisfy the Phase 4 audit policies, so the golden path is governed by construction.
- Target: form to trace under 6 minutes. Rehearse as one continuous take.

**Stop here.** Output the completion promise and wait. The presenter narrates the golden path closing the loop on the whole platform.
