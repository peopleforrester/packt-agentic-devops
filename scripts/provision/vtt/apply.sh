#!/usr/bin/env bash
# ABOUTME: Applies the workshop VTT (two-pane console) to a cluster: generates the lab-page and nginx
# ABOUTME: ConfigMaps from web/, applies the Deployment/Service/RBAC, and rolls the pod to pick them up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly NS="workshop"

# Cluster context safety: this box is shared. Require an explicit KUBECONFIG and verify the current
# context before any mutation. Never operate against a cluster you did not intend to.
: "${KUBECONFIG:?set KUBECONFIG to a dedicated kubeconfig (e.g. /tmp/adwc-dev.kubeconfig)}"
: "${AWS_PROFILE:?set AWS_PROFILE for the account that owns the cluster}"
export KUBECONFIG AWS_PROFILE

usage() {
    cat >&2 <<USAGE
Usage: KUBECONFIG=<file> AWS_PROFILE=<profile> [EXPECT_CONTEXT=<substr>] $0

Applies the VTT into the '${NS}' namespace of the cluster the KUBECONFIG points at.
EXPECT_CONTEXT, if set, must be a substring of the current context or the script aborts.
USAGE
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 2; }

ctx="$(kubectl config current-context)"
printf 'Current context: %s\n' "${ctx}" >&2
if [[ -n "${EXPECT_CONTEXT:-}" && "${ctx}" != *"${EXPECT_CONTEXT}"* ]]; then
    printf 'REFUSE: current context %q does not contain EXPECT_CONTEXT %q\n' "${ctx}" "${EXPECT_CONTEXT}" >&2
    exit 1
fi

apply_configmap_from_file() {
    # $1 = configmap name, $2 = key=path
    local name="$1" keypath="$2"
    printf 'ConfigMap %s <- %s\n' "${name}" "${keypath}" >&2
    kubectl create configmap "${name}" -n "${NS}" \
        --from-file="${keypath}" \
        --dry-run=client -o yaml | kubectl apply -f -
}

main() {
    printf 'Applying VTT manifest...\n' >&2
    kubectl apply -f "${SCRIPT_DIR}/web-terminal.yaml"

    # console-src carries every static page the nginx serves (lab + blueprint).
    printf 'ConfigMap console-src <- web/lab.html, web/diagram.html\n' >&2
    kubectl create configmap console-src -n "${NS}" \
        --from-file="lab.html=${SCRIPT_DIR}/web/lab.html" \
        --from-file="diagram.html=${SCRIPT_DIR}/web/diagram.html" \
        --dry-run=client -o yaml | kubectl apply -f -
    apply_configmap_from_file console-conf "default.conf=${SCRIPT_DIR}/web/console.conf"

    # ConfigMap volume updates do not trigger an nginx reload on their own; roll the pod so the new
    # lab page and config are served immediately.
    printf 'Rolling the deployment to pick up the ConfigMaps...\n' >&2
    kubectl rollout restart deployment/web-terminal -n "${NS}"
    kubectl rollout status deployment/web-terminal -n "${NS}" --timeout=180s

    local host
    host="$(kubectl get svc web-terminal -n "${NS}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [[ -n "${host}" ]]; then
        printf '\nVTT is live: http://%s/\n' "${host}" >&2
    else
        printf '\nVTT applied. LoadBalancer hostname not assigned yet; check:\n  kubectl get svc web-terminal -n %s -w\n' "${NS}" >&2
    fi
}

main "$@"
