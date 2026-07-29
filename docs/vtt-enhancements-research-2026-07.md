# VTT / IDE / Jupyter enhancement research spike (2026-07-29)

A survey of features and products worth adding to the student workbench (the ttyd terminal,
the code-server VS Code tab, and the JupyterLab tab). Product currency verified by web
search on 2026-07-29; re-verify versions before adopting any of these.

## What constrains the choices

The workbench is one disposable, single-tenant pod per student: nginx fronts ttyd,
code-server, and JupyterLab, all sharing `/home/student` and the Gitea-wired `~/workshop`.
Three constraints shape what fits:

- **Behind an nginx subpath, auth upstream.** Anything added is another surface on the same
  predictable, unauthenticated public URL (the known blocker owned by the separate auth
  project). Every item below inherits that caveat.
- **CPU only, no GPU.** The in-cluster vLLM is Qwen3-1.7B and it only exists after phase 6.
  Anything that wants a strong model at phase 0 needs an external backend.
- **Ephemeral, one user.** Multi-user servers (JupyterHub) are the wrong shape; per-pod
  single-user tools are right.

## Categories

### 1. AI inside the editor and the notebook

- **Cline** (VS Code, on Open VSX, ~58k stars): open-source agentic coding extension,
  model-agnostic. It talks to any OpenAI-compatible endpoint, which means it can point at
  the in-cluster vLLM OR an external model with one setting. Installable into code-server
  from Open VSX. Strong fit for "AI help right in the editor."
- **Continue** (VS Code, on Open VSX): open-source assistant, also supports local /
  self-hosted models. A lighter alternative to Cline.
- **Roo Code: do NOT adopt.** It shut down as a VS Code extension on 2026-05-15 (the team
  moved to Roomote, a Slack cloud agent). Recommending it would be adopting a discontinued
  product.
- **Jupyter AI** (`jupyter-ai`, the Jupyternaut persona): native chat UI in JupyterLab, AI
  magic commands (`%%ai`), and Jupyternaut code completion. Recent versions integrate agents
  through the Agent Client Protocol (Claude, Codex, Copilot, Gemini, Goose, and others) and
  can run against a local model via Ollama or any OpenAI-compatible endpoint. This is the
  notebook-side equivalent of Cline.

Fit: medium. Each is an extension install plus a model-backend decision (see the PRD 7
cross-reference). Note that Cline/Jupyter AI pointed at a backend is effectively an
off-the-shelf tutor, which may be simpler than the bespoke sidecar in PRD 7.

### 2. Real-time collaboration and instructor-follow

The July 23 run showed the instructor hand-diagnosing one terminal at a time. Collaboration
tools scale that directly.

- **sshx**: a Rust collaborative web terminal, end-to-end encrypted, multiplayer canvas with
  live remote cursors, built explicitly for teaching and workshops (an instructor demos a
  CLI and students follow, or an instructor drops into a stuck student's terminal by link).
  Would run as another process in the pod; the "share link" model needs thought against the
  unauthenticated-surface caveat.
- **jupyter-collaboration** (Yjs-based RTC, JupyterLab 4+): install one server extension and
  a notebook URL becomes shared-editable in real time. Lets an instructor co-edit a stuck
  student's notebook. Single extension, low effort.
- **VS Code Live Share**: proprietary and Microsoft-account gated; no clean self-hosted
  equivalent for code-server. sshx covers the terminal case; jupyter-collaboration covers the
  notebook case. Skip Live Share.

Fit: sshx medium (new process + share-link security), jupyter-collaboration easy.

### 3. Preview a running service in a tab

code-server already ships a proxy: `/proxy/:port/` (strips the prefix) and `/absproxy/:port/`
(passes the full path), plus a Ports panel driven by `VSCODE_PROXY_URI`. A student could open
a service running on their cluster (their deployed agent-service, Backstage, Grafana) in a
browser preview without leaving the IDE. Low effort, high "it works!" value, and it reuses
code-server machinery already in the image.

Fit: easy to medium (set `VSCODE_PROXY_URI`, document the pattern).

### 4. Session capture and replay

- **asciinema**: records a structured, timestamped cast and replays it in the browser. Two
  uses: feed the recent cast to the tutor agent (this is the capture layer in PRD 7, and
  asciinema's structured output is easier to parse than a raw `script` typescript), and let a
  student or instructor replay "what did I just do." Pairs naturally with PRD 7.

Fit: easy (a recorder wrapping the shell) to medium (a replay tab).

### 5. Notebook power tools (JupyterLab extensions)

Cheap, well-worn quality-of-life extensions, each a pip install into the Jupyter venv:
`jupyterlab-git` (git UI), `jupyterlab-lsp` (completion/diagnostics), `jupyterlab_execute_time`
(per-cell timing), `jupyterlab-variableInspector`, `jupyter-resource-usage` (live CPU/RAM,
useful given the 8Gi cap). **Voila** turns a notebook into a shareable dashboard, which fits
the AI-plane "send an inference request and plot the result" beat.

Fit: easy.

### 6. Terminal UX

- **A multiplexer tab** (zellij or tmux) for split panes inside one terminal. Note: tmux was
  removed as a *refresh-persistence* layer; a multiplexer as an in-terminal split tool is a
  different, additive use and would not reintroduce that complexity.
- **File upload/download** in the browser terminal (ttyd supports it) so students can pull a
  manifest out or drop one in.

Fit: easy to medium.

### 7. Embedded platform UIs

Already tracked in the backlog ("auto-discovered, clickable UIs"): embed ArgoCD, Grafana,
Backstage, or a k8s dashboard (**Headlamp** is a good CNCF-adjacent option) as tabs. k9s is
already in the image and could get its own ttyd-backed tab. Fragile per component (each needs
subpath config), so scope narrowly.

Fit: medium to hard (per-component subpath config).

## Recommended next steps, ranked

1. **AI in the editor/notebook (Cline + Jupyter AI), wired to a chosen backend.** Highest
   learner value and it merges with the PRD 7 tutor: adopting Cline/Jupyter AI pointed at a
   backend may replace the bespoke sidecar. Gated on the same model-backend decision.
2. **Service-preview via code-server's port proxy.** Cheap, high delight, reuses existing
   machinery.
3. **Notebook power tools + `jupyter-resource-usage`.** Easy wins; resource-usage is
   genuinely useful under the 8Gi cap.
4. **jupyter-collaboration for instructor co-editing.** One extension, directly addresses the
   "instructor can't reach everyone" pain.
5. **sshx for collaborative terminals.** Powerful for teaching; needs a security pass against
   the unauthenticated-surface caveat before it goes live.

## Cross-references

- PRD 7 (terminal capture + tutor agent): Cline / Jupyter AI / asciinema are directly
  relevant. The tutor's model backend is the same open decision.
- Every item rides the unauthenticated-surface caveat; the separate terminal-auth project
  must cover any new path.

Sources (2026-07-29): jupyterlab/jupyter-ai releases and jupyter.org/ai; Cline on Open VSX
and the Roo/Cline 2026 comparisons (Roo Code shutdown 2026-05-15); sshx.io; jupyterlab
jupyter-collaboration docs; coder/code-server proxy docs.
