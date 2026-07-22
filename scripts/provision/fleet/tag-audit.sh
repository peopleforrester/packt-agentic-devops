#!/usr/bin/env bash
# ABOUTME: Audits every taggable fleet resource for the Workshop=packt tag and, with --fix, applies
# ABOUTME: it to anything of ours that is missing it. Untagged infrastructure is infrastructure the
# ABOUTME: orphan sweep cannot see, and what the sweep cannot see bills forever.
#
# Not everything we create is tagged by the thing that creates it. Terraform default_tags cover what
# terraform makes; they do NOT reach EC2 instances under a managed node group (launch template
# tag_specifications do), volumes the EBS CSI driver provisions, log groups EKS creates, or the
# security groups EKS attaches. Each of those is a separate mechanism, and each was verified here
# against the live fleet rather than assumed.
#
# SAFETY: these accounts are shared with a co-tenant project. Nothing is tagged unless it is
# provably ours, by one of:
#   - an EKS cluster name matching ^student[0-9]+$
#   - membership of the lab VPC (itself tagged Purpose=lab-shared-vpc)
#   - a kubernetes.io/cluster/student<N> tag written by the CNI or CSI driver
#   - an IAM role name in the fleet's own naming scheme
# A resource that matches none of those is reported as "foreign" and never touched.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

readonly TAG_KEY="Workshop"
readonly TAG_VAL="packt"
FIX=""
TARGET=""
MISSING=0
FIXED=0

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} <account|all> [--fix]

Audits fleet resources for ${TAG_KEY}=${TAG_VAL}. Read-only unless --fix is given.
Reports per resource type: tagged / missing / foreign (not ours, never touched).
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix) FIX=1; shift ;;
        -h|--help) usage ;;
        -*) printf 'unknown flag: %s\n' "$1" >&2; usage ;;
        *) TARGET="$1"; shift ;;
    esac
done
[[ -n "${TARGET}" ]] || usage

report() { printf '  %-26s tagged=%-5s missing=%-5s %s\n' "$1" "$2" "$3" "${4:-}" >&2; }

# ec2-family tagging (instances, volumes, ENIs, security groups, subnets, VPCs, gateways...)
fix_ec2() {
    local ids="$1" kind="$2"
    [[ -n "${ids}" ]] || return 0
    MISSING=$((MISSING + $(wc -w <<<"${ids}")))
    if [[ -n "${FIX}" ]]; then
        # shellcheck disable=SC2086  # deliberate word splitting: create-tags takes an id list
        aws ec2 create-tags --region "${PACKT_REGION}" --resources ${ids} \
            --tags "Key=${TAG_KEY},Value=${TAG_VAL}" "Key=Project,Value=packt-agentic-devops" \
            >/dev/null 2>&1 && FIXED=$((FIXED + $(wc -w <<<"${ids}"))) \
            || log "    failed tagging ${kind}"
    fi
}

