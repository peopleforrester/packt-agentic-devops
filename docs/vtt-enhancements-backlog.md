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
The "+" menu's **VS Code** and **Jupyter** items are live. code-server (4.133.0) and single-user JupyterLab
(4.6) run in the web-terminal container beside ttyd, sharing `/home/student` and the Gitea-wired
`~/workshop`, so a file edited in any tab shows up in the others. nginx proxies `/ide/` (prefix-stripped)
and `/jupyter/` (base_url-prefixed) with the same websocket upgrade ttyd uses; both are backgrounded restart
loops in `entrypoint.sh`. The separate **Browser IDE** stub was folded into the VS Code tab (same thing).
Design: `prds/5-browser-ide.md`, `prds/6-jupyter.md`. Auth stays upstream, so the terminal-auth project must
cover `/ide/` and `/jupyter/` too.

### 5. Unified Workshop Tutor — DONE
One read-only tutor that sees the whole workbench and helps a stuck student. It runs the agent CLI in a
dedicated tutor posture on Amazon Bedrock (Claude Sonnet 5), authenticated by the cluster's EKS Pod
Identity, so it is provisioned inline with the lab and keyless (the grant is in `student-aws-creds.sh`).
It reads the shared `~/workshop` tree (the IDE's files and the Jupyter notebooks), the phase specs, the
terminal transcript (captured via `script`), and the cluster over read-only kubectl. Surfaced as a
prominent, lazy-loaded **Tutor** tab (ttyd on :7682, proxied at `/tutor/`), plus a proactive banner: a
watcher tails the transcript for failures and, rate-limited and secret-scrubbed, asks Bedrock for a
one-line nudge served at `/api/tutor-nudge`. Design: `prds/7-terminal-capture-ai-help.md`. Verified on
admin1 and admin2 2026-07-30. Auth stays upstream, so the terminal-auth project must cover `/tutor/` too.

### 6. JupyterLab power tools — DONE
Added to the Jupyter venv: `jupyter-resource-usage` (live CPU/RAM in the toolbar, useful under the 8Gi
cap), `jupyterlab-git` (git UI for the GitOps workshop), `jupyterlab_execute_time` (per-cell timing), and
`ipywidgets`. All enabled and JupyterLab-4.6 compatible. From the recommendations in
`vtt-enhancements-research-2026-07.md`.

### Tutor proactive nudge — reworked and verified (2026-07-31)
The proactive watcher now polls real cluster state (crashlooping pods, image-pull errors, Degraded Argo CD
apps) via the pod ServiceAccount, not the terminal transcript, and only nudges on a failure sustained
across two polls. Verified end to end on admin1: a real ImagePullBackOff produced an accurate Bedrock
nudge served at `/api/tutor-nudge` (a umask/permission bug that had it returning 403 to the browser was
found and fixed in the same pass). The tutor also skips the first-run theme/trust prompts, and the
instructions panel now has a collapse control on the panel itself.

## Still open (v2 ideas)
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
