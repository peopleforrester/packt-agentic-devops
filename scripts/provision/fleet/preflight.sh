#!/usr/bin/env bash
# ABOUTME: L0 gate. Proves every fleet account is reachable, is the account we think it is, and has
# ABOUTME: the quota headroom for the stage being attempted. Exits non-zero on any gap.
#
# Run before every stage, not just the first. Quotas are per-account and a stage that fits at 1
# cluster can be rejected at 50, which is exactly the failure this catches before the spend starts.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Verified against the live APIs on 2026-07-21. A profile that resolves to a different account than
# the one recorded here is a misconfigured profile, and provisioning into it would be unrecoverable
# without a full sweep. This map is why the check is an equality test and not just "did it resolve".
declare -A EXPECTED_ACCOUNT=(
    [accen-dev]=515966504359
    [aws1-student31]=948731545609
    [aws1-student32]=891472436879
    [aws1-student33]=250699659274
    [aws1-student34]=783241407859
)

# Service quota codes, us-west-2.
readonly Q_VCPU="L-1216C47A"      # Running On-Demand Standard vCPUs
readonly Q_NLB="L-69A177A2"       # Network Load Balancers per Region
readonly Q_CLB="L-E9E9831D"       # Classic Load Balancers per Region
readonly Q_EKS="L-1194D53C"       # EKS clusters per Region
readonly Q_VPC="L-F678F1CE"       # VPCs per Region
readonly Q_EIP="L-0263D0A3"       # Elastic IPs

readonly VCPU_PER_CLUSTER=8       # one t3.2xlarge

JSON_OUT=""
STAGE="s1"
FAILS=0

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [s1|s2|s3] [--json]

  s1   1 cluster per account          (5 total)
  s2   50 in accen-dev, 1 elsewhere   (54 total)
  s3   50 per account                 (250 total)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        s1|s2|s3) STAGE="$1"; shift ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help) usage ;;
        *) printf 'unknown arg: %s\n' "$1" >&2; usage ;;
    esac
done

fail() { printf '  FAIL  %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
pass() { printf '  ok    %s\n' "$*" >&2; }

# Clusters this stage puts in a given account.
clusters_for() {
    local account="$1"
    case "${STAGE}" in
        s1) printf '1' ;;
        s2) [[ "${account}" == "accen-dev" ]] && printf '50' || printf '1' ;;
        s3) printf '%s' "${PACKT_BLOCK}" ;;
    esac
}

quota_value() {
    local account="$1" code="$2"
    AWS_PROFILE="${account}" aws service-quotas get-service-quota \
        --service-code "$3" --quota-code "${code}" --region "${PACKT_REGION}" \
        --query 'Quota.Value' --output text 2>/dev/null || printf 'unknown'
}

check_quota() {
    local account="$1" label="$2" code="$3" service="$4" needed="$5" have
    have="$(quota_value "${account}" "${code}" "${service}")"
    if [[ "${have}" == "unknown" ]]; then
        fail "${account}: could not read quota ${label} (${code})"
        return
    fi
    # Quota values come back as floats ("800.0").
    if awk -v h="${have}" -v n="${needed}" 'BEGIN{exit !(h+0 >= n+0)}'; then
        pass "${account}: ${label} ${have%.*} >= ${needed}"
    else
        fail "${account}: ${label} is ${have%.*}, need ${needed}"
    fi
}

check_tools() {
    local t missing=0
    for t in terraform kubectl aws jq curl helm python3 openssl; do
        command -v "${t}" >/dev/null 2>&1 || { fail "missing tool: ${t}"; missing=1; }
    done
    [[ "${missing}" -eq 1 ]] || pass "local tools present"
}

check_account() {
    local account="$1" n resolved expected
    n="$(clusters_for "${account}")"
    printf '\n[%s] stage=%s clusters=%s\n' "${account}" "${STAGE}" "${n}" >&2

    resolved="$(AWS_PROFILE="${account}" aws sts get-caller-identity \
        --query Account --output text 2>/dev/null || true)"
    expected="${EXPECTED_ACCOUNT[${account}]:-}"
    if [[ -z "${resolved}" ]]; then
        fail "${account}: credentials do not resolve"
        return
    fi
    if [[ -n "${expected}" && "${resolved}" != "${expected}" ]]; then
        fail "${account}: resolves to ${resolved}, expected ${expected}"
        return
    fi
    pass "${account}: identity ${resolved}"

    # The one cluster in these accounts that is not ours. If it ever appears inside the fleet's own
    # name range something is very wrong; the driver refuses it by name, and so does this gate.
    if AWS_PROFILE="${account}" aws eks describe-cluster --name adwc-dev \
            --region "${PACKT_REGION}" >/dev/null 2>&1; then
        pass "${account}: adwc-dev present and out of scope (driver refuses it by name)"
    fi

    check_quota "${account}" "vCPU"     "${Q_VCPU}" ec2   "$((n * VCPU_PER_CLUSTER))"
    check_quota "${account}" "NLB"      "${Q_NLB}"  elasticloadbalancing "${n}"
    check_quota "${account}" "EKS"      "${Q_EKS}"  eks   "${n}"
    check_quota "${account}" "VPC"      "${Q_VPC}"  vpc   1
    check_quota "${account}" "EIP"      "${Q_EIP}"  ec2   1

    # Classic LB quota is 20 against a fleet need of 50. It only bites if a Service falls back to
    # Classic, which the VTT's annotations prevent. Reported, not fatal, so a real fallback shows up
    # as an NLB count that does not match the cluster count rather than a surprise at 50.
    local clb
    clb="$(quota_value "${account}" "${Q_CLB}" elasticloadbalancing)"
    printf '  note  %s: Classic-LB quota %s (unused; the VTT is an NLB by annotation)\n' \
        "${account}" "${clb%.*}" >&2

    # The lab VPC must exist before any cluster apply, or the driver would have no subnets to pass.
    if [[ -f "$(vpc_state_file "${account}")" ]]; then
        pass "${account}: lab VPC state present"
    else
        printf '  note  %s: no lab VPC state yet (run: fleet.sh vpc-up %s)\n' "${account}" "${account}" >&2
    fi
}

main() {
    printf 'Fleet preflight: stage=%s region=%s\n' "${STAGE}" "${PACKT_REGION}" >&2
    check_tools
    local account
    while read -r account; do
        check_account "${account}"
    done < <(accounts_list)

    printf '\n' >&2
    if [[ "${FAILS}" -gt 0 ]]; then
        printf 'PREFLIGHT FAILED: %d problem(s)\n' "${FAILS}" >&2
        [[ -n "${JSON_OUT}" ]] && printf '{"stage":"%s","pass":false,"failures":%d}\n' "${STAGE}" "${FAILS}"
        exit 1
    fi
    printf 'PREFLIGHT PASSED for stage %s\n' "${STAGE}" >&2
    [[ -n "${JSON_OUT}" ]] && printf '{"stage":"%s","pass":true,"failures":0}\n' "${STAGE}"
    exit 0
}

main
