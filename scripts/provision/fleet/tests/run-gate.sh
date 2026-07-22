#!/usr/bin/env bash
# ABOUTME: The stage gate. Runs the right subset of L0-L5 for s1, s2 or s3 and exits non-zero on any
# ABOUTME: failure, so widening the fleet is a script's decision and never a judgement call.
#
# A gate that "mostly passed" is the most expensive kind of pass, so every check here asserts a
# property from outside and reports the observed value when it fails.
set -euo pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "${FLEET_DIR}/lib.sh"

STAGE="${1:-}"
FAILS=0
# TLS handshakes are slow one at a time; at 250 hostnames they must run concurrently.
readonly TLS_PARALLEL="${TLS_PARALLEL:-20}"

usage() { printf 'Usage: %s <s1|s2|s3>\n' "${0##*/}" >&2; exit 2; }
[[ "${STAGE}" =~ ^s[123]$ ]] || usage

section() { printf '\n=== %s ===\n' "$*" >&2; }
fail() { printf '  FAIL  %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
pass() { printf '  ok    %s\n' "$*" >&2; }

expected_for() {
    local account="$1"
    case "${STAGE}" in
        s1) printf '1' ;;
        s2) [[ "${account}" == "accen-dev" ]] && printf '50' || printf '1' ;;
        s3) printf '%s' "${PACKT_BLOCK}" ;;
    esac
}

# --- L0 ---------------------------------------------------------------------------------------
gate_preflight() {
    section "L0 preflight (${STAGE})"
    if "${FLEET_DIR}/preflight.sh" "${STAGE}" >/dev/null 2>&1; then
        pass "preflight passed for ${STAGE}"
    else
        fail "preflight failed; re-run scripts/provision/fleet/preflight.sh ${STAGE}"
    fi
}

# --- Fleet size -------------------------------------------------------------------------------
gate_size() {
    section "Fleet size"
    local account want live
    while read -r account; do
        want="$(expected_for "${account}")"
        live="$(live_clusters "${account}" | wc -l)"
        if [[ "${live}" -eq "${want}" ]]; then
            pass "${account}: ${live}/${want} clusters live"
        else
            fail "${account}: ${live} clusters live, expected ${want}"
        fi
    done < <(accounts_list)
}

# --- Account isolation and membership (D5, D6) ------------------------------------------------
# The bug class this catches: a VPC id or profile leaking across the per-account subshells, which
# silently builds a cluster in the wrong account and is invisible from the cluster itself.
# One list-clusters per account (5 calls), then set comparison. The obvious implementation is a
# describe-cluster per cluster per account, which is 1,250 sequential calls at full size: slow
# enough to matter and likely to throttle, which would then be misread as an isolation failure.
# Listing once per account is both faster and strictly stronger, because it sees clusters the
# driver has no state for.
gate_isolation() {
    section "Account isolation and membership"
    local account other name recorded tmp
    tmp="$(mktemp -d)"
    while read -r account; do
        live_clusters "${account}" | sort > "${tmp}/${account}.live"
        known_clusters "${account}" | sort > "${tmp}/${account}.known"
    done < <(accounts_list)

    while read -r account; do
        # Every cluster the driver claims for this account must actually be here.
        while read -r name; do
            [[ -n "${name}" ]] || continue
            recorded="$(read_membership "${account}" "${name}" 2>/dev/null || true)"
            [[ "${recorded}" == "${account}" ]] \
                || fail "${name}: membership file says '${recorded}', expected ${account}"
            grep -qx "${name}" "${tmp}/${account}.live" \
                || fail "${name}: recorded in ${account} but not live there"
            # ...and in no other account.
            while read -r other; do
                [[ "${other}" == "${account}" ]] && continue
                grep -qx "${name}" "${tmp}/${other}.live" \
                    && fail "${name}: ALSO exists in ${other}; account isolation broken"
            done < <(accounts_list)
        done < <(known_clusters "${account}")

        # And every fleet-named cluster live in this account must be one we know about. A cluster
        # nobody has state for is unmanaged: it bills, and no teardown will ever remove it.
        while read -r name; do
            [[ -n "${name}" ]] || continue
            grep -qx "${name}" "${tmp}/${account}.known" \
                || fail "${name}: live in ${account} with no driver state (unmanaged, will not tear down)"
        done < "${tmp}/${account}.live"

        pass "${account}: $(wc -l < "${tmp}/${account}.known") cluster(s) placed correctly"
    done < <(accounts_list)
    rm -rf "${tmp}"
}

# --- L1-L3 ------------------------------------------------------------------------------------
gate_health() {
    section "L1-L3 cluster and student surface"
    if "${FLEET_DIR}/fleet.sh" health all; then
        pass "all clusters passed L1-L3"
    else
        fail "one or more clusters failed L1-L3 (see the FAIL lines above)"
    fi
}

# --- L4 ---------------------------------------------------------------------------------------
gate_tls() {
    section "L4 TLS per hostname"
    local account name hosts
    hosts="$(mktemp)"
    while read -r account; do
        while read -r name; do
            [[ -n "${name}" ]] || continue
            printf '%s.%s\n' "${name}" "${PACKT_DOMAIN}" >> "${hosts}"
        done < <(known_clusters "${account}")
    done < <(accounts_list)

    local total; total="$(wc -l < "${hosts}")"
    if [[ "${total}" -eq 0 ]]; then
        fail "no hostnames to check"
        rm -f "${hosts}"
        return
    fi
    printf '  checking %s hostname(s), %s at a time\n' "${total}" "${TLS_PARALLEL}" >&2
    local bad=0
    if ! xargs -a "${hosts}" -P "${TLS_PARALLEL}" -I{} "${FLEET_DIR}/tests/test_tls.sh" {} \
            >"${hosts}.out" 2>&1; then
        bad=1
    fi
    grep -c '^  FAIL' "${hosts}.out" >/dev/null 2>&1 && bad=1
    if [[ "${bad}" -eq 0 ]]; then
        pass "all ${total} hostnames passed L4"
    else
        fail "$(grep -c '^  FAIL' "${hosts}.out" || echo '?') L4 assertion(s) failed"
        grep '^  FAIL' "${hosts}.out" | head -20 >&2 || true
    fi
    rm -f "${hosts}" "${hosts}.out"
}

# --- L5 ---------------------------------------------------------------------------------------
gate_claim() {
    section "L5 claim flow"
    if "${FLEET_DIR}/tests/test_claim.sh"; then
        pass "claim flow verified"
    else
        fail "claim flow failed"
    fi
}

main() {
    printf 'Stage gate: %s\n' "${STAGE}" >&2
    gate_preflight
    gate_size
    gate_isolation
    gate_health
    gate_tls
    gate_claim

    printf '\n' >&2
    if [[ "${FAILS}" -gt 0 ]]; then
        printf 'GATE %s FAILED: %d problem(s). Do NOT widen the fleet.\n' "${STAGE}" "${FAILS}" >&2
        exit 1
    fi
    printf 'GATE %s PASSED.\n' "${STAGE}" >&2
}

main
