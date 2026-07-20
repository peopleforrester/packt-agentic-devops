#!/usr/bin/env bash
# ABOUTME: Read-only progress detector for the workshop VTT. Reports which platform components are ACTUALLY
# ABOUTME: running on the cluster (namespaces with a ready pod, plus specific resource checks), not a guess.
# ABOUTME: Writes JSON nginx serves at /api/status; the Blueprint colors each component by real state.
set -uo pipefail

readonly SA=/var/run/secrets/kubernetes.io/serviceaccount
readonly OUT=/run/status/status.json
export HOME=/tmp

setup_kubeconfig() {
    kubectl config set-cluster this --server="https://kubernetes.default.svc" \
        --certificate-authority="${SA}/ca.crt" --embed-certs=true >/dev/null 2>&1
    kubectl config set-credentials me --token="$(cat "${SA}/token")" >/dev/null 2>&1
    kubectl config set-context this --cluster=this --user=me >/dev/null 2>&1
    kubectl config use-context this >/dev/null 2>&1
}

# Namespaces that have at least one Ready pod. A layer is only "up" if something in it is actually running,
# so a bare or half-built cluster does not light up green.
ready_namespaces() {
    kubectl get pods -A -o json 2>/dev/null | jq -r '
        [ .items[]
          | select( any(.status.conditions[]?; .type=="Ready" and .status=="True") )
          | .metadata.namespace ] | unique | .[]' 2>/dev/null
}

deploy_ready() { # ns name -> ready if readyReplicas >= 1
    [[ "$(kubectl -n "$1" get deploy "$2" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" =~ ^[1-9] ]]
}
ds_ready() { # ns name -> ready if numberReady >= 1
    [[ "$(kubectl -n "$1" get daemonset "$2" -o jsonpath='{.status.numberReady}' 2>/dev/null)" =~ ^[1-9] ]]
}
any_of() { [[ -n "$(kubectl get "$@" -o name 2>/dev/null | head -1)" ]]; }

detect() {
    local up=()
    # Namespace-scoped layers: up iff the namespace has a ready pod.
    local rns; rns="$(ready_namespaces)"
    for ns in cert-manager openbao external-secrets kyverno observability backstage keda \
              argo argo-events argo-rollouts gitea kgateway-system agentgateway kagent kserve llm-d; do
        grep -qx "${ns}" <<<"${rns}" && up+=("${ns}")
    done
    # kube-system holds unrelated pods, so check the specific controllers, not the namespace.
    deploy_ready kube-system aws-load-balancer-controller && up+=("alb")
    { ds_ready kube-system ebs-csi-node || deploy_ready kube-system ebs-csi-controller; } && up+=("ebs")
    # Resource-based signals.
    kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && up+=("gateway-api")
    any_of applicationsets.argoproj.io -A && up+=("applicationset")
    any_of inferenceservices.serving.kserve.io -A && up+=("inferenceservice")
    if kubectl get clusterpolicies.kyverno.io -o json 2>/dev/null \
        | jq -e '[.items[]? | (.spec.validationFailureAction // empty), (.spec.failureAction // empty), (.spec.rules[]?.validate?.failureAction // empty)] | any(. == "Enforce")' >/dev/null 2>&1; then
        up+=("kyverno-enforce")
    fi

    # Phase, for the stepper's position: the furthest layer that is up.
    local phase=0
    grep -qx argocd <<<"${rns}" && phase=1
    grep -qx observability <<<"${rns}" && phase=2
    grep -qx backstage <<<"${rns}" && phase=3
    { grep -qx kgateway-system <<<"${rns}" || grep -qx agentgateway <<<"${rns}"; } && phase=4
    grep -qx kagent <<<"${rns}" && phase=5
    { printf '%s\n' "${up[@]}" | grep -qx inferenceservice; } && phase=6
    { printf '%s\n' "${up[@]}" | grep -qx applicationset; } && phase=7
    { printf '%s\n' "${up[@]}" | grep -qx kyverno-enforce; } && phase=8
    grep -qx argocd <<<"${rns}" && up+=("argocd")

    # Emit {"phase":N,"up":[...]}
    local joined=""
    if ((${#up[@]})); then joined="$(printf '"%s",' "${up[@]}")"; joined="${joined%,}"; fi
    printf '{"phase":%s,"up":[%s]}\n' "${phase}" "${joined}"
}

main() {
    setup_kubeconfig
    mkdir -p "$(dirname "${OUT}")"
    while true; do
        detect > "${OUT}.tmp" 2>/dev/null && mv "${OUT}.tmp" "${OUT}" 2>/dev/null || true
        sleep 10
    done
}

main "$@"
