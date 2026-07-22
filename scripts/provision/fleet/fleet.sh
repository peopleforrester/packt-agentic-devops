#!/usr/bin/env bash
# ABOUTME: Fleet driver. Brings each of five AWS accounts TO a target cluster count, chaining every
# ABOUTME: cluster all the way to a working HTTPS terminal, and tears them down in the order that works.
#
# Additive and idempotent by design: `up <account> 50` brings that account to 50, skipping clusters
# that already exist and pass health. That is what makes the rollout progressive (5 -> 54 -> 250)
# rather than three separate builds, and what lets the fleet scale down and back up without a rebuild.
#
# A cluster is NOT done when `terraform apply` exits 0. It is done when the URL a student would open
# answers. Everything between those two points is where the failures live.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} <verb> [args]

  preflight [stage]          L0 gate. stage = s1 | s2 | s3 (default s1)
  vpc-up <account|all>       Apply the shared lab VPC for an account
  up <account> <n>           Bring <account> TO n clusters (additive, idempotent)
  up-fleet <n>               Bring every account to n, all accounts concurrently
  health <account|all>       Re-assert L1-L3 across known clusters
  routes                     Regenerate routes.map from the live fleet and deploy the router
  ingest                     Write distribution/pool.csv from the live fleet
  status                     Known vs live cluster counts per account
  down <account> <name...>   Destroy named clusters                 [PACKT_APPLY=1]
  down-fleet                 Destroy every known cluster            [PACKT_APPLY=1]
  reap --keep <file>         Destroy clusters NOT listed in <file>  [PACKT_APPLY=1]
  sweep <account|all>        Orphan sweep                           [PACKT_APPLY=1]

Env: PACKT_ACCOUNTS PACKT_REGION PACKT_DOMAIN PACKT_BLOCK MAX_PARALLEL PACKT_APPLY
Now: accounts=${PACKT_ACCOUNTS} region=${PACKT_REGION} block=${PACKT_BLOCK} parallel=${MAX_PARALLEL}/account
EOF
    exit 2
}

require_tools() {
    local t missing=0
    for t in terraform kubectl aws jq curl helm python3; do
        command -v "${t}" >/dev/null 2>&1 || { log "missing tool: ${t}"; missing=1; }
    done
    [[ "${missing}" -eq 0 ]] || die "install the missing tools first"
}

# --- Failure recording -----------------------------------------------------------------------
# A backgrounded exit code that nobody reads is how a partial fleet looks complete. Every worker
# records its own outcome to a file, and the gate reads the file rather than trusting the shell.

RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
FAILURES="${LOG_ROOT}/failures-${RUN_ID}.txt"
SUCCESSES="${LOG_ROOT}/ok-${RUN_ID}.txt"
export RUN_ID FAILURES SUCCESSES

record_fail() { mkdir -p "${LOG_ROOT}"; printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "${FAILURES}"; }
record_ok() { mkdir -p "${LOG_ROOT}"; printf '%s\t%s\n' "$1" "$2" >> "${SUCCESSES}"; }

# --- Health assertions (L1 / L2 / L3) --------------------------------------------------------

# L1: the control plane is ACTIVE and a node is Ready. Not "terraform said ok".
check_l1() {
    local account="$1" name="$2" kc status ready
    status="$(AWS_PROFILE="${account}" aws eks describe-cluster --name "${name}" \
        --region "${PACKT_REGION}" --query 'cluster.status' --output text 2>/dev/null || echo MISSING)"
    [[ "${status}" == "ACTIVE" ]] || { printf 'L1 cluster status=%s' "${status}"; return 1; }
    kc="$(kubeconfig_file "${account}" "${name}")"
    ready="$(KUBECONFIG="${kc}" kubectl get nodes \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
        2>/dev/null | grep -c '^True$' || true)"
    [[ "${ready:-0}" -ge 1 ]] || { printf 'L1 no Ready node'; return 1; }
    return 0
}

