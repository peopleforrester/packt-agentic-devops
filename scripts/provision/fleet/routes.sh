#!/usr/bin/env bash
# ABOUTME: Regenerates the router's hostname-to-NLB table from the live fleet and deploys it, so
# ABOUTME: every student reaches their cluster over HTTPS at studentN.packt.ai-enhanced-devops.com.
#
# Run after every scale change. A routing table that describes a fleet which no longer exists sends
# students to a dead NLB, and that failure is invisible from the cluster side.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROUTER_DIR="${PROVISION_DIR}/router"
ROUTES_MAP="${ROUTER_DIR}/routes.map"
CADDYFILE="${ROUTER_DIR}/Caddyfile"
readonly ROUTER_DIR ROUTES_MAP CADDYFILE
readonly ROUTER_SERVICE="packt-router"

DEPLOY=1
ALLOW_EMPTY=""

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [--no-deploy] [--allow-empty]

Reads every known cluster's LoadBalancer hostname, writes routes.map and the rendered Caddyfile,
and deploys the ${ROUTER_SERVICE} Railway service.

  --no-deploy     stop after rendering
  --allow-empty   permit a table with zero routes (bootstrapping the service before any cluster
                  exists; every hostname then serves the 404 page, which is correct pre-fleet)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-deploy) DEPLOY=""; shift ;;
        --allow-empty) ALLOW_EMPTY=1; shift ;;
        -h|--help) usage ;;
        *) printf 'unknown arg: %s\n' "$1" >&2; usage ;;
    esac
done

main() {
    mkdir -p "${ROUTER_DIR}"
    local account name host total=0 missing=0
    : > "${ROUTES_MAP}"

    while read -r account; do
        while read -r name; do
            [[ -n "${name}" ]] || continue
            host="$(cluster_lb_host "${account}" "${name}" 2>/dev/null || true)"
            if [[ -z "${host}" ]]; then
                log "  ${name}: no LoadBalancer hostname yet, omitted from the routing table"
                missing=$((missing + 1))
                continue
            fi
            printf '\t\t%s.%s\t%s\n' "${name}" "${PACKT_DOMAIN}" "${host}" >> "${ROUTES_MAP}"
            total=$((total + 1))
        done < <(known_clusters "${account}")
    done < <(accounts_list)

    log "routing table: ${total} clusters mapped, ${missing} omitted"
    # An empty table means every student gets a 404, so it is refused unless asked for explicitly.
    # The one legitimate case is bootstrapping the service before the first cluster exists.
    [[ "${total}" -gt 0 || -n "${ALLOW_EMPTY}" ]] \
        || die "no clusters have a LoadBalancer hostname; refusing to deploy an empty router"

    # Render the template. A cluster whose row is missing must 404 on a real page, never proxy to a
    # stale upstream, so the map's default stays empty rather than falling back to any cluster.
    python3 - <<PY
import pathlib
tmpl = pathlib.Path("${ROUTER_DIR}/Caddyfile.tmpl").read_text()
routes = pathlib.Path("${ROUTES_MAP}").read_text().rstrip("\n")
pathlib.Path("${CADDYFILE}").write_text(tmpl.replace("{{ROUTES}}", routes))
PY
    log "rendered ${CADDYFILE}"

    if [[ -z "${DEPLOY}" ]]; then
        log "--no-deploy: stopping after render"
        return 0
    fi

    command -v railway >/dev/null 2>&1 || die "railway CLI not found"
    log "deploying ${ROUTER_SERVICE}..."
    # --no-gitignore is load-bearing: the rendered Caddyfile and routes.map are gitignored (they are
    # generated), and without this flag the deploy ships a router with no routing table at all.
    # .railwayignore is then the only ignore list.
    ( cd "${ROUTER_DIR}" && railway up --service "${ROUTER_SERVICE}" --ci --no-gitignore ) \
        || die "router deploy failed"
    log "router deployed with ${total} routes"
}

main
