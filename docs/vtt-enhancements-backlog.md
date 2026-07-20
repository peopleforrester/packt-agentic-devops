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

### 3. Session persistence (tmux + PVC) — DONE
tmux keeps the shell alive across a browser refresh (ttyd `-a` + `vtt-shell` per-session attach); a 1Gi
`~/.claude` PVC keeps login + conversation history across a pod restart. See `scripts/provision/vtt/README.md`.

## Still open (v2 ideas)

- **"+" dropdown future tools.** The add-menu already lists them disabled: **VS Code** (code-server),
  **Jupyter**, and a **Browser IDE**. Each is a real build: a service in the pod (or namespace) plus an
  nginx-proxied tab, with the same per-session persistence model as the terminals.
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
