#!/bin/bash
# ABOUTME: Launches the Workshop Tutor: Claude Code on Amazon Bedrock (Sonnet 5) via the cluster's EKS
# ABOUTME: Pod Identity, read-only (plan mode), with the whole workbench as context. Served on ttyd :7682.
set -uo pipefail
export HOME=/home/student
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"

# Isolate the tutor's Claude config from the student's own ~/.claude (which is on the PVC and holds the
# student's subscription login). The tutor runs on Bedrock with no login; separate config dirs keep the
# two from mixing (the tutor must not inherit or clobber the student's session or auth).
export CLAUDE_CONFIG_DIR="$HOME/.claude-tutor"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Bedrock backend, authenticated by Pod Identity (no API key in the image or a Secret). Region and model
# are pinned; the pod's Pod Identity role grants bedrock:InvokeModel on the Sonnet 5 model (see
# student-aws-creds.sh). The AWS SDK reads Pod Identity from AWS_CONTAINER_CREDENTIALS_FULL_URI at runtime.
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION="${AWS_REGION:-us-west-2}"
export ANTHROPIC_MODEL="${TUTOR_MODEL:-us.anthropic.claude-sonnet-5}"

SYS="$(cat /opt/tutor/system-prompt.md 2>/dev/null || true)"
cd "$HOME/workshop" 2>/dev/null || cd "$HOME"

# Pre-trust the workshop directory so the tutor does not show the first-run "trust this folder" dialog on
# connect (it would otherwise stall a stuck student behind a prompt). Idempotent; jq is in the image.
CJSON="${CLAUDE_CONFIG_DIR}/.claude.json"
[ -f "${CJSON}" ] || echo '{}' > "${CJSON}"
if _t="$(jq --arg p "$HOME/workshop" '.projects[$p].hasTrustDialogAccepted=true' "${CJSON}" 2>/dev/null)"; then
  printf '%s' "${_t}" > "${CJSON}"
fi

# Plan mode is the read-only posture: the tutor investigates (reads files, runs read-only kubectl) and
# advises, but does not apply changes. If Bedrock is unreachable (no Pod Identity, model access off),
# Claude Code exits and the caller's restart loop retries; the tab shows the error rather than a blank.
exec claude --append-system-prompt "${SYS}" --permission-mode plan
