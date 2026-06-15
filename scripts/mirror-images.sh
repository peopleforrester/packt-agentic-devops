#!/usr/bin/env bash
# ABOUTME: Re-hosts every image in components.yaml under a GHCR namespace so no
# ABOUTME: manifest references docker.io and 300 clusters avoid Docker Hub limits.
set -euo pipefail

# Phase 6 deliverable. Not yet implemented. This skeleton lists what the real
# script must do so the contract is visible now.
#
# Steps to implement:
#   - read every image referenced by components.yaml and the vendored charts
#   - pull each, retag under the workshop GHCR namespace, and push
#   - emit a mapping the manifests use so no manifest references docker.io
#   - support a dry-run mode that lists actions without pushing
#
# Exit nonzero on any failure.

echo "mirror-images.sh is a Phase 6 scaffold and is not yet implemented" >&2
exit 1
