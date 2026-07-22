#!/usr/bin/env bash
# ABOUTME: Builds the instructor's standalone cluster: same module and bootstrap chain as a student
# ABOUTME: cluster, but in a separate account and outside the fleet driver's reach entirely.
#
# This cluster is for rehearsal, recording and run-of-show. It must NEVER be touched by fleet
# teardown, reap or sweep, and two independent things guarantee that:
#
#   1. It lives in `kcd-instructor`, which is deliberately absent from PACKT_ACCOUNTS. Every fleet
#      verb calls assert_account first, so they refuse this account by name.
#   2. It is named `instructor`, and assert_ours pins fleet names to ^student[0-9]+$, so even a
#      command aimed at this account could not select it.
#
# Its terraform state also lives here rather than under fleet/states/, so `down-fleet`, which
# iterates the fleet state directory, cannot see it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR PROVISION_DIR
readonly CLUSTER_DIR="${PROVISION_DIR}/cluster"
readonly LAB_VPC_DIR="${PROVISION_DIR}/lab-vpc"
readonly VTT_DIR="${PROVISION_DIR}/vtt"
readonly STATE_DIR="${SCRIPT_DIR}/states"
readonly LOG_DIR="${SCRIPT_DIR}/logs"

readonly PROFILE="${INSTRUCTOR_PROFILE:-kcd-instructor}"
readonly REGION="${INSTRUCTOR_REGION:-us-west-2}"
readonly NAME="${INSTRUCTOR_NAME:-instructor}"
readonly DOMAIN="${PACKT_DOMAIN:-packt.ai-enhanced-devops.com}"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "FATAL: $*"; exit 1; }

# The one thing that would make this cluster dangerous is building it in a fleet account, where a
# teardown could reach it. Refuse outright.
case "${PROFILE}" in
    accen-dev|aws1-student3[1-4])
        die "REFUSING: ${PROFILE} is a fleet account. The instructor cluster must be isolated." ;;
esac
[[ "${NAME}" =~ ^student[0-9]+$ ]] && die "REFUSING: '${NAME}' is inside the fleet name range."

main() {
    mkdir -p "${STATE_DIR}" "${LOG_DIR}"
    command -v terraform >/dev/null 2>&1 || die "terraform not found"

    log "account: $(AWS_PROFILE="${PROFILE}" aws sts get-caller-identity --query Account --output text)"

    log "1/5 lab VPC"
    terraform -chdir="${LAB_VPC_DIR}" init -input=false >/dev/null
    terraform -chdir="${LAB_VPC_DIR}" apply -auto-approve -no-color -input=false \
        -state="${STATE_DIR}/lab-vpc.tfstate" \
        -var "profile=${PROFILE}" -var "region=${REGION}" \
        >"${LOG_DIR}/lab-vpc.log" 2>&1 || die "lab VPC apply failed (see ${LOG_DIR}/lab-vpc.log)"

    local vpc subnets
    vpc="$(terraform -chdir="${LAB_VPC_DIR}" output -state="${STATE_DIR}/lab-vpc.tfstate" -raw vpc_id)"
    subnets="$(terraform -chdir="${LAB_VPC_DIR}" output -state="${STATE_DIR}/lab-vpc.tfstate" -json private_subnet_ids)"
    log "    vpc=${vpc}"

    log "2/5 cluster ${NAME} (~13 min: the EKS control plane is an irreducible ~10)"
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    terraform -chdir="${CLUSTER_DIR}" apply -auto-approve -no-color -input=false \
        -state="${STATE_DIR}/${NAME}.tfstate" \
        -var "name=${NAME}" -var "profile=${PROFILE}" -var "region=${REGION}" \
        -var "vpc_id=${vpc}" -var "private_subnet_ids=${subnets}" \
        >"${LOG_DIR}/${NAME}.apply.log" 2>&1 || die "cluster apply failed (see ${LOG_DIR}/${NAME}.apply.log)"

    log "3/5 kubeconfig and identity check"
    local kc="${STATE_DIR}/${NAME}.kubeconfig"
    AWS_PROFILE="${PROFILE}" aws eks update-kubeconfig --name "${NAME}" \
        --region "${REGION}" --kubeconfig "${kc}" >/dev/null
    local server expect
    server="$(KUBECONFIG="${kc}" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
    expect="$(AWS_PROFILE="${PROFILE}" aws eks describe-cluster --name "${NAME}" \
        --region "${REGION}" --query 'cluster.endpoint' --output text)"
    [[ "${server}" == "${expect}" ]] || die "kubeconfig endpoint does not match the AWS API"

    log "4/5 platform bootstrap (LB controller, gp3, Gitea, VTT)"
    KUBECONFIG="${kc}" AWS_PROFILE="${PROFILE}" AWS_REGION="${REGION}" EXPECT_CONTEXT="${NAME}" \
        "${VTT_DIR}/apply.sh" >"${LOG_DIR}/${NAME}.vtt.log" 2>&1 \
        || die "VTT bootstrap failed (see ${LOG_DIR}/${NAME}.vtt.log)"

    log "5/5 AWS access via Pod Identity"
    KUBECONFIG="${kc}" AWS_PROFILE="${PROFILE}" AWS_REGION="${REGION}" \
        "${VTT_DIR}/student-aws-creds.sh" "${NAME}" >"${LOG_DIR}/${NAME}.creds.log" 2>&1 \
        || die "student-aws-creds failed"

    local host i=0
    while (( i < 60 )); do
        host="$(KUBECONFIG="${kc}" kubectl -n workshop get svc web-terminal \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
        [[ -n "${host}" ]] && break
        sleep 10; i=$((i + 1))
    done
    [[ -n "${host}" ]] || die "no LoadBalancer hostname assigned"

    printf '\n' >&2
    log "INSTRUCTOR CLUSTER READY"
    log "  cluster:   ${NAME} in ${PROFILE} (${REGION})"
    log "  kubeconfig ${kc}"
    log "  NLB        ${host}"
    log "  HTTPS      https://${NAME}.${DOMAIN}   (after: fleet/routes.sh)"
    printf '%s\n' "${host}" > "${STATE_DIR}/${NAME}.lbhost"
}

main "$@"
