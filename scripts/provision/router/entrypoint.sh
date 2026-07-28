#!/bin/sh
# ABOUTME: Router entrypoint. Serves the Caddyfile from a Railway volume so routes can be
# ABOUTME: changed with a live reload (no redeploy). Seeds the volume from the baked default.
set -e

# The volume mounts at /config. On first boot it is empty, so seed it from the image's baked
# Caddyfile (the empty seed router-image-deploy.sh bakes). After that the volume copy is
# authoritative: routes-reload.sh writes a new one and reloads Caddy in place.
if [ ! -f /config/Caddyfile ]; then
    echo "seeding /config/Caddyfile from the baked default"
    cp /etc/caddy/Caddyfile /config/Caddyfile
fi

# Run from the volume copy. The admin API (enabled in the Caddyfile global block) is what
# 'caddy reload' uses to hot-swap config without restarting the process, which is the whole
# point: a route change is an upload plus a reload, never a rebuild-and-redeploy.
exec caddy run --config /config/Caddyfile --adapter caddyfile
