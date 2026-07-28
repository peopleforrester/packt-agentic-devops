#!/usr/bin/env bash
# ABOUTME: Renders the router's hostname-to-NLB table (Caddyfile) from the live fleet plus
# ABOUTME: routes.static. Render only: it does not deploy or reload. This is the shared engine.
#
# To apply routes, use routes-reload.sh (renders via this script, then live-reloads the running
# router with no redeploy). To ship a new router image (Dockerfile / entrypoint / 404 assets),
# use router-image-deploy.sh. Splitting render from apply keeps a route change (data) off the
# redeploy path (code), which is the whole point of the volume + reload setup.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROUTER_DIR="${PROVISION_DIR}/router"
ROUTES_MAP="${ROUTER_DIR}/routes.map"
CADDYFILE="${ROUTER_DIR}/Caddyfile"
readonly ROUTER_DIR ROUTES_MAP CADDYFILE

ALLOW_EMPTY=""

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [--allow-empty]

Reads every known cluster's LoadBalancer hostname and writes routes.map and the rendered
Caddyfile. Does NOT deploy: apply with routes-reload.sh, or rebuild the image with
router-image-deploy.sh.

  --allow-empty   permit a table with zero routes (bootstrapping before any cluster exists;
                  every hostname then serves the 404 page, which is correct pre-fleet)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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
            # The port belongs in the map value. A placeholder upstream with no port does NOT
            # default to 80: Caddy dials port 0 and every request 502s with an i/o timeout.
            printf '\t\t%s.%s\t%s:80\n' "${name}" "${PACKT_DOMAIN}" "${host}" >> "${ROUTES_MAP}"
            total=$((total + 1))
        done < <(known_clusters "${account}")
    done < <(accounts_list)

    # Static routes for hosts the fleet driver does not manage (instructor standalone clusters).
    # Without this they would be silently dropped from the table on the next scale change, because
    # the table is rebuilt from the fleet inventory each time.
    local static="${ROUTER_DIR}/routes.static"
    if [[ -f "${static}" ]]; then
        local shost supstream n=0
        while read -r shost supstream; do
            [[ -n "${shost}" && "${shost}" != \#* ]] || continue
            printf '\t\t%s\t%s\n' "${shost}" "${supstream}" >> "${ROUTES_MAP}"
            total=$((total + 1)); n=$((n + 1))
        done < "${static}"
        [[ "${n}" -gt 0 ]] && log "  plus ${n} static route(s) from routes.static"
    fi

    log "routing table: ${total} clusters mapped, ${missing} omitted"
    # An empty table means every student gets a 404, so it is refused unless asked for explicitly.
    # The one legitimate case is bootstrapping the service before the first cluster exists.
    [[ "${total}" -gt 0 || -n "${ALLOW_EMPTY}" ]] \
        || die "no clusters have a LoadBalancer hostname; refusing to render an empty router"

    # Render the template. A cluster whose row is missing must 404 on a real page, never proxy to a
    # stale upstream, so the map's default stays empty rather than falling back to any cluster.
    python3 - <<PY
import pathlib
tmpl = pathlib.Path("${ROUTER_DIR}/Caddyfile.tmpl").read_text()
routes = pathlib.Path("${ROUTES_MAP}").read_text().rstrip("\n")
pathlib.Path("${CADDYFILE}").write_text(tmpl.replace("{{ROUTES}}", routes))
PY
    log "rendered ${CADDYFILE} (not applied; use routes-reload.sh)"
}

main
