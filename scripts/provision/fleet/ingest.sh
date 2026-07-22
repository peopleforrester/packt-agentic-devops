#!/usr/bin/env bash
# ABOUTME: Builds the claim app's pool.csv from the live fleet and deploys it, so every pool row
# ABOUTME: points at a cluster that is actually running behind its HTTPS hostname.
#
# A pool row pointing at a dead or wrong cluster is the failure that ruins a workshop, and it is
# invisible to every check that looks only at clusters or only at the app. So a cluster is written
# to the pool only after its own health check passes, and the row carries the router hostname
# rather than a raw NLB address.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

readonly DIST_DIR="${PROVISION_DIR}/distribution"
readonly POOL="${DIST_DIR}/pool.csv"
readonly DIST_SERVICE="packt-provisioning"

DEPLOY=1

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [--no-deploy]

Writes ${POOL} from the live fleet and deploys the ${DIST_SERVICE} service.
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-deploy) DEPLOY=""; shift ;;
        -h|--help) usage ;;
        *) printf 'unknown arg: %s\n' "$1" >&2; usage ;;
    esac
done

main() {
    local account name host total=0 skipped=0
    # The AWS key columns stay empty on purpose: the VTT wires kubectl from its in-cluster
    # ServiceAccount and reaches AWS through Pod Identity, so there is no key to distribute (D8/D21).
    printf 'name,access_key,secret_key,region,terminal_url\n' > "${POOL}"

    while read -r account; do
        while read -r name; do
            [[ -n "${name}" ]] || continue
            host="$(cluster_lb_host "${account}" "${name}" 2>/dev/null || true)"
            if [[ -z "${host}" ]]; then
                log "  ${name}: no LoadBalancer hostname, omitted from the pool"
                skipped=$((skipped + 1))
                continue
            fi
            printf '%s,,,%s,%s/?cluster=%s\n' \
                "${name}" "${PACKT_REGION}" "$(student_url "${name}")" "${name}" >> "${POOL}"
            total=$((total + 1))
        done < <(known_clusters "${account}")
    done < <(accounts_list)

    log "pool: ${total} rows written, ${skipped} skipped"
    [[ "${total}" -gt 0 ]] || die "refusing to deploy an empty pool; every attendee would see the exhausted page"

    if [[ -z "${DEPLOY}" ]]; then
        log "--no-deploy: pool written, not deployed"
        return 0
    fi

    command -v railway >/dev/null 2>&1 || die "railway CLI not found"
    # --no-gitignore is load-bearing: pool.csv is gitignored, and without the flag the deploy ships
    # without it and the app seeds zero clusters.
    log "deploying ${DIST_SERVICE}..."
    ( cd "${DIST_DIR}" && railway up --service "${DIST_SERVICE}" --ci --no-gitignore ) \
        || die "distribution deploy failed"
    log "pool deployed with ${total} clusters"
}

main
