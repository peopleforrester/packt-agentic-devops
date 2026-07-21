#!/usr/bin/env bash
# ABOUTME: Grants the student terminal read-only AWS access to its own cluster via EKS Pod Identity, so
# ABOUTME: the AWS CLI works inside the VTT with no long-lived access key to mint, distribute, or revoke.
#
# Why Pod Identity rather than an IAM user plus an access key:
#   - Nothing static exists. There is no secret to lose, leak from the student's shell, or clean up at
#     teardown; deleting the cluster deletes the association.
#   - Provisioning becomes idempotent. AWS returns an access key's secret exactly once, so a key-based
#     script must either rotate on every run (churn, and it invalidates the key the running pod holds)
#     or persist the secret somewhere. Pod Identity has no such state: re-running this script converges.
#   - No IAM propagation wait. The agent vends short-lived credentials per pod, so there is no window
#     where a freshly minted key is not yet valid.
#   - It scales as one role plus one association per cluster instead of 250 users and 250 keys.
# The cluster already runs the eks-pod-identity-agent addon, and terraform already uses this exact
# mechanism for the AWS Load Balancer Controller and the EBS CSI driver.
#
# Scope is deliberately tiny. The fleet puts ~50 student clusters in ONE account, so a broad
# ReadOnlyAccess would let every student enumerate every other student's resources. This grants only
# "describe my own cluster" plus the ListClusters call the CLI needs to be usable.
set -euo pipefail

readonly NS="workshop"
readonly SA="web-terminal"
readonly POLICY_NAME="packt-student-readonly"

: "${KUBECONFIG:?set KUBECONFIG to the target cluster kubeconfig}"
: "${AWS_PROFILE:?set AWS_PROFILE for the account that owns the cluster}"
export KUBECONFIG AWS_PROFILE
REGION="${AWS_REGION:-us-west-2}"

usage() { echo "Usage: KUBECONFIG=<f> AWS_PROFILE=<p> $0 [cluster-name]" >&2; exit 2; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

CLUSTER="${1:-$(kubectl config current-context | sed 's|.*/||')}"
[[ -n "${CLUSTER}" ]] || usage
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ROLE="packt-student-${CLUSTER}"
ROLE="${ROLE:0:64}"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

printf 'cluster=%s account=%s role=%s\n' "${CLUSTER}" "${ACCOUNT}" "${ROLE}" >&2

# The Pod Identity agent must be present or the pod never receives credentials. Fail loudly here rather
# than shipping a terminal whose `aws` silently has no identity.
if ! aws eks describe-addon --cluster-name "${CLUSTER}" --region "${REGION}" \
        --addon-name eks-pod-identity-agent >/dev/null 2>&1; then
    printf 'REFUSE: the eks-pod-identity-agent addon is not installed on %s\n' "${CLUSTER}" >&2
    exit 1
fi

# Trust the EKS Pod Identity service. Not a user, and not an OIDC provider: the cluster sets
# enable_irsa = false, so no OIDC provider exists to trust.
read -r -d '' TRUST <<'JSON' || true
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"Service":"pods.eks.amazonaws.com"},
 "Action":["sts:AssumeRole","sts:TagSession"]}]}
JSON

if aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "${ROLE}" --policy-document "${TRUST}" >/dev/null
    printf '  role exists, trust policy refreshed\n' >&2
else
    aws iam create-role --role-name "${ROLE}" --assume-role-policy-document "${TRUST}" \
        --description "Read-only access to ${CLUSTER} for the workshop terminal" \
        --tags Key=Workshop,Value=packt Key=Cluster,Value="${CLUSTER}" >/dev/null
    printf '  role created\n' >&2
fi

read -r -d '' POLICY <<JSON || true
{"Version":"2012-10-17","Statement":[
 {"Sid":"DescribeOwnCluster","Effect":"Allow","Action":["eks:DescribeCluster"],
  "Resource":"arn:aws:eks:${REGION}:${ACCOUNT}:cluster/${CLUSTER}"},
 {"Sid":"ListClusters","Effect":"Allow","Action":["eks:ListClusters"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name "${ROLE}" \
    --policy-name "${POLICY_NAME}" --policy-document "${POLICY}"
printf '  scoped read-only policy attached\n' >&2

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Converge the association: reuse it when it already points at this role, repoint it when it does not.
EXISTING="$(aws eks list-pod-identity-associations --cluster-name "${CLUSTER}" --region "${REGION}" \
    --namespace "${NS}" --service-account "${SA}" \
    --query 'associations[0].associationId' --output text 2>/dev/null || true)"

if [[ -n "${EXISTING}" && "${EXISTING}" != "None" ]]; then
    CURRENT="$(aws eks describe-pod-identity-association --cluster-name "${CLUSTER}" --region "${REGION}" \
        --association-id "${EXISTING}" --query 'association.roleArn' --output text 2>/dev/null || true)"
    if [[ "${CURRENT}" == "${ROLE_ARN}" ]]; then
        printf '  association already correct (%s)\n' "${EXISTING}" >&2
    else
        aws eks delete-pod-identity-association --cluster-name "${CLUSTER}" --region "${REGION}" \
            --association-id "${EXISTING}" >/dev/null
        aws eks create-pod-identity-association --cluster-name "${CLUSTER}" --region "${REGION}" \
            --namespace "${NS}" --service-account "${SA}" --role-arn "${ROLE_ARN}" >/dev/null
        printf '  association repointed to %s\n' "${ROLE}" >&2
    fi
else
    aws eks create-pod-identity-association --cluster-name "${CLUSTER}" --region "${REGION}" \
        --namespace "${NS}" --service-account "${SA}" --role-arn "${ROLE_ARN}" >/dev/null
    printf '  association created\n' >&2
fi

# A leftover static-key secret would win over Pod Identity in the CLI's credential chain. Remove it so a
# cluster provisioned by the older key-based version of this script converges to the new mechanism.
kubectl -n "${NS}" delete secret student-aws-creds --ignore-not-found >/dev/null 2>&1 || true

# Pod Identity env vars are injected at pod admission, so the terminal has to restart to receive them.
kubectl -n "${NS}" rollout restart deployment/web-terminal >/dev/null
kubectl -n "${NS}" rollout status deployment/web-terminal --timeout=300s >&2

# Verify from inside the pod. Provisioning that reports success without proving it is not verification,
# and at fleet scale an unverified step is 250 unverified steps.
POD="$(kubectl -n "${NS}" get pod -l app.kubernetes.io/name=web-terminal -o name | head -1)"
printf '  verifying the AWS identity from inside the terminal...\n' >&2
if ! kubectl -n "${NS}" exec "${POD}" -c ttyd -- bash -lc '
      for i in $(seq 1 10); do
        if aws sts get-caller-identity --query Arn --output text 2>/dev/null; then exit 0; fi
        sleep 3
      done
      echo "no AWS identity after 30s" >&2; exit 1' >&2; then
    printf 'FAILED: the terminal has no AWS identity\n' >&2
    exit 1
fi
printf 'done: student AWS access is live via Pod Identity, no static keys\n' >&2
