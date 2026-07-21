#!/usr/bin/env bash
# ABOUTME: Mints a read-only, single-cluster IAM user for one student and writes it into the cluster as
# ABOUTME: the student-aws-creds secret, which the VTT turns into the default AWS profile on next start.
#
# Scope is deliberately tiny. The fleet puts ~50 student clusters in ONE account, so a broad ReadOnlyAccess
# would let every student enumerate every other student's resources. This grants only "describe my own
# cluster" plus the ListClusters call the CLI needs to be usable, so `aws sts get-caller-identity` and
# `aws eks describe-cluster` work and nothing else does.
set -euo pipefail

readonly NS="workshop"

: "${KUBECONFIG:?set KUBECONFIG to the target cluster kubeconfig}"
: "${AWS_PROFILE:?set AWS_PROFILE for the account that owns the cluster}"
export KUBECONFIG AWS_PROFILE
REGION="${AWS_REGION:-us-west-2}"

usage() { echo "Usage: KUBECONFIG=<f> AWS_PROFILE=<p> $0 [cluster-name]" >&2; exit 2; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

CLUSTER="${1:-$(kubectl config current-context | sed 's|.*/||')}"
[[ -n "${CLUSTER}" ]] || usage
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
USER_NAME="packt-${CLUSTER}"
USER_NAME="${USER_NAME:0:64}"
POLICY_NAME="packt-student-readonly"

printf 'cluster=%s account=%s iam-user=%s\n' "${CLUSTER}" "${ACCOUNT}" "${USER_NAME}" >&2

# Idempotent create.
if ! aws iam get-user --user-name "${USER_NAME}" >/dev/null 2>&1; then
    aws iam create-user --user-name "${USER_NAME}" \
        --tags Key=Workshop,Value=packt Key=Cluster,Value="${CLUSTER}" >/dev/null
    printf '  created IAM user\n' >&2
else
    printf '  IAM user already exists\n' >&2
fi

read -r -d '' POLICY <<JSON || true
{"Version":"2012-10-17","Statement":[
 {"Sid":"DescribeOwnCluster","Effect":"Allow","Action":["eks:DescribeCluster"],
  "Resource":"arn:aws:eks:${REGION}:${ACCOUNT}:cluster/${CLUSTER}"},
 {"Sid":"ListClusters","Effect":"Allow","Action":["eks:ListClusters"],"Resource":"*"}]}
JSON
aws iam put-user-policy --user-name "${USER_NAME}" \
    --policy-name "${POLICY_NAME}" --policy-document "${POLICY}"
printf '  scoped read-only policy attached\n' >&2

# AWS returns a secret key exactly once, so an existing key is useless to us: rotate to get a usable pair.
for k in $(aws iam list-access-keys --user-name "${USER_NAME}" \
        --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
    aws iam delete-access-key --user-name "${USER_NAME}" --access-key-id "${k}" >/dev/null 2>&1 || true
    printf '  rotated out old key %s\n' "${k}" >&2
done
KEY_JSON="$(aws iam create-access-key --user-name "${USER_NAME}" --output json)"
AK="$(printf '%s' "${KEY_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')"
SK="$(printf '%s' "${KEY_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["AccessKey"]["SecretAccessKey"])')"
[[ -n "${AK}" && -n "${SK}" ]] || { printf 'failed to mint an access key\n' >&2; exit 1; }

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${NS}" create secret generic student-aws-creds \
    --from-literal=AWS_ACCESS_KEY_ID="${AK}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${SK}" \
    --from-literal=AWS_DEFAULT_REGION="${REGION}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
printf '  wrote student-aws-creds into %s\n' "${NS}" >&2

# The entrypoint writes ~/.aws/credentials from these at start, so the pod has to restart to pick them up.
kubectl -n "${NS}" rollout restart deployment/web-terminal >/dev/null
kubectl -n "${NS}" rollout status deployment/web-terminal --timeout=300s >&2
printf 'done: the student AWS profile is live\n' >&2
