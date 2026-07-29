# VTT enhancements backlog

Enhancements for the student web terminal (`scripts/provision/vtt/`).

## Shipped (v1)

### 1. Interactive architecture blueprint (progressive reveal) — DONE
`web/diagram.html`, served at `/diagram`, embedded as the **Blueprint** tab. Shows the whole build from a
bare cluster to all components, revealed phase 0 through 8 with Argo CD as the source of truth. Prev/Next,
Play, clickable phase pips, keyboard arrows, `?phase=` deep link.

### 2. Component endpoint directory — DONE
`web/links.html`, served at `/links`, embedded as the **Endpoints** tab. Phase-revealed catalog of the
platform UIs with namespace and the phase each comes online. Tapping a card prints that component's address
on the student's own cluster into the terminal (postMessage bridge to the lab; clipboard fallback standalone).

### 3. Session persistence (PVC) — DONE
A 1Gi `~/.claude` PVC keeps login + conversation history across a pod restart. A tmux re-attach layer for
surviving a browser refresh was tried and removed; a refresh now starts a fresh shell. See
`scripts/provision/vtt/README.md`.

### 4. VS Code and Jupyter tabs — DONE
The "+" menu's **VS Code** and **Jupyter** items are live. code-server (4.105.1) and single-user JupyterLab
(4.6) run in the web-terminal container beside ttyd, sharing `/home/student` and the Gitea-wired
`~/workshop`, so a file edited in any tab shows up in the others. nginx proxies `/ide/` (prefix-stripped)
and `/jupyter/` (base_url-prefixed) with the same websocket upgrade ttyd uses; both are backgrounded restart
loops in `entrypoint.sh`. The separate **Browser IDE** stub was folded into the VS Code tab (same thing).
Design: `prds/5-browser-ide.md`, `prds/6-jupyter.md`. Auth stays upstream, so the terminal-auth project must
cover `/ide/` and `/jupyter/` too.

## Still open (v2 ideas)

- **Terminal capture + AI help.** Capture the student's session and feed it to a tutor that answers when a
  student is stuck. Design in `prds/7-terminal-capture-ai-help.md` (Option B, standalone tutor agent,
  selected). Gated on a model-backend decision.
- **Fleet image distribution.** Mirror the VTT image in-region for 300 clusters: an ECR pull-through
  cache, or a shared Harbor (CNCF) proxy-cache; pin by digest. Avoids GHCR burst latency at scale.

- **Live phase sync.** Drive the Blueprint and Endpoints current-phase from the student's real progress
  (which phase Claude has completed) rather than a manual stepper. Could key off a marker the phase tests
  write, surfaced to the lab via localStorage or a small status endpoint.
- **Auto-discovered, clickable UIs.** Replace the discovery commands with real reachable links. Two paths:
  read the cluster's Ingress/HTTPRoute/LoadBalancer objects (needs a small backend, since nginx cannot run
  kubectl), or path-proxy each UI through the console nginx (needs per-component subpath config: Argo CD
  `--basehref`, Grafana `serve_from_sub_path`, Backstage `baseUrl`). Fragile per component; scope carefully.
- **Blueprint <-> Endpoints cross-highlight.** Hovering a component in one panel highlights it in the other.
