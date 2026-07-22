#!/usr/bin/env bash
# ABOUTME: Shared helpers for the fleet driver: account map, name and account guards, per-cluster
# ABOUTME: kubeconfig handling, and the secondary identity check that runs before any mutation.
#
# Sourced, never executed. Everything here is deliberately paranoid: the five accounts are shared
# with a co-tenant project and with Michael's own adwc-dev, so "which cluster am I about to change"
# is never answered from current-context alone.

# The five fleet accounts, in range order. Account i owns student[i*BLOCK+1 .. i*BLOCK+BLOCK].
PACKT_ACCOUNTS="${PACKT_ACCOUNTS:-accen-dev,aws1-student31,aws1-student32,aws1-student33,aws1-student34}"
PACKT_REGION="${PACKT_REGION:-us-west-2}"
PACKT_DOMAIN="${PACKT_DOMAIN:-packt.ai-enhanced-devops.com}"
# Clusters per account at full size. Also the width of each account's name range, so ranges stay
# disjoint no matter what n a given command is called with.
PACKT_BLOCK="${PACKT_BLOCK:-50}"
# Per-account concurrency. Total = this x 5 accounts. The binding constraint is local RAM (~600 MB
# per terraform build tree), not AWS: most of a build is an idle ~9m30s wait on the control plane.
MAX_PARALLEL="${MAX_PARALLEL:-10}"
# Every destructive verb is a no-op unless this is 1.
PACKT_APPLY="${PACKT_APPLY:-}"

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_DIR="$(cd "${FLEET_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PROVISION_DIR}/../.." && pwd)"
CLUSTER_DIR="${PROVISION_DIR}/cluster"
LAB_VPC_DIR="${PROVISION_DIR}/lab-vpc"
VTT_DIR="${PROVISION_DIR}/vtt"
STATE_ROOT="${FLEET_DIR}/states"
LOG_ROOT="${FLEET_DIR}/logs"
export FLEET_DIR PROVISION_DIR REPO_ROOT CLUSTER_DIR LAB_VPC_DIR VTT_DIR STATE_ROOT LOG_ROOT
export PACKT_ACCOUNTS PACKT_REGION PACKT_DOMAIN PACKT_BLOCK MAX_PARALLEL PACKT_APPLY

# Names this driver must never touch, whatever else happens.
readonly FORBIDDEN_NAMES="adwc-dev"

