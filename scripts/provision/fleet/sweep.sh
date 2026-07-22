#!/usr/bin/env bash
# ABOUTME: Orphan sweep. Deletes what terraform does not own after a teardown: load balancers,
# ABOUTME: detached volumes, and the cross-referencing security groups that block VPC deletion.
#
# Teardown is not `terraform destroy`. Terraform does not own the load balancers Kubernetes created,
# and what it leaves behind both costs money and blocks the VPC from deleting. A comparable fleet
# observed ~2 orphaned load balancers per cluster (400 at 250 clusters), 61 detached volumes, and 15
# orphaned security groups in a single account after a teardown that skipped this step.
#
# The lab VPC is deliberately NOT destroyed unless --with-vpc is passed: keeping it means the next
# provisioning run is a cluster build only.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET=""
WITH_VPC=""

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} <account|all> [--with-vpc]

Deletes fleet-tagged orphans left after cluster teardown. Dry-run unless PACKT_APPLY=1.
  --with-vpc   also destroy the shared lab VPC (default: keep it for the next run)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-vpc) WITH_VPC=1; shift ;;
        -h|--help) usage ;;
        -*) printf 'unknown flag: %s\n' "$1" >&2; usage ;;
        *) TARGET="$1"; shift ;;
    esac
done
[[ -n "${TARGET}" ]] || usage

# Mass DeleteLoadBalancer gets API-throttled hard; the awscli default of 2 retries is not enough.
# Every mutating call in this script goes through here.
retry_aws() {
    local attempt=0 max=6 delay=2 out rc
    while :; do
        if out="$("$@" 2>&1)"; then
            # The trailing newline is load-bearing. Command substitution strips it, and a
            # `while read` loop fed a final line with no newline sets the variable but returns
            # non-zero, so the loop body never runs for that element. Every resource list here is
            # consumed by such a loop, so `printf '%s'` silently dropped the LAST load balancer,
            # target group, volume and security group. With a single load balancer that is all of
            # them, and the sweep reports a clean account while the NLB keeps billing.
            printf '%s\n' "${out}"
            return 0
        fi
        rc=$?
        if ! printf '%s' "${out}" | grep -qiE 'throttl|rate exceeded|requestlimitexceeded'; then
            printf '%s' "${out}" >&2
            return "${rc}"
        fi
        attempt=$((attempt + 1))
        (( attempt >= max )) && { printf '%s' "${out}" >&2; return "${rc}"; }
        sleep "${delay}"
        delay=$((delay * 2))
    done
}

# Runs a mutating call only when PACKT_APPLY=1; otherwise reports what it would have done.
do_or_echo() {
    local what="$1"; shift
    if [[ "${PACKT_APPLY}" == "1" ]]; then
        retry_aws "$@" >/dev/null || log "    (failed: ${what})"
    else
        log "    DRY-RUN would ${what}"
    fi
}

