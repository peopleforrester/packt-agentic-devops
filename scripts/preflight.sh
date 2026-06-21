#!/usr/bin/env bash
# ABOUTME: Event-day 7:30 AM ritual. Verifies a cluster, image mirror, checkpoints,
# ABOUTME: model warmth, env vars, and backup videos before going live.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT

# Required inputs (no global kubeconfig is ever used; this is a shared machine).
KUBECONFIG_FILE="${KUBECONFIG_FILE:-}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-}"
GHCR_ORG="${GHCR_ORG:-}"
BACKUP_VIDEO_DIR="${BACKUP_VIDEO_DIR:-}"
# Space-separated names of presenter env vars to confirm exist (values never printed).
REQUIRED_ENV_VARS="${REQUIRED_ENV_VARS:-}"

FAILURES=0

log() { printf '%s\n' "$*" >&2; }
pass() { printf 'PASS  %s\n' "$*" >&2; }
fail() { printf 'FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

usage() {
    cat >&2 <<EOF
Usage: KUBECONFIG_FILE=<path> EXPECTED_CONTEXT=<substr> GHCR_ORG=<org> \\
       BACKUP_VIDEO_DIR=<dir> REQUIRED_ENV_VARS="VAR_A VAR_B" ${0##*/}

Runs the event-day preflight checks against one cluster. Exits nonzero if any check
fails. Uses an explicit kubeconfig file only; never the ambient context.
EOF
    exit 2
}

# kubectl bound to the explicit kubeconfig, never the shared default.
kc() { kubectl --kubeconfig "${KUBECONFIG_FILE}" "$@"; }

check_context() {
    local ctx
    ctx="$(kc config current-context 2>/dev/null || true)"
    if [[ -z "${ctx}" ]]; then
        fail "cluster context: kubeconfig has no current-context"
        return 1
    fi
    if [[ "${ctx}" != *"${EXPECTED_CONTEXT}"* ]]; then
        fail "cluster context: '${ctx}' does not match expected '${EXPECTED_CONTEXT}'"
        return 1
    fi
    if ! kc get nodes >/dev/null 2>&1; then
        fail "cluster reachable: get nodes failed on '${ctx}'"
        return 1
    fi
    pass "cluster reachable and context matches '${EXPECTED_CONTEXT}'"
}

check_argocd() {
    local out unhealthy
    out="$(kc get applications -n argocd \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)"
    if [[ -z "${out}" ]]; then
        fail "argocd: no Applications found"
        return 1
    fi
    unhealthy="$(printf '%s\n' "${out}" | awk '$2!="Synced" || $3!="Healthy" {print $1}')"
    if [[ -n "${unhealthy}" ]]; then
        fail "argocd: not all Synced/Healthy -> ${unhealthy//$'\n'/ }"
        return 1
    fi
    pass "argocd: every Application Synced and Healthy"
}

check_checkpoints() {
    local tag missing=0
    for tag in checkpoint/module-0-start checkpoint/module-1-end \
               checkpoint/module-2-end checkpoint/module-3-end; do
        git -C "${REPO_ROOT}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1 \
            || { fail "checkpoint tag missing: ${tag}"; missing=1; }
    done
    [[ "${missing}" -eq 0 ]] && pass "all checkpoint tags present"
}

check_mirror() {
    [[ -n "${GHCR_ORG}" ]] || { fail "image mirror: GHCR_ORG unset"; return 1; }
    command -v crane >/dev/null 2>&1 || { fail "image mirror: crane not installed"; return 1; }
    local map="${REPO_ROOT}/image-map.tsv"
    [[ -s "${map}" ]] || { fail "image mirror: ${map} missing (run mirror-images.sh)"; return 1; }
    local dst miss=0 n=0
    while IFS=$'\t' read -r _ dst; do
        [[ -n "${dst}" ]] || continue
        n=$((n + 1))
        crane manifest "${dst}" >/dev/null 2>&1 || { fail "image absent in mirror: ${dst}"; miss=1; }
    done <"${map}"
    [[ "${miss}" -eq 0 ]] && pass "image mirror: all ${n} mapped images present in GHCR"
}

check_model_warm() {
    local ready
    ready="$(kc get inferenceservice -n kserve -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == *"True"* ]]; then
        pass "vLLM InferenceService Ready"
    else
        fail "vLLM InferenceService not Ready (status: ${ready:-none})"
    fi
}

check_env_vars() {
    [[ -n "${REQUIRED_ENV_VARS}" ]] || { pass "env vars: none required"; return 0; }
    local v miss=0
    for v in ${REQUIRED_ENV_VARS}; do
        # Existence only. Never print the value.
        [[ -n "${!v:-}" ]] || { fail "env var not set: ${v}"; miss=1; }
    done
    [[ "${miss}" -eq 0 ]] && pass "all required presenter env vars present"
}

check_backup_videos() {
    [[ -n "${BACKUP_VIDEO_DIR}" ]] || { fail "backup videos: BACKUP_VIDEO_DIR unset"; return 1; }
    [[ -d "${BACKUP_VIDEO_DIR}" ]] || { fail "backup videos: dir missing ${BACKUP_VIDEO_DIR}"; return 1; }
    local count
    count="$(find "${BACKUP_VIDEO_DIR}" -maxdepth 1 -type f -name '*.mp4' | wc -l | tr -d ' ')"
    if [[ "${count}" -gt 0 ]]; then
        pass "backup videos: ${count} .mp4 files present"
    else
        fail "backup videos: no .mp4 files in ${BACKUP_VIDEO_DIR}"
    fi
}

main() {
    [[ -n "${KUBECONFIG_FILE}" && -n "${EXPECTED_CONTEXT}" ]] || usage
    [[ -f "${KUBECONFIG_FILE}" ]] || { log "kubeconfig not found: ${KUBECONFIG_FILE}"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log "kubectl not found"; exit 1; }

    log "== preflight: ${EXPECTED_CONTEXT} =="
    check_context
    check_argocd
    check_checkpoints
    check_mirror
    check_model_warm
    check_env_vars
    check_backup_videos

    # Manual confirmation item, surfaced but not auto-checked.
    log "MANUAL  confirm OBS scenes are loaded and the correct scene is live"

    if [[ "${FAILURES}" -gt 0 ]]; then
        log "== preflight FAILED: ${FAILURES} check(s) =="
        exit 1
    fi
    log "== preflight PASSED =="
}

main "$@"
