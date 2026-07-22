#!/usr/bin/env bash
# ABOUTME: L5 gate. Claims a cluster through the real distribution app and proves the URL it hands
# ABOUTME: back is the same live cluster the fleet built, then proves the claim is idempotent.
#
# This is the assertion no other layer covers. The clusters can all be healthy and the app can be
# up, and the workshop still fails if a pool row points at a cluster that is dead, wrong, or handed
# to two people. So the last step here follows the returned URL and re-runs the L3 checks against it.
#
# Claiming consumes a pool slot. That is acceptable during a rehearsal run whose pool is rebuilt
# from scratch afterwards; do not run this against a pool that is already serving attendees.
set -euo pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "${FLEET_DIR}/lib.sh"

readonly APP="${CLAIM_APP:-https://packt.ai-enhanced-devops.com}"
readonly DIST_SERVICE="packt-provisioning"
# A distinctive address so a test claim is obvious in the export and easy to reconcile later.
EMAIL="${CLAIM_TEST_EMAIL:-fleet-gate-$(date -u +%Y%m%d%H%M%S)@ai-enhanced-devops.com}"
readonly EMAIL

FAILS=0
fail() { printf '  FAIL  %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
pass() { printf '  ok    %s\n' "$*" >&2; }

# The railway CLI resolves its project from the working directory, so this must run inside the
# linked service directory. It also must not abort the whole test: under `set -e` with pipefail a
# failed railway call kills the script mid-run and the gate reports "failed" with no reason printed.
admin_token() {
    ( cd "${PROVISION_DIR}/distribution" 2>/dev/null \
        && railway variables --service "${DIST_SERVICE}" --kv 2>/dev/null ) \
        | sed -n 's/^ADMIN_TOKEN=//p' | head -1 || true
}

expected_pool_size() {
    local account total=0
    while read -r account; do
        total=$((total + $(known_clusters "${account}" | wc -l)))
    done < <(accounts_list)
    printf '%s' "${total}"
}

main() {
    printf '[L5] claim flow against %s\n' "${APP}" >&2
    local code token body url1 url2 want

    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "${APP}/healthz" 2>/dev/null)" || true
    [[ "${code}" == "200" ]] && pass "/healthz -> 200" || fail "/healthz -> ${code}"

    token="$(admin_token)"
    if [[ -z "${token}" ]]; then
        fail "could not read ADMIN_TOKEN from the ${DIST_SERVICE} service"
    else
        want="$(expected_pool_size)"
        body="$(curl -sS --max-time 20 "${APP}/admin?token=${token}" || true)"
        # Read the Total stat specifically. Grepping the whole page for the bare number matches any
        # digit anywhere (the Claimed count, a region, a timestamp) and so passes for the wrong
        # reason, which is worse than failing: this check exists to catch a pool that does not
        # describe the fleet.
        local total
        total="$(printf '%s' "${body}" \
            | tr -d '\n' \
            | sed -n 's/.*<div class="label">Total<\/div>[[:space:]]*<div class="value">\([0-9]*\).*/\1/p')"
        if [[ "${total}" == "${want}" ]]; then
            pass "/admin reports Total=${total}, matching the ${want} clusters built"
        else
            fail "/admin reports Total='${total:-unreadable}', expected ${want} (a mismatched pool hands out dead clusters)"
        fi
    fi

    # First claim: a fresh email must receive a cluster URL on our own domain.
    body="$(curl -sS --max-time 30 -X POST -d "email=${EMAIL}" "${APP}/eks-claim" || true)"
    if printf '%s' "${body}" | grep -q "exhausted\|no clusters"; then
        fail "claim returned the exhausted page; the pool is empty or unseeded"
        printf '[L5] FAILED (%d)\n' "$((FAILS + 1))" >&2
        exit 1
    fi
    url1="$(printf '%s' "${body}" | grep -oE "https://student[0-9]+\.${PACKT_DOMAIN}[^\"'< ]*" | head -1)"
    if [[ -n "${url1}" ]]; then
        pass "claim returned ${url1}"
    else
        fail "claim did not return a student URL on ${PACKT_DOMAIN}"
    fi

    # Second claim, same email: must return the SAME cluster. Without this, a returning attendee is
    # handed a different cluster and two attendees can end up on one.
    body="$(curl -sS --max-time 30 -X POST -d "email=${EMAIL}" "${APP}/eks-claim" || true)"
    url2="$(printf '%s' "${body}" | grep -oE "https://student[0-9]+\.${PACKT_DOMAIN}[^\"'< ]*" | head -1)"
    if [[ -n "${url1}" && "${url1}" == "${url2}" ]]; then
        pass "re-claim is idempotent (same cluster)"
    else
        fail "re-claim returned '${url2}', expected '${url1}'"
    fi

    # The assertion that ties the pool to reality: the URL the app handed out must serve.
    if [[ -n "${url1}" ]]; then
        local host base
        host="$(printf '%s' "${url1}" | sed -E 's|https://([^/]+).*|\1|')"
        base="https://${host}"
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "${base}/" 2>/dev/null)" || true
        [[ "${code}" == "200" ]] && pass "claimed URL serves 200" || fail "claimed URL -> ${code}"
        if curl -sS --max-time 25 "${base}/api/status" 2>/dev/null \
                | jq -e 'has("phase") and (.phase|type=="number")' >/dev/null 2>&1; then
            pass "claimed cluster /api/status parses with a numeric phase"
        else
            fail "claimed cluster /api/status did not parse"
        fi
    fi

    printf '  note  test claim used %s; the pool is reseeded on the next ingest\n' "${EMAIL}" >&2
    if [[ "${FAILS}" -gt 0 ]]; then
        printf '[L5] FAILED (%d)\n' "${FAILS}" >&2
        exit 1
    fi
    printf '[L5] PASSED\n' >&2
}

main
