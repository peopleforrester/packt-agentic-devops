#!/usr/bin/env bash
# ABOUTME: Update the router's routing table with a LIVE RELOAD and no redeploy. Renders the
# ABOUTME: Caddyfile, writes it to the router's /config volume, and reloads Caddy in place.
#
# This is the routine path for route changes (a scale change, an instructor cluster coming or
# going). It swaps config in seconds with zero downtime and no image rebuild. Use routes.sh
# instead only for the initial deploy or when the Dockerfile / entrypoint / srv assets change,
# because those need a new image (railway up). The two share the same renderer.
#
# How it works: the router runs Caddy from /config/Caddyfile on a Railway volume, with the
# admin API enabled (Caddyfile global block). `caddy reload` hot-swaps the config through that
# admin API. If the new config is invalid Caddy keeps the old one running, so a bad table
# cannot take the router down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ROUTER_DIR="${SCRIPT_DIR}/../router"
readonly CADDYFILE="${ROUTER_DIR}/Caddyfile"
readonly ROUTER_SERVICE="packt-router"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "FATAL: $*"; exit 1; }

# 1. Render the Caddyfile from the live fleet + routes.static, without deploying. Pass through
#    any flags (e.g. --allow-empty) to the renderer.
"${SCRIPT_DIR}/routes.sh" --no-deploy "$@"

command -v railway >/dev/null 2>&1 || die "railway CLI not found"
[[ -f "${CADDYFILE}" ]] || die "no rendered Caddyfile at ${CADDYFILE}"

# 2. Push the rendered Caddyfile onto the volume the running container reads, then reload. Both
#    run inside the container over `railway ssh`; the admin API is bound to localhost there.
log "writing the rendered Caddyfile to the ${ROUTER_SERVICE} /config volume"
railway ssh -s "${ROUTER_SERVICE}" -- sh -c 'cat > /config/Caddyfile' < "${CADDYFILE}" \
    || die "failed to write /config/Caddyfile over railway ssh"

log "reloading Caddy in place (no redeploy)"
railway ssh -s "${ROUTER_SERVICE}" -- caddy reload --config /config/Caddyfile --adapter caddyfile \
    || die "caddy reload failed (the previous config is still serving)"

log "router reloaded with the new routing table, no redeploy"
