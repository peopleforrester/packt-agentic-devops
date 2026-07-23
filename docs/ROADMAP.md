# Workshop platform roadmap

ABOUTME: Future fixes and enhancements for the Agentic DevOps workshop, captured from the live
ABOUTME: 2026-07-23 run. Status reflects what shipped live vs what remains for the next run.

Ordered by how load-bearing each item is. "Live-patched" means done on the running fleet this run
but not yet durable in the provisioning path; "Manifest" means the repo default is fixed so future
provisions get it from cold.

## 1. Terminal (VTT) durability and UX

### 1a. Persistent 8Gi terminal memory
The ttyd shell OOM-kills at 2Gi under a real build (agentic CLI + kubectl/helm/argocd/node), dropping
the student's session. **Live-patched:** all 100 student pods + admin1/admin2 raised to 8Gi via
in-place pod resize (EKS >=1.33, no restart, no session loss). **Manifest:** `web-terminal.yaml` is
now 8Gi, so cold provisions ship it. **Remaining:** the in-place resize is not durable across a pod
restart (a restarted pod reverts to the deployment spec until re-provisioned). See
[[inplace-resize-ttyd-memory]].

### 1b. Endpoints tab + paste bridge
Tapping an Endpoints card should print the component address into the terminal via a same-origin
`postMessage('vtt-run')` -> `sendToTerminal`. The older `sendToTerminal` dispatched the synthetic
paste on one target and failed. **Fixed** in `web/lab.html` (dispatch on both the xterm helper
textarea and the `.xterm` root) and applied to admin2 via a `console-src` ConfigMap update (no
restart). Ensure every cluster provisions with the fixed `lab.html`.

### 1c. Add-a-terminal ("+")
`addTerm()` (new `/terminal/` iframe + tab) is in the current `lab.html`; older cached tabs lacked
it. Ships with 1b. The "+" add-menu already stubs the tools below as "soon".

### 1d. Terminal authentication (GO-LIVE BLOCKER)
Terminals are unauthenticated, guessable public URLs; a student reached the admin cluster this run.
**Must be fixed before the next run.** Full write-up and fix directions in
`docs/fleet/09-lessons-learned.md` and [[terminals-unauthenticated-golive-blocker]]. Any new
per-service URL (sections 3-4) inherits this gap and must be gated too.

## 2. More tools in the terminal (the "+" menu "soon" items)

Same pattern for each: a sidecar (or in-pod service) + a new terminal-tab pane (iframe) + one nginx
`location`. The tab machinery (`showTerm`, panes keyed by `data-i`) already supports it.

- **2a. Jupyter notebooks** — jupyter server in the pod, pane iframe -> `/jupyter`, nginx proxy.
- **2b. VS Code IDE** — `code-server`, pane iframe -> `/code`.
- **2c. Browser IDE** — as already stubbed.

Each is a heavier container; fold their memory into the node budget (t3.2xlarge ~31Gi is roomy, but
Jupyter + code-server + an 8Gi terminal cap on one node needs a quick check).

## 3. URLs for all services, per cluster

Every platform UI reachable per cluster, auto-exposed once the service is online (ArgoCD, Grafana,
Jaeger/Tempo, Backstage, Prometheus, Gitea, Argo Workflows/Rollouts, kgateway, ...).

**Routing decision (settled):** use a **path on the existing host** —
`studentN.packt.ai-enhanced-devops.com/<service>` — which reuses the existing wildcard cert, DNS,
Caddy route, and NLB with zero new infra. A per-component **subdomain**
(`argocd.studentN.packt...`) is two labels deep, which `*.packt...` does NOT cover, so it needs one
wildcard cert per cluster and breaches the Let's Encrypt 50-cert/domain/week limit (the very reason
for the single wildcard). A single-label host (`argocd-studentN.packt...`) works with the existing
wildcard but costs a per-cluster route. **Auto-once-online:** each component ships its own Ingress
or in-pod nginx route, so ArgoCD syncing it adds the path with no extra step. See
[[per-component-subdomains-future]].

## 4. BurritoBot (Qwen-backed witchy chat)

Port the full BurritoBot ai-layer from `~/repos/events/Unleash_an_Agent_Watch_It_Burn/gitops/ai-layer`
(witchy storefront `web/burritbot.html`, spectator panel, menu/secret-sauce jailbreak framing,
guards/MCP), swapping the model backend from **Bedrock/kagent to the in-cluster Qwen3 vLLM**
(`qwen3-predictor.kserve.svc:80`, OpenAI-compatible, model `qwen3-1.7b`). Serve at
`<cluster>.packt.../burrito` (the path route from section 3). The UI posts `{prompt}` to `/chat`; a
thin proxy prepends the BurritoBot system prompt and calls Qwen. admin1 can host it now (Qwen is
serving); admin2 once its AI plane is up. Note: the spectator panel IS the cost dashboard (section 5).

## 5. Cost dashboard + Claude Code telemetry

### 5a. In-terminal cost tab
Live tokens / LLM cost / infra cost / total in the VTT. Assembly of existing pieces:
- **Metering proxy** in front of the model, serving `/cost` (tokens + USD). Port the cost meter from
  Unleash `gitops/ai-layer/proxy.py` (tally + per-model rate card + `/cost` endpoint), swap the rate
  card for Qwen/Claude.
- **Cost sidecar** cloned from the existing `status-loop.sh` status sidecar: reads `/cost` (LLM) +
  computes `infra = rate-card x uptime` (EKS $0.10/hr + t3.2xlarge ~$0.33/hr + NLB ~$0.0225/hr + EBS
  gp3), writes `/run/cost/cost.json`.
- **nginx** serves `/api/cost` (one line, like `/api/status`); **`lab.html` Cost tab** polls it.
Caveats: in-cluster Qwen has no per-token API charge (its cost is compute, already in "infra") — the
real external spend is the student's Claude Code (section 5b). Infra is a live rate-card estimate;
Cost Explorer gives actuals hours later.

### 5b. OTel from student Claude Code, on by default
Wire every student's Claude Code to export usage telemetry into the cluster's observability plane
automatically, so tokens/cost from the *building* agent are visible (not just the in-cluster model).
Set in the terminal environment (container env or `/home/student/.bashrc`):
- `CLAUDE_CODE_ENABLE_TELEMETRY=1`
- `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`
- `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` (or `http/protobuf`)
- `OTEL_EXPORTER_OTLP_ENDPOINT=` the in-cluster OpenTelemetry Collector (observability namespace)
Claude Code then emits token-usage and cost metrics over the SAME OTLP pipeline as the platform's
OpenLLMetry `gen_ai.*` spans, so one Grafana dashboard covers both the platform model and the
building agent. **Verify the exact Claude Code telemetry env-var names and metric names against the
current Claude Code docs at implementation time** (they are version-sensitive; do not trust this list
blind).

## 6. Bells and whistles (backlog)

- Per-student cost cap / rate limit (Unleash `proxy.py` already has `COST_CAP_USD` / `RATE_LIMIT_RPM`).
- tmux-back the terminal so a browser reload reattaches instead of spawning a fresh shell (would have
  saved sessions during this run's lab.html fixes).
- Auto-reconnect banner in the terminal when ttyd drops, instead of a bare "reconnect" that loses state.