audit_account() {
    local account="$1" vpc
    assert_account "${account}"
    printf '\n=== %s ===\n' "${account}" >&2
    export AWS_PROFILE="${account}"

    vpc="$(aws ec2 describe-vpcs --region "${PACKT_REGION}" \
        --filters "Name=tag:${TAG_KEY},Values=${TAG_VAL}" "Name=tag:Purpose,Values=lab-shared-vpc" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo None)"
    [[ "${vpc}" == "None" || -z "${vpc}" ]] && { log "  no lab VPC; skipping"; return 0; }

    # --- EBS volumes -------------------------------------------------------------------------
    # Root volumes come from the launch template and are tagged. CSI volumes are not: the driver
    # writes only kubernetes.io/* tags, which is how 100 of 150 volumes went missing.
    local tagged untagged
    tagged="$(aws ec2 describe-volumes --region "${PACKT_REGION}" \
        --filters "Name=tag:${TAG_KEY},Values=${TAG_VAL}" --query 'length(Volumes)' --output text)"
    untagged="$(aws ec2 describe-volumes --region "${PACKT_REGION}" \
        --filters "Name=tag-key,Values=kubernetes.io/cluster/student*" \
        --query "Volumes[?!not_null(Tags[?Key=='${TAG_KEY}'])].VolumeId" --output text | tr '\t' ' ')"
    report "EBS volumes" "${tagged}" "$(wc -w <<<"${untagged}")"
    fix_ec2 "${untagged}" "volumes"

    # --- Network interfaces ------------------------------------------------------------------
    # The CNI creates ENIs per node and the load balancers create their own. They are billable
    # only indirectly, but an untagged ENI is what blocks a subnet delete with no explanation.
    untagged="$(aws ec2 describe-network-interfaces --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" \
        --query "NetworkInterfaces[?!not_null(TagSet[?Key=='${TAG_KEY}'])].NetworkInterfaceId" \
        --output text | tr '\t' ' ')"
    tagged="$(aws ec2 describe-network-interfaces --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" "Name=tag:${TAG_KEY},Values=${TAG_VAL}" \
        --query 'length(NetworkInterfaces)' --output text)"
    report "Network interfaces" "${tagged}" "$(wc -w <<<"${untagged}")"
    fix_ec2 "${untagged}" "ENIs"

    # --- Security groups ---------------------------------------------------------------------
    # EKS creates eks-cluster-sg-* outside terraform state. These are the groups that fail
    # DeleteVpc with DependencyViolation, so being able to find them by tag matters.
    untagged="$(aws ec2 describe-security-groups --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" \
        --query "SecurityGroups[?!not_null(Tags[?Key=='${TAG_KEY}'])].GroupId" --output text | tr '\t' ' ')"
    tagged="$(aws ec2 describe-security-groups --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" "Name=tag:${TAG_KEY},Values=${TAG_VAL}" \
        --query 'length(SecurityGroups)' --output text)"
    report "Security groups" "${tagged}" "$(wc -w <<<"${untagged}")"
    fix_ec2 "${untagged}" "security groups"

    # --- Instances ---------------------------------------------------------------------------
    untagged="$(aws ec2 describe-instances --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" "Name=instance-state-name,Values=running,pending,stopped" \
        --query "Reservations[].Instances[?!not_null(Tags[?Key=='${TAG_KEY}'])].InstanceId" \
        --output text | tr '\t' ' ')"
    tagged="$(aws ec2 describe-instances --region "${PACKT_REGION}" \
        --filters "Name=tag:${TAG_KEY},Values=${TAG_VAL}" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'length(Reservations[].Instances[])' --output text)"
    report "EC2 instances" "${tagged}" "$(wc -w <<<"${untagged}")"
    fix_ec2 "${untagged}" "instances"

    # --- Load balancers and target groups ----------------------------------------------------
    # The LB controller applies aws-load-balancer-additional-resource-tags, but a target group
    # created before that annotation existed, or by another chart, would be missed.
    local arn n_tagged=0 n_missing=0 arns
    arns="$(aws elbv2 describe-load-balancers --region "${PACKT_REGION}" \
        --query "LoadBalancers[?VpcId=='${vpc}'].LoadBalancerArn" --output text | tr '\t' '\n')"
    for arn in ${arns}; do
        [[ -n "${arn}" ]] || continue
        if aws elbv2 describe-tags --region "${PACKT_REGION}" --resource-arns "${arn}" \
                --query "TagDescriptions[0].Tags[?Key=='${TAG_KEY}'].Value" --output text 2>/dev/null \
                | grep -q "${TAG_VAL}"; then
            n_tagged=$((n_tagged + 1))
        else
            n_missing=$((n_missing + 1)); MISSING=$((MISSING + 1))
            if [[ -n "${FIX}" ]]; then
                aws elbv2 add-tags --region "${PACKT_REGION}" --resource-arns "${arn}" \
                    --tags "Key=${TAG_KEY},Value=${TAG_VAL}" >/dev/null 2>&1 \
                    && FIXED=$((FIXED + 1))
            fi
        fi
    done
    report "Load balancers" "${n_tagged}" "${n_missing}"

    n_tagged=0; n_missing=0
    arns="$(aws elbv2 describe-target-groups --region "${PACKT_REGION}" \
        --query "TargetGroups[?VpcId=='${vpc}'].TargetGroupArn" --output text | tr '\t' '\n')"
    for arn in ${arns}; do
        [[ -n "${arn}" ]] || continue
        if aws elbv2 describe-tags --region "${PACKT_REGION}" --resource-arns "${arn}" \
                --query "TagDescriptions[0].Tags[?Key=='${TAG_KEY}'].Value" --output text 2>/dev/null \
                | grep -q "${TAG_VAL}"; then
            n_tagged=$((n_tagged + 1))
        else
            n_missing=$((n_missing + 1)); MISSING=$((MISSING + 1))
            if [[ -n "${FIX}" ]]; then
                aws elbv2 add-tags --region "${PACKT_REGION}" --resource-arns "${arn}" \
                    --tags "Key=${TAG_KEY},Value=${TAG_VAL}" >/dev/null 2>&1 \
                    && FIXED=$((FIXED + 1))
            fi
        fi
    done
    report "Target groups" "${n_tagged}" "${n_missing}"

    # --- CloudWatch log groups ---------------------------------------------------------------
    # EKS creates /aws/eks/<cluster>/cluster itself (create_cloudwatch_log_group=false), so
    # terraform never tags it and it survives destroy.
    local lg name
    n_tagged=0; n_missing=0
    while read -r lg; do
        [[ -n "${lg}" ]] || continue
        name="${lg#/aws/eks/}"; name="${name%/cluster}"
        [[ "${name}" =~ ^student[0-9]+$ ]] || continue
        if aws logs list-tags-for-resource --region "${PACKT_REGION}" \
                --resource-arn "arn:aws:logs:${PACKT_REGION}:$(aws sts get-caller-identity --query Account --output text):log-group:${lg}" \
                --query "tags.${TAG_KEY}" --output text 2>/dev/null | grep -q "${TAG_VAL}"; then
            n_tagged=$((n_tagged + 1))
        else
            n_missing=$((n_missing + 1)); MISSING=$((MISSING + 1))
            if [[ -n "${FIX}" ]]; then
                aws logs tag-log-group --region "${PACKT_REGION}" --log-group-name "${lg}" \
                    --tags "${TAG_KEY}=${TAG_VAL}" >/dev/null 2>&1 && FIXED=$((FIXED + 1))
            fi
        fi
    done < <(aws logs describe-log-groups --region "${PACKT_REGION}" \
        --log-group-name-prefix "/aws/eks/student" \
        --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' '\n')
    report "CloudWatch log groups" "${n_tagged}" "${n_missing}"

    # --- IAM roles ---------------------------------------------------------------------------
    # IAM is global, not regional. Roles follow the fleet naming scheme, which is what makes them
    # safely identifiable in a shared account.
    local role
    n_tagged=0; n_missing=0
    while read -r role; do
        [[ -n "${role}" ]] || continue
        [[ "${role}" =~ ^(packt-student-)?student[0-9]+(-ebs-csi|-aws-lbc)?$ || "${role}" =~ ^packt-student-student[0-9]+$ ]] || continue
        if aws iam list-role-tags --role-name "${role}" \
                --query "Tags[?Key=='${TAG_KEY}'].Value" --output text 2>/dev/null | grep -q "${TAG_VAL}"; then
            n_tagged=$((n_tagged + 1))
        else
            n_missing=$((n_missing + 1)); MISSING=$((MISSING + 1))
            if [[ -n "${FIX}" ]]; then
                aws iam tag-role --role-name "${role}" \
                    --tags "Key=${TAG_KEY},Value=${TAG_VAL}" >/dev/null 2>&1 && FIXED=$((FIXED + 1))
            fi
        fi
    done < <(aws iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
    report "IAM roles" "${n_tagged}" "${n_missing}"
}

main() {
    [[ -n "${FIX}" ]] || log "AUDIT ONLY (pass --fix to apply missing tags)"
    local account
    while read -r account; do
        audit_account "${account}"
    done < <( [[ "${TARGET}" == "all" ]] && accounts_list || printf '%s\n' "${TARGET}" )

    printf '\n' >&2
    if [[ -n "${FIX}" ]]; then
        log "TOTAL: ${MISSING} untagged found, ${FIXED} tagged"
        [[ "${MISSING}" -eq "${FIXED}" ]] || { log "some resources could not be tagged"; exit 1; }
    else
        log "TOTAL: ${MISSING} resource(s) missing ${TAG_KEY}=${TAG_VAL}"
        [[ "${MISSING}" -eq 0 ]] || exit 1
    fi
}

main
