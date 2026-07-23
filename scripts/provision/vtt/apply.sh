#!/usr/bin/env bash
# ABOUTME: Applies the workshop VTT (two-pane console) to a cluster: generates the lab-page and nginx
# ABOUTME: ConfigMaps from web/, applies the Deployment/Service/RBAC, and rolls the pod to pick them up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly NS="workshop"
# Pinned to match platform/1-foundation/aws-load-balancer-controller/application.yaml so provisioning and
# the student's phase-1 sync install the identical chart version.
readonly LBC_CHART_VERSION="3.4.0"
# Matches platform/1-foundation/gitea/application.yaml so provisioning and phase 3 install the same chart.
readonly GITEA_CHART_VERSION="12.6.0"

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

# The AWS Load Balancer Controller, installed at provisioning because the VTT Service is an
# internet-facing ip-target NLB and nothing else can create one. Without this the Service falls back to a
# Classic ELB (deprecated, and capped at 20 per region against a fleet need of 50). Terraform already
# creates the Pod Identity association for kube-system/aws-load-balancer-controller, so no keys are
# needed. Idempotent: the student's phase-1 App-of-Apps re-applies the same chart and adopts it.
bootstrap_lb_controller() {
    local cluster region vpc
    cluster="$(kubectl config current-context | sed 's|.*/||')"
    region="${AWS_REGION:-us-west-2}"
    vpc="$(aws eks describe-cluster --name "${cluster}" --region "${region}" \
        --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null)"
    [[ -n "${vpc}" && "${vpc}" != None ]] || { printf 'could not resolve VPC for %s\n' "${cluster}" >&2; return 1; }

    printf 'Installing AWS Load Balancer Controller (cluster=%s vpc=%s)...\n' "${cluster}" "${vpc}" >&2
    helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
    helm repo update eks >/dev/null 2>&1 || true
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --namespace kube-system --version "${LBC_CHART_VERSION}" \
        --set "clusterName=${cluster}" \
        --set "region=${region}" \
        --set "vpcId=${vpc}" \
        --set serviceAccount.create=true \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set enableServiceMutatorWebhook=false \
        --wait --timeout 5m >&2
}

# In-cluster Gitea, installed at provisioning and seeded with the platform manifests, so ArgoCD sources
# GitOps from inside the cluster. This is what makes a student cluster self-contained: no GitHub in the
# reconcile loop (250 clusters polling one repo through 5 NAT IPs gets throttled), and the student can
# actually push, because they own this Git host. Same chart/version/values as
# platform/1-foundation/gitea/application.yaml, so the student's phase-3 sync adopts this release.
bootstrap_gitea() {
    printf 'Installing in-cluster Gitea...\n' >&2
    helm repo add gitea https://dl.gitea.com/charts/ >/dev/null 2>&1 || true
    helm repo update gitea >/dev/null 2>&1 || true
    helm upgrade --install gitea gitea/gitea \
        --namespace gitea --create-namespace \
        --version "${GITEA_CHART_VERSION}" \
        -f "${SCRIPT_DIR}/gitea/values.yaml" \
        --wait --timeout 10m >&2

    # Hand the seed job the SAME credentials the chart just used, read straight out of values.yaml.
    # Keeping a second copy in the Job manifest drifted once and cost a debug cycle (401 on every call).
    local gu gp
    gu="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['gitea']['admin']['username'])" "${SCRIPT_DIR}/gitea/values.yaml")"
    gp="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['gitea']['admin']['password'])" "${SCRIPT_DIR}/gitea/values.yaml")"
    [[ -n "${gu}" && -n "${gp}" ]] || { printf 'could not read gitea admin creds from values.yaml\n' >&2; return 1; }
    kubectl -n gitea create secret generic gitea-seed-creds \
        --from-literal=username="${gu}" --from-literal=password="${gp}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    # Per-cluster facts the seed job substitutes into the manifests before pushing to Gitea. The
    # AWS Load Balancer Controller Application ships clusterName and vpcId as placeholders because
    # neither can be hardcoded (every cluster is a different EKS name in a different VPC), and
    # leaving vpcId to IMDS makes the controller crash-loop on a metadata timeout under prefix
    # delegation. Resolved here from the AWS API, the single source of truth.
    local cluster region vpc
    cluster="$(kubectl config current-context | sed 's|.*/||')"
    region="${AWS_REGION:-us-west-2}"
    vpc="$(aws eks describe-cluster --name "${cluster}" --region "${region}" \
        --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null)"
    [[ -n "${vpc}" && "${vpc}" != None ]] \
        || { printf 'could not resolve VPC for %s; cannot seed cluster facts\n' "${cluster}" >&2; return 1; }
    printf 'Recording cluster facts for the seed job (cluster=%s vpc=%s)\n' "${cluster}" "${vpc}" >&2
    kubectl -n gitea create configmap platform-cluster-facts \
        --from-literal=cluster_name="${cluster}" --from-literal=vpc_id="${vpc}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    printf 'Seeding Gitea with the platform manifests...\n' >&2
    kubectl -n gitea delete job gitea-seed-platform --ignore-not-found >/dev/null 2>&1 || true
    kubectl apply -f "${SCRIPT_DIR}/gitea/seed-platform-job.yaml" >&2
    if ! kubectl -n gitea wait --for=condition=complete job/gitea-seed-platform --timeout=10m >&2; then
        printf 'Gitea seed job did not complete. Logs:\n' >&2
        kubectl -n gitea logs job/gitea-seed-platform --tail=40 >&2 || true
        return 1
    fi
    kubectl -n gitea logs job/gitea-seed-platform --tail=6 >&2 || true
}

