#!/usr/bin/env bash
# ABOUTME: Read-only phase detector for the workshop VTT. Derives the current build phase from what is
# ABOUTME: actually deployed on the cluster and writes it to a JSON file nginx serves at /api/status.
set -uo pipefail

readonly SA=/var/run/secrets/kubernetes.io/serviceaccount
readonly OUT=/run/status/status.json
export HOME=/tmp

# kubectl talks to THIS cluster via the pod ServiceAccount (read-all, scoped by the console-terminal role).
setup_kubeconfig() {
    kubectl config set-cluster this --server="https://kubernetes.default.svc" \
        --certificate-authority="${SA}/ca.crt" --embed-certs=true >/dev/null 2>&1
    kubectl config set-credentials me --token="$(cat "${SA}/token")" >/dev/null 2>&1
    kubectl config set-context this --cluster=this --user=me >/dev/null 2>&1
    kubectl config use-context this >/dev/null 2>&1
}

has_ns() { kubectl get namespace "$1" >/dev/null 2>&1; }
any_of() { [[ -n "$(kubectl get "$@" -o name 2>/dev/null | head -1)" ]]; }

# Highest phase whose signature resource is present. A later signature implies the earlier phases ran, so
# checking from the top down and returning the first match is enough for a progress indicator.
detect_phase() {
    if kubectl get clusterpolicies.kyverno.io -o json 2>/dev/null \
        | jq -e '[.items[]? | (.spec.validationFailureAction // empty), (.spec.failureAction // empty), (.spec.rules[]?.validate?.failureAction // empty)] | any(. == "Enforce")' >/dev/null 2>&1; then
        echo 8; return
    fi
    if any_of applicationsets.argoproj.io -A; then echo 7; return; fi
    if any_of inferenceservices.serving.kserve.io -A; then echo 6; return; fi
    if any_of agents.kagent.dev -A; then echo 5; return; fi
    if has_ns agentgateway || has_ns kgateway-system; then echo 4; return; fi
    if has_ns backstage; then echo 3; return; fi
    if has_ns observability; then echo 2; return; fi
    if has_ns argocd; then echo 1; return; fi
    echo 0
}

main() {
    setup_kubeconfig
    mkdir -p "$(dirname "${OUT}")"
    while true; do
        p="$(detect_phase)"
        printf '{"phase":%s}\n' "${p:-0}" > "${OUT}.tmp" 2>/dev/null && mv "${OUT}.tmp" "${OUT}" 2>/dev/null || true
        sleep 10
    done
}

main "$@"
