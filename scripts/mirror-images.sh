#!/usr/bin/env bash
# ABOUTME: Re-hosts every image in components.yaml under a GHCR namespace so no
# ABOUTME: manifest references docker.io and 300 clusters avoid Docker Hub limits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR REPO_ROOT
readonly COMPONENTS="${REPO_ROOT}/components.yaml"
readonly MAPPING="${REPO_ROOT}/image-map.tsv"

DRY_RUN=0
GHCR_ORG="${GHCR_ORG:-}"

usage() {
    cat >&2 <<EOF
Usage: GHCR_ORG=<org> ${0##*/} [--dry-run]

Renders every Helm chart in components.yaml and scans the platform manifests for
image references, then copies each non-GHCR image to ghcr.io/\${GHCR_ORG}/<name>:<tag>.
Writes a source->mirror mapping to image-map.tsv.

  --dry-run   List the copies that would happen, push nothing.

Requires: helm, crane, python3. GHCR_ORG must be set.
EOF
    exit 2
}

log() { printf '%s\n' "$*" >&2; }

require_tools() {
    local missing=0 t
    for t in helm crane python3; do
        command -v "${t}" >/dev/null 2>&1 || { log "missing required tool: ${t}"; missing=1; }
    done
    [[ "${missing}" -eq 0 ]] || exit 1
}

# Print "repo<TAB>chart<TAB>version<TAB>install_method" for each helm/helm-oci component.
list_helm_charts() {
    python3 - "${COMPONENTS}" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for c in doc.get("components", []):
    m = c.get("install_method", "")
    if m in ("helm", "helm-oci") and c.get("chart_repo") and c.get("chart_name"):
        print("\t".join([c["chart_repo"], c["chart_name"],
                         str(c.get("chart_version") or ""), m]))
PY
}

# Render one chart and print the images it references.
images_from_chart() {
    local repo="$1" chart="$2" version="$3" method="$4"
    local args=(template _mirror --version "${version}")
    if [[ "${method}" == "helm-oci" ]]; then
        # OCI: strip a trailing /charts-style path is not needed; helm takes repo/chart.
        args+=("${repo}/${chart}")
    else
        args+=("${chart}" --repo "${repo}")
    fi
    # A chart that will not render is a hard error: we cannot mirror unknown images.
    if ! helm "${args[@]}" 2>/dev/null | grep -oE 'image:[[:space:]]*"?[^"[:space:]]+' \
        | sed -E 's/image:[[:space:]]*"?//'; then
        log "ERROR: failed to render chart ${chart} (${repo} ${version})"
        return 1
    fi
}

# Scan raw platform manifests for image references (vLLM, LLM Guard, OpenBao seed).
images_from_manifests() {
    grep -rhoE 'image:[[:space:]]*"?[^"[:space:]]+' "${REPO_ROOT}/platform" 2>/dev/null \
        | sed -E 's/image:[[:space:]]*"?//' | grep -vE 'REPLACE_' || true
}

# Mirror one image. Echoes the mapping line.
mirror_one() {
    local src="$1"
    # Skip images already in our GHCR namespace.
    [[ "${src}" == ghcr.io/"${GHCR_ORG}"/* ]] && return 0
    local name="${src##*/}"          # repo:tag
    local dst="ghcr.io/${GHCR_ORG}/${name}"
    printf '%s\t%s\n' "${src}" "${dst}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "  DRY-RUN copy ${src} -> ${dst}"
    else
        crane copy "${src}" "${dst}" >&2
    fi
}

main() {
    [[ $# -gt 0 && "$1" == "--dry-run" ]] && DRY_RUN=1
    [[ -n "${GHCR_ORG}" ]] || { log "GHCR_ORG is not set"; usage; }
    require_tools

    log "Collecting images from charts and manifests..."
    local tmp; tmp="$(mktemp)"
    trap 'rm -f "${tmp}"' EXIT

    images_from_manifests >>"${tmp}"
    local repo chart version method
    while IFS=$'\t' read -r repo chart version method; do
        [[ -n "${chart}" ]] || continue
        log "  rendering ${chart} ${version}"
        images_from_chart "${repo}" "${chart}" "${version}" "${method}" >>"${tmp}"
    done < <(list_helm_charts)

    # Dedupe and mirror with progress.
    local images; mapfile -t images < <(sort -u "${tmp}" | grep -vE '^\s*$')
    local total="${#images[@]}" i=0 src
    log "Mirroring ${total} unique images to ghcr.io/${GHCR_ORG} (dry-run=${DRY_RUN})"
    : >"${MAPPING}"
    for src in "${images[@]}"; do
        i=$((i + 1))
        log "[${i}/${total}] ${src}"
        mirror_one "${src}" >>"${MAPPING}"
    done
    log "Done. Mapping written to ${MAPPING}"
}

main "$@"