main() {
    bootstrap_lb_controller

    # The default gp3 StorageClass, applied here rather than waiting for the student's phase-1 bootstrap.
    # EKS ships no default StorageClass since 1.30, and the VTT's claude-home PVC is created at
    # provisioning time, so without this the PVC (and the pod) hang Pending on a fresh cluster. Same file
    # the platform bootstrap uses, so re-applying it in phase 1 is a no-op.
    printf 'Applying the default gp3 StorageClass...\n' >&2
    kubectl apply -f "${SCRIPT_DIR}/../../../platform/0-bootstrap/gp3-storageclass.yaml"

    bootstrap_gitea

    # Hand the terminal the in-cluster Git remote (same creds the chart used) so the student can push and
    # watch ArgoCD apply their own commit. Without this their clone still points at the public GitHub
    # repo, which they cannot write to, and the GitOps loop never closes for them.
    local gu2 gp2
    gu2="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['gitea']['admin']['username'])" "${SCRIPT_DIR}/gitea/values.yaml")"
    gp2="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['gitea']['admin']['password'])" "${SCRIPT_DIR}/gitea/values.yaml")"
    kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl -n "${NS}" create secret generic student-git-creds \
        --from-literal=GITEA_REPO_URL="http://gitea-http.gitea.svc:3000/platform/packt-agentic-devops.git" \
        --from-literal=GITEA_USER="${gu2}" \
        --from-literal=GITEA_PASSWORD="${gp2}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    printf 'Applying VTT manifest...\n' >&2
    kubectl apply -f "${SCRIPT_DIR}/web-terminal.yaml"

    # console-src carries every static page the nginx serves (lab + blueprint).
    printf 'ConfigMap console-src <- web/lab.html, web/diagram.html\n' >&2
    kubectl create configmap console-src -n "${NS}" \
        --from-file="lab.html=${SCRIPT_DIR}/web/lab.html" \
        --from-file="diagram.html=${SCRIPT_DIR}/web/diagram.html" \
        --from-file="links.html=${SCRIPT_DIR}/web/links.html" \
        --dry-run=client -o yaml | kubectl apply -f -
    apply_configmap_from_file console-conf "default.conf=${SCRIPT_DIR}/web/console.conf"
    apply_configmap_from_file status-src "status-loop.sh=${SCRIPT_DIR}/web/status-loop.sh"

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
