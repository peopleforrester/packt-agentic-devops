#!/bin/bash
# ABOUTME: Proactive tutor watch. Tails the terminal transcript for failure signatures and, rate-limited,
# ABOUTME: asks Bedrock (Sonnet 5) for a one-line nudge that the lab page shows as a dismissible banner.
set -uo pipefail
export HOME=/home/student
readonly TRANSCRIPT="$HOME/.session/transcript"
readonly NUDGE_DIR=/run/tutor
readonly NUDGE="${NUDGE_DIR}/nudge.json"
readonly REGION="${AWS_REGION:-us-west-2}"
readonly MODEL="${TUTOR_MODEL:-us.anthropic.claude-sonnet-5}"
readonly COOLDOWN="${TUTOR_NUDGE_COOLDOWN:-180}"   # at most one proactive nudge per this many seconds

mkdir -p "${NUDGE_DIR}"

# Error signatures worth a proactive nudge. Deliberately specific, so benign output does not trip it.
readonly SIGS='error:|Error:|OutOfSync|Degraded|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|FailedMount|no matches for kind|connection refused|Unable to connect|denied the request|is forbidden|Back-off restarting'

strip_ansi() { sed -r 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b\][0-9;]*(\x07|\x1b\\)//g'; }

# Wait for the transcript to exist (the capture layer creates it on first shell connect).
for _ in $(seq 1 60); do [ -f "${TRANSCRIPT}" ] && break; sleep 2; done
[ -f "${TRANSCRIPT}" ] || exit 0

last=0
# Follow new transcript lines, strip escapes, and react on the first error signature per cooldown window.
tail -n0 -F "${TRANSCRIPT}" 2>/dev/null | strip_ansi | grep --line-buffered -iE "${SIGS}" \
| while IFS= read -r _hit; do
    now=$(date +%s)
    (( now - last < COOLDOWN )) && continue
    last=$now

    # Feed the recent tail (secret-scrubbed) as context for one short nudge.
    ctx="$(tail -c 4000 "${TRANSCRIPT}" | strip_ansi | /opt/tutor/scrub.sh)"
    read -r -d '' prompt <<EOF || true
A workshop student is building a Kubernetes GitOps platform and just hit an error in their terminal. Recent terminal output:

${ctx}

In ONE short sentence (max 24 words), say what likely went wrong and that the Tutor tab can help. No commands, no code.
EOF
    msg="$(printf '%s' "${prompt}" | jq -Rs '[{role:"user",content:[{text:.}]}]')"
    txt="$(aws bedrock-runtime converse --region "${REGION}" --model-id "${MODEL}" \
             --messages "${msg}" --inference-config '{"maxTokens":80}' \
             --query 'output.message.content[0].text' --output text 2>/dev/null || true)"
    [ -z "${txt}" ] && continue
    printf '{"ts":%s,"nudge":%s}\n' "${now}" "$(printf '%s' "${txt}" | jq -Rs .)" > "${NUDGE}"
done