# L2: the platform floor the VTT depends on. EKS has shipped no default StorageClass since 1.30, so
# without gp3 the claude-home PVC hangs Pending and the terminal never starts.
check_l2() {
    local account="$1" name="$2" kc isdefault phase ready
    kc="$(kubeconfig_file "${account}" "${name}")"
    isdefault="$(KUBECONFIG="${kc}" kubectl get storageclass gp3 \
        -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' \
        2>/dev/null || true)"
    [[ "${isdefault}" == "true" ]] || { printf 'L2 gp3 is not the default StorageClass'; return 1; }
    phase="$(KUBECONFIG="${kc}" kubectl -n workshop get pvc student-claude \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "${phase}" == "Bound" ]] || { printf 'L2 PVC student-claude phase=%s' "${phase:-missing}"; return 1; }
    ready="$(KUBECONFIG="${kc}" kubectl -n workshop get deploy web-terminal \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    [[ "${ready:-0}" -ge 1 ]] || { printf 'L2 web-terminal has no ready replica'; return 1; }
    return 0
}

# L3: the surface a student actually opens. Checked against the raw LB hostname, so a routing
# failure and a cluster failure stay distinguishable (the router has its own gate, L4).
check_l3() {
    local account="$1" name="$2" host code body
    host="$(cluster_lb_host "${account}" "${name}")"
    [[ -n "${host}" ]] || { printf 'L3 no LoadBalancer hostname assigned'; return 1; }
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://${host}/" 2>/dev/null || echo 000)"
    [[ "${code}" == "200" ]] || { printf 'L3 GET / returned %s' "${code}"; return 1; }
    body="$(curl -sS --max-time 15 "http://${host}/api/status" 2>/dev/null || true)"
    printf '%s' "${body}" | jq -e 'has("phase") and (.phase|type=="number")' >/dev/null 2>&1 \
        || { printf 'L3 /api/status did not parse with a numeric phase'; return 1; }
    return 0
}

health_one() {
    local account="$1" name="$2" why
    if ! why="$(check_l1 "${account}" "${name}")"; then printf '%s' "${why}"; return 1; fi
    if ! why="$(check_l2 "${account}" "${name}")"; then printf '%s' "${why}"; return 1; fi
    if ! why="$(check_l3 "${account}" "${name}")"; then printf '%s' "${why}"; return 1; fi
    return 0
}

# --- Bring one cluster up, all the way to a working terminal ---------------------------------