log()  { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die()  { log "FATAL: $*"; exit 1; }

accounts_list() { printf '%s\n' "${PACKT_ACCOUNTS}" | tr ',' '\n' | sed '/^$/d'; }

account_index() {
    local want="$1" i=0 a
    while read -r a; do
        [[ "${a}" == "${want}" ]] && { printf '%s' "${i}"; return 0; }
        i=$((i + 1))
    done < <(accounts_list)
    return 1
}

# Cluster names owned by an account: student[i*BLOCK+1 .. i*BLOCK+n].
account_names() {
    local account="$1" n="$2" idx base i
    idx="$(account_index "${account}")" || die "unknown account: ${account}"
    base=$((idx * PACKT_BLOCK))
    (( n <= PACKT_BLOCK )) || die "n=${n} exceeds the ${PACKT_BLOCK}-wide range for ${account}"
    for ((i = 1; i <= n; i++)); do printf 'student%d\n' $((base + i)); done
}

# --- Guards ----------------------------------------------------------------------------------

# The name is the state file, the terraform -var, the IAM role suffix and the resource tag, so a
# refused name cannot produce an apply, a destroy, or a tagged resource anywhere.
assert_ours() {
    local name="$1" forbidden
    [[ "${name}" =~ ^student[0-9]+$ ]] || die "REFUSING non-fleet name: ${name}"
    for forbidden in ${FORBIDDEN_NAMES}; do
        [[ "${name}" == "${forbidden}" ]] && die "REFUSING ${forbidden}: not part of the fleet"
    done
    return 0
}

assert_account() {
    local account="$1"
    account_index "${account}" >/dev/null || die "REFUSING unknown account: ${account}"
}

# A cluster's account is persisted at apply time and read back on every later operation. Recomputing
# it from offset arithmetic is how a mismatched n silently orphans clusters.
membership_file() { printf '%s/%s/%s.account' "${STATE_ROOT}" "$1" "$2"; }
state_file()      { printf '%s/%s/%s.tfstate' "${STATE_ROOT}" "$1" "$2"; }
kubeconfig_file() { printf '%s/%s/%s.kubeconfig' "${STATE_ROOT}" "$1" "$2"; }

record_membership() {
    local account="$1" name="$2"
    mkdir -p "${STATE_ROOT}/${account}"
    printf '%s\n' "${account}" > "$(membership_file "${account}" "${name}")"
}

# Read the account a cluster actually belongs to. Refuses to guess.
read_membership() {
    local account="$1" name="$2" f
    f="$(membership_file "${account}" "${name}")"
    [[ -f "${f}" ]] || return 1
    cat "${f}"
}

assert_membership_matches() {
    local account="$1" name="$2" recorded
    recorded="$(read_membership "${account}" "${name}")" \
        || die "no membership record for ${name}; refusing to act on a cluster we cannot place"
    [[ "${recorded}" == "${account}" ]] \
        || die "membership mismatch for ${name}: recorded=${recorded} requested=${account}"
}

require_apply() {
    [[ "${PACKT_APPLY}" == "1" ]] || {
        log "DRY-RUN: would $* (set PACKT_APPLY=1 to execute)"
        return 1
    }
    return 0
}

# --- Cluster identity ------------------------------------------------------------------------

write_kubeconfig() {
    local account="$1" name="$2" kc
    kc="$(kubeconfig_file "${account}" "${name}")"
    AWS_PROFILE="${account}" aws eks update-kubeconfig --name "${name}" \
        --region "${PACKT_REGION}" --kubeconfig "${kc}" >/dev/null 2>&1 || return 1
    printf '%s' "${kc}"
}

# Verify the kubeconfig points at the cluster we think it does, independently of current-context.
# current-context is a string we wrote ourselves; the API endpoint and the Workshop tag come from
# AWS. Both must agree before anything mutating runs.
assert_cluster_identity() {
    local account="$1" name="$2" kc server expect tag
    kc="$(kubeconfig_file "${account}" "${name}")"
    [[ -f "${kc}" ]] || { log "${name}: no kubeconfig"; return 1; }
    server="$(KUBECONFIG="${kc}" kubectl config view --minify \
        -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
    expect="$(AWS_PROFILE="${account}" aws eks describe-cluster --name "${name}" \
        --region "${PACKT_REGION}" --query 'cluster.endpoint' --output text 2>/dev/null)"
    tag="$(AWS_PROFILE="${account}" aws eks describe-cluster --name "${name}" \
        --region "${PACKT_REGION}" --query 'cluster.tags.Workshop' --output text 2>/dev/null)"
    [[ -n "${server}" && "${server}" == "${expect}" ]] \
        || { log "${name}: ABORT endpoint mismatch (kubeconfig=${server} aws=${expect})"; return 1; }
    [[ "${tag}" == "packt" ]] \
        || { log "${name}: ABORT Workshop tag is '${tag}', not 'packt'"; return 1; }
    return 0
}

# --- Lab VPC ---------------------------------------------------------------------------------

vpc_state_file() { printf '%s/%s/lab-vpc.tfstate' "${STATE_ROOT}" "$1"; }

read_vpc_outputs() {
    local account="$1" st
    st="$(vpc_state_file "${account}")"
    [[ -f "${st}" ]] || die "no lab VPC state for ${account}. Run: fleet.sh vpc-up ${account}"
    VPC_ID="$(terraform -chdir="${LAB_VPC_DIR}" output -state="${st}" -raw vpc_id 2>/dev/null)"
    SUBNETS_JSON="$(terraform -chdir="${LAB_VPC_DIR}" output -state="${st}" -json private_subnet_ids 2>/dev/null)"
    [[ -n "${VPC_ID}" && -n "${SUBNETS_JSON}" ]] \
        || die "could not read lab VPC outputs for ${account} from ${st}"
    export VPC_ID SUBNETS_JSON
}

# --- Student URL -----------------------------------------------------------------------------

student_url() { printf 'https://%s.%s' "$1" "${PACKT_DOMAIN}"; }

# The raw NLB hostname the router forwards to. Empty until AWS assigns it.
cluster_lb_host() {
    local account="$1" name="$2" kc
    kc="$(kubeconfig_file "${account}" "${name}")"
    [[ -f "${kc}" ]] || return 1
    KUBECONFIG="${kc}" kubectl -n workshop get svc web-terminal \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null
}

# --- Inventory -------------------------------------------------------------------------------

# Clusters with persisted state, per account. This is the fleet as the driver knows it; the live
# AWS listing is a separate question and the two are reconciled by `status`.
known_clusters() {
    local account="$1" f name
    [[ -d "${STATE_ROOT}/${account}" ]] || return 0
    for f in "${STATE_ROOT}/${account}"/*.tfstate; do
        [[ -e "${f}" ]] || return 0
        name="$(basename "${f}" .tfstate)"
        [[ "${name}" == "lab-vpc" ]] && continue
        printf '%s\n' "${name}"
    done
}

live_clusters() {
    local account="$1"
    AWS_PROFILE="${account}" aws eks list-clusters --region "${PACKT_REGION}" \
        --query 'clusters[]' --output text 2>/dev/null | tr '\t' '\n' | grep -E '^student[0-9]+$' || true
}
