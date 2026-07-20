# Student web terminal (VTT)

The browser terminal a student lands in from the credential-claim email. A two-pane console
(instructions left, terminal right) plus a live architecture blueprint and an endpoint directory.

## Parts

- `web-terminal.yaml` — the Kubernetes manifest: namespace, ServiceAccount, scoped RBAC, the pod
  (three containers: `ttyd`, `nginx`, a read-only `status` phase detector), the LoadBalancer Service,
  and the `student-claude` PVC.
- `web/lab.html` — the two-pane lab page (front door), with the nine-phase walkthrough and the
  Blueprint / Endpoints tabs.
- `web/diagram.html` — the interactive architecture blueprint (`/diagram`), progressive reveal 0..8,
  with a Live toggle that follows real cluster progress via `/api/status`.
- `web/links.html` — the component endpoint directory (`/links`).
- `web/console.conf` — nginx: serves the pages and reverse-proxies `/terminal/` to ttyd, plus
  `/api/status`.
- `web/status-loop.sh` — the phase detector, run by the status sidecar.
- `apply.sh` — generates the ConfigMaps from `web/` and rolls the deployment. Needs `KUBECONFIG` and
  `AWS_PROFILE`; set `EXPECT_CONTEXT` to guard the target cluster.
- The image is built from `images/web-terminal/` (ttyd, kubectl, AWS CLI, helm, eksctl, k9s, yq,
  Starship, tmux, Claude Code, the workshop repo pre-cloned) and published to
  `ghcr.io/peopleforrester/packt-agentic-devops:web-terminal` (public).

## Session persistence

- **Login + conversation across a pod restart: a 1Gi PVC on `~/.claude`.** The PVC keeps the Claude Code
  login and conversation history, so a pod restart does not log the student out and `claude --continue`
  resumes the conversation. Deployment strategy is `Recreate` (the PVC is ReadWriteOnce) and `fsGroup:
  1000` makes the volume writable by the student user. Needs a default StorageClass (the EBS CSI `gp3`
  default on EKS).
- **Browser refresh** starts a fresh shell (ttyd spawns a new process per connection). A tmux-based
  re-attach layer was tried and removed; if session-survives-refresh is wanted later, that is where it goes.

## Fleet notes (300 clusters)

- The image is public on GHCR and anonymously pullable (no imagePullSecret). At 300 clusters pulling at
  once, prefer an in-region mirror to avoid GHCR burst latency: an **ECR pull-through cache**, or a
  shared **Harbor** (CNCF) proxy-cache. Pin by digest for cache-friendliness and immutability.