up_one() {
    local account="$1" name="$2" logf kc why i=0
    assert_ours "${name}"
    mkdir -p "${STATE_ROOT}/${account}" "${LOG_ROOT}/${account}"
    logf="${LOG_ROOT}/${account}/${name}.apply.log"

    # Idempotence: if it already exists and is healthy, do nothing. This is what makes the ladder
    # additive rather than three separate builds, and what lets us scale down and back up.
    if [[ -f "$(state_file "${account}" "${name}")" ]]; then
        write_kubeconfig "${account}" "${name}" >/dev/null 2>&1 || true
        if health_one "${account}" "${name}" >/dev/null 2>&1; then
            log "  ${name}: already healthy, skipping"
            record_ok "${account}" "${name}"
            return 0
        fi
        log "  ${name}: state exists but unhealthy, converging"
    fi

    if ! terraform -chdir="${CLUSTER_DIR}" apply -auto-approve -no-color -input=false \
            -state="$(state_file "${account}" "${name}")" \
            -var "name=${name}" -var "profile=${account}" -var "region=${PACKT_REGION}" \
            -var "vpc_id=${VPC_ID}" -var "private_subnet_ids=${SUBNETS_JSON}" \
            >"${logf}" 2>&1; then
        log "  ${name}: FAILED terraform apply (see ${logf})"
        record_fail "${account}" "${name}" "terraform-apply"
        return 1
    fi
    record_membership "${account}" "${name}"

    if ! kc="$(write_kubeconfig "${account}" "${name}")"; then
        log "  ${name}: FAILED to write kubeconfig"
        record_fail "${account}" "${name}" "kubeconfig"
        return 1
    fi
    if ! assert_cluster_identity "${account}" "${name}"; then
        record_fail "${account}" "${name}" "identity-check"
        return 1
    fi

    # The bootstrap chain: the LB controller (so the VTT Service becomes an internet-facing NLB and
    # not a Classic ELB), the default gp3 StorageClass, in-cluster Gitea seeded with the platform,
    # then the VTT itself.
    if ! KUBECONFIG="${kc}" AWS_PROFILE="${account}" AWS_REGION="${PACKT_REGION}" \
            EXPECT_CONTEXT="${name}" "${VTT_DIR}/apply.sh" \
            >"${LOG_ROOT}/${account}/${name}.vtt.log" 2>&1; then
        log "  ${name}: FAILED VTT bootstrap (see ${LOG_ROOT}/${account}/${name}.vtt.log)"
        record_fail "${account}" "${name}" "vtt-bootstrap"
        return 1
    fi

    # AWS access for the student terminal via Pod Identity. No key to mint, distribute or revoke.
    if ! KUBECONFIG="${kc}" AWS_PROFILE="${account}" AWS_REGION="${PACKT_REGION}" \
            "${VTT_DIR}/student-aws-creds.sh" "${name}" \
            >"${LOG_ROOT}/${account}/${name}.creds.log" 2>&1; then
        log "  ${name}: FAILED student AWS creds"
        record_fail "${account}" "${name}" "student-aws-creds"
        return 1
    fi

    # The NLB needs time to be assigned and to pass its target health checks before the surface
    # answers. Poll rather than sleeping a fixed guess.
    while (( i < 40 )); do
        if health_one "${account}" "${name}" >/dev/null 2>&1; then break; fi
        sleep 15
        i=$((i + 1))
    done
    if ! why="$(health_one "${account}" "${name}")"; then
        log "  ${name}: FAILED health after bootstrap: ${why}"
        record_fail "${account}" "${name}" "health:${why}"
        return 1
    fi

    log "  ${name}: UP  $(student_url "${name}")"
    record_ok "${account}" "${name}"
    return 0
}

# --- Tear one cluster down, in the order that actually works ---------------------------------

down_one() {
    local account="$1" name="$2" kc st
    assert_ours "${name}"
    st="$(state_file "${account}" "${name}")"
    [[ -f "${st}" ]] || { log "  ${name}: no state, skipping"; return 0; }
    assert_membership_matches "${account}" "${name}"
    mkdir -p "${LOG_ROOT}/${account}"

    kc="$(kubeconfig_file "${account}" "${name}")"
    if [[ -f "${kc}" ]] && KUBECONFIG="${kc}" kubectl get ns >/dev/null 2>&1; then
        # Drain first. Terraform does not own the load balancers Kubernetes created; skipping this
        # orphans ~2 LBs per cluster, and their ENIs hold the subnet so DeleteVpc fails later.
        # --wait blocks on the finalizer, which is removed only once the real AWS LB is gone.
        log "  ${name}: draining load balancers"
        KUBECONFIG="${kc}" kubectl delete svc -A --all \
            --field-selector spec.type=LoadBalancer --wait=true --timeout=150s >/dev/null 2>&1 || true
        KUBECONFIG="${kc}" kubectl delete ingress -A --all --wait=true --timeout=150s >/dev/null 2>&1 || true
        # Release dynamically-provisioned EBS while the CSI controller still exists to reclaim it.
        # Destroy the cluster first and those volumes orphan as 'available' and bill on.
        KUBECONFIG="${kc}" kubectl delete pvc -A --all --wait=false --timeout=60s >/dev/null 2>&1 || true
        sleep 10
    else
        log "  ${name}: cluster unreachable, proceeding straight to destroy"
    fi

    if ! terraform -chdir="${CLUSTER_DIR}" destroy -auto-approve -no-color -input=false \
            -state="${st}" \
            -var "name=${name}" -var "profile=${account}" -var "region=${PACKT_REGION}" \
            -var "vpc_id=${VPC_ID}" -var "private_subnet_ids=${SUBNETS_JSON}" \
            >"${LOG_ROOT}/${account}/${name}.destroy.log" 2>&1; then
        log "  ${name}: FAILED destroy (state kept for retry)"
        record_fail "${account}" "${name}" "terraform-destroy"
        return 1
    fi
    # Remove state only on success, so a failure stays retryable.
    rm -f "${st}" "${st}.backup" "$(membership_file "${account}" "${name}")" "${kc}"
    log "  ${name}: DOWN"
    record_ok "${account}" "${name}"
    return 0
}

