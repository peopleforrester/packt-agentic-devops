#!/bin/bash
# ABOUTME: Proactive tutor watch. Observes what is ACTUALLY going on in the cluster (crashlooping pods,
# ABOUTME: image-pull errors, Degraded Argo CD apps) and, rate-limited, asks Bedrock for a one-line nudge.
#
# This watches real cluster state via the pod ServiceAccount, not the terminal transcript. A student's
# main terminal is mostly their own agent's full-screen UI, so grepping it for errors is a noisy, weak
# signal. The cluster is the source of truth for "is something actually broken", so that is what we watch.
set -uo pipefail
export HOME=/home/student
export PATH="$HOME/.local/bin:$HOME/workshop:$PATH"
readonly NUDGE_DIR=/run/tutor
readonly NUDGE="${NUDGE_DIR}/nudge.json"
readonly REGION="${AWS_REGION:-us-west-2}"
readonly MODEL="${TUTOR_MODEL:-us.anthropic.claude-sonnet-5}"
readonly COOLDOWN="${TUTOR_NUDGE_COOLDOWN:-300}"    # at most one proactive nudge per this many seconds
readonly POLL="${TUTOR_POLL_INTERVAL:-30}"          # seconds between cluster checks

# The nudge is served to the browser by the nginx sidecar (a different uid), so it must be readable by
# it. entrypoint.sh leaves umask 077 (from the git-credential write), which would make the nudge 0600 and
# nginx would 403. The nudge is a one-line hint with no secret, so write it world-readable.
umask 022
mkdir -p "${NUDGE_DIR}"

# The real failure signal. Pods stuck in a bad phase/waiting reason, and Argo CD apps whose HEALTH is
# Degraded. We deliberately do NOT flag OutOfSync/Progressing: those are normal while a GitOps build
# converges, and nudging on them would fire constantly.
snapshot() {
  kubectl get pods -A --no-headers 2>/dev/null | awk '
    $4 ~ /CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError|Init:Error|^Error$/ {
      print "pod " $1 "/" $2 " " $4 }'
  kubectl get applications -n argocd --no-headers 2>/dev/null | awk '/Degraded/ { print "argocd-app " $1 " Degraded" }'
}

last=0
prev=""
while true; do
  sleep "${POLL}"
  cur="$(snapshot)"
  # Nothing wrong: clear the memory so a later problem is seen fresh.
  [ -z "${cur}" ] && { prev=""; continue; }
  # Require the SAME failure across two consecutive polls (~POLL seconds), so transient churn during a
  # rollout does not trigger a nudge. Only a sustained problem does.
  if [ "${cur}" != "${prev}" ]; then prev="${cur}"; continue; fi

  now=$(date +%s)
  (( now - last < COOLDOWN )) && continue
  last=$now

  read -r -d '' prompt <<EOF || true
A workshop student is building a Kubernetes GitOps platform (Argo CD, an AI plane on EKS). The cluster currently shows these SUSTAINED failures:

${cur}

In ONE short sentence (max 24 words), say what is most likely wrong and that the Tutor tab can help diagnose it. No commands, no code.
EOF
  msg="$(printf '%s' "${prompt}" | jq -Rs '[{role:"user",content:[{text:.}]}]')"
  txt="$(aws bedrock-runtime converse --region "${REGION}" --model-id "${MODEL}" \
           --messages "${msg}" --inference-config '{"maxTokens":80}' \
           --query 'output.message.content[0].text' --output text 2>/dev/null || true)"
  [ -z "${txt}" ] && continue
  printf '{"ts":%s,"nudge":%s}\n' "${now}" "$(printf '%s' "${txt}" | jq -Rs .)" > "${NUDGE}"
  chmod 0644 "${NUDGE}" 2>/dev/null || true
done
