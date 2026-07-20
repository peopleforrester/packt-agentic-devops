#!/bin/bash
# ABOUTME: Wires the student VTT: kubectl from the in-cluster ServiceAccount, the AWS CLI from the
# ABOUTME: student's own keys (optional secret), refreshes the pre-cloned repo, then launches ttyd.
set -euo pipefail

SA=/var/run/secrets/kubernetes.io/serviceaccount
export HOME=/home/student
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"
mkdir -p "$HOME/.kube" "$HOME/.aws"

# kubectl talks to THIS cluster via the pod's own ServiceAccount token. No kubeconfig secret needed.
if [ -f "$SA/token" ]; then
  kubectl config set-cluster this \
    --server="https://kubernetes.default.svc" \
    --certificate-authority="$SA/ca.crt" --embed-certs=true >/dev/null
  kubectl config set-credentials me --token="$(cat "$SA/token")" >/dev/null
  kubectl config set-context this --cluster=this --user=me \
    --namespace="$(cat "$SA/namespace")" >/dev/null
  kubectl config use-context this >/dev/null
  echo "kubectl is wired to THIS cluster (namespace: $(cat "$SA/namespace"))." > "$HOME/.motd"
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

# Refresh the pre-cloned workshop repo so a restarted pod picks up the latest committed materials. The
# repo is public, so this needs no credentials. A failure here is non-fatal: the baked-in copy still works.
if [ -d "$HOME/workshop/.git" ]; then
  git -C "$HOME/workshop" pull --ff-only --quiet 2>/dev/null || true
fi

cat > "$HOME/.bashrc" <<'BRC'
cat ~/.motd 2>/dev/null
echo "Welcome to your Agentic DevOps with Claude workshop terminal."
echo "  kubectl is wired to your cluster   (try: kubectl get nodes)"
echo "  aws is ready with your keys        (try: aws sts get-caller-identity)"
echo "  the workshop repo is at ~/workshop (cd ~/workshop)"
echo "  start building with Claude Code    (run: claude)"
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"
cd "$HOME/workshop" 2>/dev/null || cd "$HOME"
export PS1='\[\e[38;5;208m\]workshop\[\e[0m\]:\w$ '
BRC

# -W writable (interactive); -b serves under /terminal so a fronting router can proxy it on a subpath.
# Auth/exposure are handled upstream by the per-student router; this is the student's own cluster.
exec ttyd -p 7681 -W -b /terminal -t fontSize=14 -t 'theme={"background":"#0f1117"}' bash --rcfile "$HOME/.bashrc"