# --- Concurrency -----------------------------------------------------------------------------

# A sliding window at MAX_PARALLEL. Workers record their own outcomes, so a worker that dies cannot
# be mistaken here for one that succeeded.
run_pool() {
    local fn="$1" account="$2"
    shift 2
    local name running=0 total=$# finished=0
    (( total > 0 )) || return 0
    for name in "$@"; do
        "${fn}" "${account}" "${name}" &
        running=$((running + 1))
        if (( running >= MAX_PARALLEL )); then
            wait -n 2>/dev/null || true
            running=$((running - 1))
            finished=$((finished + 1))
            log "  [${account}] ${finished}/${total}"
        fi
    done
    wait
    log "  [${account}] ${total}/${total} complete"
}

# --- Verbs -----------------------------------------------------------------------------------

cmd_vpc_up() {
    local target="${1:-}"
    [[ -n "${target}" ]] || usage
    require_tools
    terraform -chdir="${LAB_VPC_DIR}" init -input=false >/dev/null
    local account
    while read -r account; do
        assert_account "${account}"
        mkdir -p "${STATE_ROOT}/${account}" "${LOG_ROOT}/${account}"
        log "lab VPC: ${account}"
        terraform -chdir="${LAB_VPC_DIR}" apply -auto-approve -no-color -input=false \
            -state="$(vpc_state_file "${account}")" \
            -var "profile=${account}" -var "region=${PACKT_REGION}" \
            >"${LOG_ROOT}/${account}/lab-vpc.apply.log" 2>&1 \
            || die "lab VPC apply failed for ${account} (see ${LOG_ROOT}/${account}/lab-vpc.apply.log)"
        read_vpc_outputs "${account}"
        log "  ${account}: vpc=${VPC_ID}"
    done < <( [[ "${target}" == "all" ]] && accounts_list || printf '%s\n' "${target}" )
}

cmd_up() {
    local account="${1:-}" n="${2:-}"
    [[ -n "${account}" && "${n}" =~ ^[0-9]+$ ]] || usage
    require_tools
    assert_account "${account}"
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    read_vpc_outputs "${account}"
    local names
    mapfile -t names < <(account_names "${account}" "${n}")
    log "[${account}] target ${n} clusters (max ${MAX_PARALLEL} parallel)"
    run_pool up_one "${account}" "${names[@]}"
    cmd_report
}

cmd_up_fleet() {
    local n="${1:-}"
    [[ "${n}" =~ ^[0-9]+$ ]] || usage
    require_tools
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    local account
    # One subshell per account so VPC_ID and the profile cannot leak across pools.
    while read -r account; do
        assert_account "${account}"
        (
            read_vpc_outputs "${account}"
            local names
            mapfile -t names < <(account_names "${account}" "${n}")
            run_pool up_one "${account}" "${names[@]}"
        ) &
    done < <(accounts_list)
    wait
    cmd_report
}

cmd_health() {
    local target="${1:-all}" account name why fails=0
    while read -r account; do
        assert_account "${account}"
        while read -r name; do
            [[ -n "${name}" ]] || continue
            if why="$(health_one "${account}" "${name}")"; then
                printf 'OK   %-16s %-14s %s\n' "${account}" "${name}" "$(student_url "${name}")"
            else
                printf 'FAIL %-16s %-14s %s\n' "${account}" "${name}" "${why}"
                fails=$((fails + 1))
            fi
        done < <(known_clusters "${account}")
    done < <( [[ "${target}" == "all" ]] && accounts_list || printf '%s\n' "${target}" )
    [[ "${fails}" -eq 0 ]] || { log "${fails} cluster(s) failed health"; return 1; }
    log "all known clusters healthy"
}

