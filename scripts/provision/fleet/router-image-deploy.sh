#!/usr/bin/env bash
# ABOUTME: Build and deploy a NEW router image (railway up). Rare: only when the image itself
# ABOUTME: changes (Dockerfile, entrypoint.sh, srv/ 404 assets). Route changes use routes-reload.sh.
#
# The image bakes an EMPTY routing table (all 404) as the seed only. The live table lives on the
# /config volume and is owned by routes-reload.sh; entrypoint.sh copies this baked default onto the
# volume only when the volume is empty (first boot, or a wiped volume). So an image deploy never
# resets live routes: the volume persists and the new container keeps reading the volume's table.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ROUTER_DIR="${SCRIPT_DIR}/../router"
readonly ROUTER_SERVICE="packt-router"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "FATAL: $*"; exit 1; }

command -v railway >/dev/null 2>&1 || die "railway CLI not found"

# Bake an empty table (all 404) as the seed. Deliberately not the live fleet: the routing table is
# the volume's job, applied by routes-reload.sh, not baked into the image.
log "rendering an empty seed Caddyfile"
python3 - <<PY
import pathlib
tmpl = pathlib.Path("${ROUTER_DIR}/Caddyfile.tmpl").read_text()
pathlib.Path("${ROUTER_DIR}/Caddyfile").write_text(tmpl.replace("{{ROUTES}}", ""))
PY

log "deploying a new ${ROUTER_SERVICE} image (railway up)"
# --no-gitignore ships the rendered Caddyfile and srv/ assets, which are gitignored (generated).
( cd "${ROUTER_DIR}" && railway up --service "${ROUTER_SERVICE}" --ci --no-gitignore ) \
    || die "router image deploy failed"

log "router image deployed. Live routes are unchanged (the volume persists);"
log "run routes-reload.sh to (re)apply the routing table if needed."
