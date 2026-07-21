#!/bin/bash
# ABOUTME: Wires the student VTT: kubectl from the in-cluster ServiceAccount, the AWS CLI from the
# ABOUTME: student's own keys (optional secret), refreshes the pre-cloned repo, then launches ttyd.
set -euo pipefail

SA=/var/run/secrets/kubernetes.io/serviceaccount
export HOME=/home/student
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"
mkdir -p "$HOME/.kube" "$HOME/.aws"

# kubectl talks to THIS cluster via the pod's own ServiceAccount token. No kubeconfig secret needed.
# The context is named after the cluster (CLUSTER_NAME, defaulting to a friendly label) so the
# Starship prompt reads "☸ <cluster>" rather than a generic placeholder. Default namespace is
# "default": the student builds across many namespaces, so the pod's own namespace would mislead.
CTX_NAME="${CLUSTER_NAME:-your-cluster}"
if [ -f "$SA/token" ]; then
  kubectl config set-cluster "$CTX_NAME" \
    --server="https://kubernetes.default.svc" \
    --certificate-authority="$SA/ca.crt" --embed-certs=true >/dev/null
  kubectl config set-credentials me --token="$(cat "$SA/token")" >/dev/null
  kubectl config set-context "$CTX_NAME" --cluster="$CTX_NAME" --user=me \
    --namespace=default >/dev/null
  kubectl config use-context "$CTX_NAME" >/dev/null
  echo "kubectl is wired to your cluster (context: $CTX_NAME)." > "$HOME/.motd"
else
  echo "WARNING: no in-cluster ServiceAccount token found; kubectl is not auto-configured." > "$HOME/.motd"
fi

# Pre-configure the AWS CLI with the student's OWN keys (mounted as the optional `student-aws-creds`
# secret -> env). Written as the DEFAULT profile so `aws` works with no --profile inside the VTT. On a
# cluster without the secret, aws is installed but unconfigured; kubectl still works via the SA above.
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  cat > "$HOME/.aws/credentials" <<CREDS
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
CREDS
  cat > "$HOME/.aws/config" <<CFG
[default]
region = ${AWS_DEFAULT_REGION:-us-west-2}
output = json
CFG
  chmod 600 "$HOME/.aws/credentials"
  printf 'aws is configured with your keys (default profile, region %s).\n' "${AWS_DEFAULT_REGION:-us-west-2}" >> "$HOME/.motd"
fi

# Point the student's working copy at the IN-CLUSTER Gitea, which is what ArgoCD reconciles from. Without
# this the clone still points at the public GitHub repo, so the student can commit but never push, and the
# GitOps loop never closes for them: their change cannot reach ArgoCD. With it, `git push` lands in Gitea
# and ArgoCD applies their own commit, which is the whole point of the workshop.
if [ -d "$HOME/workshop/.git" ]; then
  if [ -n "${GITEA_REPO_URL:-}" ]; then
    # Credentials are embedded in the remote so push needs no prompt. This is the throwaway dev admin on
    # the student's own single-tenant cluster, the same posture as the OpenBao dev token.
    if [ -n "${GITEA_USER:-}" ] && [ -n "${GITEA_PASSWORD:-}" ]; then
      _host="${GITEA_REPO_URL#http://}"
      _remote="http://${GITEA_USER}:${GITEA_PASSWORD}@${_host}"
    else
      _remote="${GITEA_REPO_URL}"
    fi
    git -C "$HOME/workshop" remote set-url origin "${_remote}" 2>/dev/null || \
      git -C "$HOME/workshop" remote add origin "${_remote}" 2>/dev/null || true
    git -C "$HOME/workshop" fetch --quiet origin 2>/dev/null || true
    git -C "$HOME/workshop" checkout -q -B main origin/main 2>/dev/null || true
    git -C "$HOME/workshop" config user.email "student@workshop.local" 2>/dev/null || true
    git -C "$HOME/workshop" config user.name  "Workshop Student" 2>/dev/null || true
    printf 'git remote points at your in-cluster Gitea; commit and push to have ArgoCD apply it.\n' >> "$HOME/.motd"
  else
    # No in-cluster Git wired: fall back to refreshing the public read-only clone.
    git -C "$HOME/workshop" pull --ff-only --quiet 2>/dev/null || true
  fi
fi

cat > "$HOME/.bashrc" <<'BRC'
cat ~/.motd 2>/dev/null
printf '\n\033[38;5;208m▌\033[0m \033[1mAgentic DevOps with Claude\033[0m — your workshop terminal\n'
echo "  kubectl is wired to your cluster   (try: kubectl get nodes)"
echo "  the workshop repo is at ~/workshop (you start here)"
echo "  build it with Claude Code          (run: claude)"
echo "  then follow the phases in the panel on the left, one prompt at a time."
echo
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"
export KUBE_EDITOR=vim
cd "$HOME/workshop" 2>/dev/null || cd "$HOME"
# Starship: rich prompt with cluster context, AWS, git, and dir. Config baked at ~/.config/starship.toml.
eval "$(starship init bash)"
BRC

# -W writable (interactive); -b serves under /terminal so a fronting router can proxy it on a subpath.
# Auth/exposure are handled upstream by the per-student router; this is the student's own cluster.
# The theme is tuned to the Packt palette (orange cursor, ink background) so the terminal matches the
# lab wrapper. A monospace stack with emoji fallback lets the Starship symbols render.
exec ttyd -p 7681 -W -b /terminal \
  -t fontSize=15 \
  -t 'fontFamily=ui-monospace, "SFMono-Regular", "JetBrains Mono", Menlo, Consolas, "Segoe UI Emoji", monospace' \
  -t cursorStyle=bar \
  -t 'theme={"background":"#0f1117","foreground":"#e6e1f0","cursor":"#FA7040","cursorAccent":"#0f1117","selectionBackground":"#FA704055","black":"#191919","brightBlack":"#4A4A4A","red":"#ff6b6b","green":"#2e9e5b","yellow":"#FFB454","blue":"#6db3f2","magenta":"#b48ead","cyan":"#5fb3b3","white":"#e6e1f0","brightWhite":"#ffffff"}' \
  bash --rcfile "$HOME/.bashrc"