cmd_status() {
    local account known live
    printf '%-16s %8s %8s\n' ACCOUNT KNOWN LIVE
    while read -r account; do
        known="$(known_clusters "${account}" | wc -l)"
        live="$(live_clusters "${account}" | wc -l)"
        printf '%-16s %8s %8s\n' "${account}" "${known}" "${live}"
    done < <(accounts_list)
}

cmd_report() {
    local ok=0 bad=0
    [[ -f "${SUCCESSES}" ]] && ok="$(wc -l < "${SUCCESSES}")"
    [[ -f "${FAILURES}" ]] && bad="$(wc -l < "${FAILURES}")"
    log "run ${RUN_ID}: ${ok} ok, ${bad} failed"
    if [[ "${bad}" -gt 0 ]]; then
        log "failures (${FAILURES}):"
        sed 's/^/    /' "${FAILURES}" >&2
        return 1
    fi
    return 0
}

cmd_down() {
    local account="${1:-}"
    shift || usage
    [[ -n "${account}" && $# -ge 1 ]] || usage
    assert_account "${account}"
    require_apply "destroy $* in ${account}" || return 0
    require_tools
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    read_vpc_outputs "${account}"
    run_pool down_one "${account}" "$@"
    cmd_report
}

cmd_down_fleet() {
    require_apply "destroy every known cluster in ${PACKT_ACCOUNTS}" || return 0
    require_tools
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    local account
    while read -r account; do
        (
            read_vpc_outputs "${account}"
            local names
            mapfile -t names < <(known_clusters "${account}")
            (( ${#names[@]} )) && run_pool down_one "${account}" "${names[@]}"
        ) &
    done < <(accounts_list)
    wait
    cmd_report
}

# Cost lever: destroy any cluster not in the claimed list from the claim app's /admin/export.
cmd_reap() {
    [[ "${1:-}" == "--keep" && -n "${2:-}" ]] || usage
    local keep="$2" account name
    [[ -f "${keep}" ]] || die "no such keep file: ${keep}"
    require_tools
    terraform -chdir="${CLUSTER_DIR}" init -input=false >/dev/null
    while read -r account; do
        local -a doomed=()
        while read -r name; do
            [[ -n "${name}" ]] || continue
            grep -qx "${name}" "${keep}" || doomed+=("${name}")
        done < <(known_clusters "${account}")
        (( ${#doomed[@]} )) || continue
        log "[${account}] reaping ${#doomed[@]}: ${doomed[*]}"
        if require_apply "reap ${#doomed[@]} in ${account}"; then
            (
                read_vpc_outputs "${account}"
                run_pool down_one "${account}" "${doomed[@]}"
            )
        fi
    done < <(accounts_list)
    cmd_report
}

cmd_routes() { "${FLEET_DIR}/routes.sh" "$@"; }
cmd_ingest() { "${FLEET_DIR}/ingest.sh" "$@"; }
cmd_sweep() { "${FLEET_DIR}/sweep.sh" "$@"; }
cmd_preflight() { "${FLEET_DIR}/preflight.sh" "$@"; }

main() {
    local cmd="${1:-}"
    shift || true
    case "${cmd}" in
        preflight)  cmd_preflight "$@" ;;
        vpc-up)     cmd_vpc_up "$@" ;;
        up)         cmd_up "$@" ;;
        up-fleet)   cmd_up_fleet "$@" ;;
        health)     cmd_health "$@" ;;
        routes)     cmd_routes "$@" ;;
        ingest)     cmd_ingest "$@" ;;
        status)     cmd_status "$@" ;;
        down)       cmd_down "$@" ;;
        down-fleet) cmd_down_fleet "$@" ;;
        reap)       cmd_reap "$@" ;;
        sweep)      cmd_sweep "$@" ;;
        *)          usage ;;
    esac
}

main "$@"
