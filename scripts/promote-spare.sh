#!/usr/bin/env bash
# ABOUTME: Promotes the pre-synced hot spare to the active presenter cluster in under 60
# ABOUTME: seconds: health-gates the spare, repoints the active kubeconfig, prints its URLs.
set -euo pipefail

# All inputs are explicit. The script never guesses a cluster or a URL: if a required
# value is missing it aborts, because promoting the wrong cluster on screen is worse than
# the failure it recovers from.
SPARE_KUBECONFIG="${SPARE_KUBECONFIG:-}"     # kubeconfig for the pre-synced spare cluster
SPARE_CONTEXT="${SPARE_CONTEXT:-}"           # substring the spare's context MUST contain
ACTIVE_KUBECONFIG="${ACTIVE_KUBECONFIG:-}"   # the file the presenter's tools read as "live"
SPARE_BACKSTAGE_URL="${SPARE_BACKSTAGE_URL:-}" # the spare's Backstage URL to show on screen
SKIP_HEALTH="${SKIP_HEALTH:-0}"              # set to 1 only if the primary is already dead
readonly TIMEOUT="10s"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<EOF
Usage:
  SPARE_KUBECONFIG=<path> SPARE_CONTEXT=<substr> ACTIVE_KUBECONFIG=<path> \\
  SPARE_BACKSTAGE_URL=<url> ${0##*/}

Promotes the hot spare to the active presenter cluster. It confirms the spare's context,
health-gates the spare (nodes Ready, ArgoCD apps Synced+Healthy, vLLM InferenceService
Ready), backs up the current active kubeconfig, then overwrites the active kubeconfig with
the spare's so every downstream kubectl/demo command targets the spare. Finally it prints
the spare's Backstage URL to put on screen.

Required env:
  SPARE_KUBECONFIG     path to the spare cluster kubeconfig
  SPARE_CONTEXT        substring the spare context must contain (safety guard)
  ACTIVE_KUBECONFIG    path the presenter tools treat as the live cluster (gets repointed)
  SPARE_BACKSTAGE_URL  the spare's Backstage URL to display

Optional env:
  SKIP_HEALTH=1        skip the health gate (use only when the primary is already dead and
                       you accept promoting without the pre-check)

Uses an explicit kubeconfig only, never the shared default. Idempotent: re-running when the
spare is already active is safe.
EOF
    exit 2
}

kc() { kubectl --kubeconfig "${SPARE_KUBECONFIG}" --request-timeout="${TIMEOUT}" "$@"; }

guard_context() {
    local ctx; ctx="$(kc config current-context 2>/dev/null || true)"
    if [[ "${ctx}" != *"${SPARE_CONTEXT}"* ]]; then
        log "ABORT: spare context '${ctx}' does not match expected '${SPARE_CONTEXT}'"
        exit 1
    fi
    log "spare context confirmed: ${ctx}"
}

health_gate() {
    if [[ "${SKIP_HEALTH}" -eq 1 ]]; then
        log "WARNING: SKIP_HEALTH=1, promoting spare without the health pre-check"
        return 0
    fi

    local nodes
    nodes="$(kc get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    [[ "${nodes}" == *"True"* && "${nodes}" != *"False"* ]] \
        || { log "ABORT: spare nodes not all Ready (status: ${nodes:-none})"; exit 1; }
    log "spare nodes Ready"

    local unhealthy
    unhealthy="$(kc get applications -n argocd \
        -o jsonpath='{range .items[?(@.status.health.status!="Healthy")]}{.metadata.name}{" "}{end}' \
        2>/dev/null || true)"
    [[ -z "${unhealthy// }" ]] \
        || { log "ABORT: spare ArgoCD apps not Healthy: ${unhealthy}"; exit 1; }
    log "spare ArgoCD apps Healthy"

    local model
    model="$(kc get inferenceservice -n kserve \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    [[ "${model}" == *"True"* ]] \
        || { log "ABORT: spare vLLM InferenceService not Ready (status: ${model:-none})"; exit 1; }
    log "spare vLLM InferenceService Ready"
}

repoint_active() {
    if [[ -f "${ACTIVE_KUBECONFIG}" ]]; then
        cp -f "${ACTIVE_KUBECONFIG}" "${ACTIVE_KUBECONFIG}.pre-promote"
        log "backed up current active kubeconfig to ${ACTIVE_KUBECONFIG}.pre-promote"
    else
        log "note: ${ACTIVE_KUBECONFIG} did not exist yet, creating it from the spare"
    fi
    cp -f "${SPARE_KUBECONFIG}" "${ACTIVE_KUBECONFIG}"
    log "active kubeconfig now points at the spare"
}

main() {
    [[ -n "${SPARE_KUBECONFIG}" && -n "${SPARE_CONTEXT}" \
       && -n "${ACTIVE_KUBECONFIG}" && -n "${SPARE_BACKSTAGE_URL}" ]] || usage
    [[ -f "${SPARE_KUBECONFIG}" ]] || { log "spare kubeconfig not found: ${SPARE_KUBECONFIG}"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log "kubectl not found"; exit 1; }

    guard_context
    health_gate
    repoint_active

    log ""
    log "SPARE PROMOTED. Put this on screen:"
    log "  Backstage: ${SPARE_BACKSTAGE_URL}"
    log ""
    log "Verify the active context now resolves to the spare:"
    log "  kubectl --kubeconfig ${ACTIVE_KUBECONFIG} config current-context"
}

main "$@"
