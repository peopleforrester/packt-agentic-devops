#!/usr/bin/env bash
# ABOUTME: Builds the distribution app's pool.csv from a running fleet: for each cluster it reads that
# ABOUTME: cluster's VTT LoadBalancer hostname and writes a terminal-only row (no AWS keys; the VTT wires
# ABOUTME: kubectl from its in-cluster ServiceAccount). One row per student cluster, keyed to its own URL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly NS="workshop"

# A single throwaway kubeconfig reused per cluster; cleaned up on any exit. Global so the EXIT trap can
# always see it (a function-local would be out of scope by the time the trap fires).
KC="$(mktemp)"
readonly KC
trap 'rm -f "${KC}"' EXIT

usage() {
    cat >&2 <<USAGE
Usage: $0 --profile <aws-profile> --region <region> [--out <pool.csv>]
          [--clusters-file <file>] [<cluster> ...]

Writes name,access_key,secret_key,region,terminal_url rows (keys empty) for each cluster whose VTT
LoadBalancer has a hostname. Clusters come from positional args and/or --clusters-file (one name per line).
Default --out is scripts/provision/distribution/pool.csv.
USAGE
}

main() {
    local profile="" region="" out="" clusters_file=""
    local -a clusters=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile="$2"; shift 2 ;;
            --region) region="$2"; shift 2 ;;
            --out) out="$2"; shift 2 ;;
            --clusters-file) clusters_file="$2"; shift 2 ;;
            -h|--help) usage; exit 2 ;;
            -*) printf 'unknown flag: %s\n' "$1" >&2; usage; exit 2 ;;
            *) clusters+=("$1"); shift ;;
        esac
    done

    [[ -n "${profile}" && -n "${region}" ]] || { usage; exit 2; }
    command -v aws >/dev/null 2>&1 || { printf 'aws CLI not found\n' >&2; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { printf 'kubectl not found\n' >&2; exit 1; }
    out="${out:-${SCRIPT_DIR}/distribution/pool.csv}"

    if [[ -n "${clusters_file}" ]]; then
        [[ -f "${clusters_file}" ]] || { printf 'no such file: %s\n' "${clusters_file}" >&2; exit 1; }
        while IFS= read -r line; do
            line="${line%%#*}"; line="$(printf '%s' "${line}" | tr -d '[:space:]')"
            [[ -n "${line}" ]] && clusters+=("${line}")
        done < "${clusters_file}"
    fi
    (( ${#clusters[@]} )) || { printf 'no clusters given\n' >&2; usage; exit 2; }

    printf 'name,access_key,secret_key,region,terminal_url\n' > "${out}"

    local total="${#clusters[@]}" i=0 written=0

    for cluster in "${clusters[@]}"; do
        i=$((i + 1))
        printf '[%d/%d] %s: ' "${i}" "${total}" "${cluster}" >&2
        if ! aws eks update-kubeconfig --name "${cluster}" --region "${region}" \
                --profile "${profile}" --kubeconfig "${KC}" >/dev/null 2>&1; then
            printf 'SKIP (no cluster creds)\n' >&2; continue
        fi
        local ctx; ctx="$(KUBECONFIG="${KC}" kubectl config current-context 2>/dev/null || true)"
        if [[ "${ctx}" != *"${cluster}"* ]]; then
            printf 'SKIP (context %q does not match)\n' "${ctx}" >&2; continue
        fi
        local host
        host="$(KUBECONFIG="${KC}" kubectl -n "${NS}" get svc web-terminal \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
        if [[ -z "${host}" ]]; then
            printf 'SKIP (VTT LoadBalancer has no hostname yet)\n' >&2; continue
        fi
        printf '%s,,,%s,http://%s/?cluster=%s\n' "${cluster}" "${region}" "${host}" "${cluster}" >> "${out}"
        written=$((written + 1))
        printf 'ok\n' >&2
    done

    printf '\nWrote %d/%d rows to %s\n' "${written}" "${total}" "${out}" >&2
}

main "$@"