sweep_account() {
    local account="$1" vpc still_live
    assert_account "${account}"
    printf '\n=== sweep %s ===\n' "${account}" >&2
    export AWS_PROFILE="${account}"

    # HARD GUARD. This script deletes every load balancer in the lab VPC and every eks-cluster-sg
    # group it finds, on the assumption that the clusters are already gone. Run against an account
    # that still has live clusters it does not clean up orphans: it revokes the security groups of
    # RUNNING clusters and tears down their networking mid-workshop. Nothing else in the chain
    # stops that, so it is refused here rather than left to operator discipline.
    still_live="$(live_clusters "${account}" | wc -l)"
    if [[ "${still_live}" -gt 0 ]]; then
        log "  REFUSING: ${still_live} student cluster(s) still live in ${account}."
        log "  The sweep deletes load balancers and eks-cluster-sg groups belonging to live"
        log "  clusters. Tear them down first: PACKT_APPLY=1 ${0%/*}/fleet.sh down-fleet"
        log "  Override only if you know the remaining clusters are not yours: SWEEP_FORCE=1"
        [[ "${SWEEP_FORCE:-}" == "1" ]] || return 1
        log "  SWEEP_FORCE=1 set; proceeding anyway"
    fi

    vpc="$(retry_aws aws ec2 describe-vpcs --region "${PACKT_REGION}" \
        --filters "Name=tag:Workshop,Values=packt" "Name=tag:Purpose,Values=lab-shared-vpc" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo None)"
    [[ "${vpc}" == "None" || -z "${vpc}" ]] && { log "  no lab VPC found; nothing to sweep"; return 0; }
    log "  lab VPC: ${vpc}"

    # 1. Protect the NAT's EIP allocations first, then never release those.
    local nat_allocs
    nat_allocs="$(retry_aws aws ec2 describe-nat-gateways --region "${PACKT_REGION}" \
        --filter "Name=vpc-id,Values=${vpc}" "Name=state,Values=available,pending" \
        --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text 2>/dev/null || true)"
    log "  protected NAT EIP allocations: ${nat_allocs:-none}"

    # 2. Load balancers (v2 then classic) that Kubernetes created inside the lab VPC.
    local lb arn
    while read -r arn; do
        [[ -n "${arn}" && "${arn}" != "None" ]] || continue
        log "    elbv2 orphan: ${arn##*/}"
        do_or_echo "delete elbv2 ${arn##*/}" \
            aws elbv2 delete-load-balancer --region "${PACKT_REGION}" --load-balancer-arn "${arn}"
    done < <(retry_aws aws elbv2 describe-load-balancers --region "${PACKT_REGION}" \
        --query "LoadBalancers[?VpcId=='${vpc}'].LoadBalancerArn" --output text 2>/dev/null \
        | tr '\t' '\n')

    while read -r lb; do
        [[ -n "${lb}" && "${lb}" != "None" ]] || continue
        log "    classic ELB orphan: ${lb}"
        do_or_echo "delete classic ELB ${lb}" \
            aws elb delete-load-balancer --region "${PACKT_REGION}" --load-balancer-name "${lb}"
    done < <(retry_aws aws elb describe-load-balancers --region "${PACKT_REGION}" \
        --query "LoadBalancerDescriptions[?VPCId=='${vpc}'].LoadBalancerName" --output text 2>/dev/null \
        | tr '\t' '\n')

    # Target groups orphan separately from their load balancers.
    while read -r arn; do
        [[ -n "${arn}" && "${arn}" != "None" ]] || continue
        do_or_echo "delete target group ${arn##*/}" \
            aws elbv2 delete-target-group --region "${PACKT_REGION}" --target-group-arn "${arn}"
    done < <(retry_aws aws elbv2 describe-target-groups --region "${PACKT_REGION}" \
        --query "TargetGroups[?VpcId=='${vpc}'].TargetGroupArn" --output text 2>/dev/null | tr '\t' '\n')

    # 3. Wait for LB ENIs to drain. EIPs cannot disassociate and subnets cannot delete until they do.
    if [[ "${PACKT_APPLY}" == "1" ]]; then
        local i=0 enis
        while (( i < 40 )); do
            enis="$(retry_aws aws ec2 describe-network-interfaces --region "${PACKT_REGION}" \
                --filters "Name=vpc-id,Values=${vpc}" "Name=description,Values=ELB*" \
                --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 0)"
            [[ "${enis}" == "0" ]] && break
            log "    waiting on ${enis} ELB ENI(s) to drain"
            sleep 15
            i=$((i + 1))
        done
    fi

    # 4. Detached EBS volumes left by PVCs whose CSI controller died with the cluster.
    #
    # Two selectors, because they catch different volumes. The node root volumes carry
    # Workshop=packt from the launch template. The PVC volumes are created by the EBS CSI driver,
    # which applies only its own kubernetes.io/* tags: measured on the live fleet, 100 of 150
    # volumes had no Workshop tag at all (two PVCs per cluster, so 500 at full size). The
    # StorageClass now adds our tags to NEW volumes, but anything provisioned before that, and
    # anything provisioned by a chart with its own StorageClass, still needs the second selector.
    #
    # The second selector keys on kubernetes.io/cluster/student<N>, which the CSI driver always
    # writes and which the fleet name guard makes unambiguously ours. Only `available` volumes are
    # ever deleted, so an in-use volume is never touched.
    local vol
    delete_available_volumes() {
        local desc="$1"; shift
        while read -r vol; do
            [[ -n "${vol}" && "${vol}" != "None" ]] || continue
            log "    detached volume (${desc}): ${vol}"
            do_or_echo "delete volume ${vol}" \
                aws ec2 delete-volume --region "${PACKT_REGION}" --volume-id "${vol}"
        done < <(retry_aws aws ec2 describe-volumes --region "${PACKT_REGION}" \
            --filters "Name=status,Values=available" "$@" \
            --query 'Volumes[].VolumeId' --output text 2>/dev/null | tr '\t' '\n')
    }
    delete_available_volumes "Workshop tag" "Name=tag:Workshop,Values=packt"
    delete_available_volumes "CSI/PVC" "Name=tag-key,Values=kubernetes.io/cluster/student*"

    # 5. Orphaned eks-cluster-sg-* groups. They cross-reference each other, so DeleteSecurityGroup
    #    fails with DependencyViolation while the references exist: revoke all rules first.
    local sg
    local -a sgs=()
    while read -r sg; do
        [[ -n "${sg}" && "${sg}" != "None" ]] || continue
        sgs+=("${sg}")
    done < <(retry_aws aws ec2 describe-security-groups --region "${PACKT_REGION}" \
        --filters "Name=vpc-id,Values=${vpc}" "Name=group-name,Values=eks-cluster-sg-*" \
        --query 'SecurityGroups[].GroupId' --output text 2>/dev/null | tr '\t' '\n')

    if (( ${#sgs[@]} )); then
        log "    ${#sgs[@]} orphaned eks-cluster-sg group(s); revoking rules before delete"
        for sg in "${sgs[@]}"; do
            local ing egr
            ing="$(retry_aws aws ec2 describe-security-groups --region "${PACKT_REGION}" \
                --group-ids "${sg}" --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo '[]')"
            egr="$(retry_aws aws ec2 describe-security-groups --region "${PACKT_REGION}" \
                --group-ids "${sg}" --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null || echo '[]')"
            [[ "${ing}" != "[]" ]] && do_or_echo "revoke ingress on ${sg}" \
                aws ec2 revoke-security-group-ingress --region "${PACKT_REGION}" \
                --group-id "${sg}" --ip-permissions "${ing}"
            [[ "${egr}" != "[]" ]] && do_or_echo "revoke egress on ${sg}" \
                aws ec2 revoke-security-group-egress --region "${PACKT_REGION}" \
                --group-id "${sg}" --ip-permissions "${egr}"
        done
        for sg in "${sgs[@]}"; do
            do_or_echo "delete security group ${sg}" \
                aws ec2 delete-security-group --region "${PACKT_REGION}" --group-id "${sg}"
        done
    fi

    # 6. Optionally the lab VPC itself.
    if [[ -n "${WITH_VPC}" ]]; then
        if [[ "${PACKT_APPLY}" == "1" ]]; then
            log "  destroying lab VPC"
            terraform -chdir="${LAB_VPC_DIR}" destroy -auto-approve -no-color -input=false \
                -state="$(vpc_state_file "${account}")" \
                -var "profile=${account}" -var "region=${PACKT_REGION}" \
                >"${LOG_ROOT}/${account}/lab-vpc.destroy.log" 2>&1 \
                || log "  lab VPC destroy FAILED (see ${LOG_ROOT}/${account}/lab-vpc.destroy.log)"
        else
            log "  DRY-RUN would destroy the lab VPC"
        fi
    else
        log "  keeping the lab VPC (pass --with-vpc to remove it)"
    fi

    report_account "${account}" "${vpc}"
}

# Anything non-zero here is a leak and must be explained, not waved through.
report_account() {
    local account="$1" vpc="$2" eks ec2c clb elbv2 vols
    eks="$(live_clusters "${account}" | wc -l)"
    ec2c="$(retry_aws aws ec2 describe-instances --region "${PACKT_REGION}" \
        --filters "Name=tag:Workshop,Values=packt" "Name=instance-state-name,Values=running,pending" \
        --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo '?')"
    elbv2="$(retry_aws aws elbv2 describe-load-balancers --region "${PACKT_REGION}" \
        --query "length(LoadBalancers[?VpcId=='${vpc}'])" --output text 2>/dev/null || echo '?')"
    clb="$(retry_aws aws elb describe-load-balancers --region "${PACKT_REGION}" \
        --query "length(LoadBalancerDescriptions[?VPCId=='${vpc}'])" --output text 2>/dev/null || echo '?')"
    vols="$(retry_aws aws ec2 describe-volumes --region "${PACKT_REGION}" \
        --filters "Name=status,Values=available" "Name=tag:Workshop,Values=packt" \
        --query 'length(Volumes)' --output text 2>/dev/null || echo '?')"
    printf '  RESULT %s: eks=%s ec2=%s clb=%s elbv2=%s volumes=%s\n' \
        "${account}" "${eks}" "${ec2c}" "${clb}" "${elbv2}" "${vols}" >&2
}

main() {
    [[ "${PACKT_APPLY}" == "1" ]] || log "DRY-RUN mode (set PACKT_APPLY=1 to execute)"
    local account
    while read -r account; do
        sweep_account "${account}"
    done < <( [[ "${TARGET}" == "all" ]] && accounts_list || printf '%s\n' "${TARGET}" )
}

main
