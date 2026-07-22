#!/usr/bin/env bash
# ABOUTME: L6 continuous watch. Re-checks every student surface on a fixed cadence and prints one
# ABOUTME: line per STATE CHANGE, so silence means healthy and any output is something that moved.
#
# Design rule learned the hard way: the filter must match failure signatures, not just successes, or
# a crash-looping cluster reads identically to a healthy one. Silence only means healthy if failures
# are guaranteed to print, so every transition in either direction is emitted.
#
# Sampling, per 04-verification-tests.md: HTTP checks run against every cluster every cycle because
# they are cheap and they are the student's actual reality. The AWS API is consulted only to explain
# a failure the HTTP check already found, which keeps 250 clusters from throttling the EKS API.
set -euo pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "${FLEET_DIR}/lib.sh"

readonly INTERVAL="${WATCH_INTERVAL:-180}"
readonly PARALLEL="${WATCH_PARALLEL:-25}"
STATE_CACHE="$(mktemp)"
readonly STATE_CACHE
trap 'rm -f "${STATE_CACHE}" "${STATE_CACHE}.new"' EXIT

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Probe one hostname. Prints "<name> <ok|FAIL:reason>".
probe() {
    local name="$1" host code body
    host="${name}.${PACKT_DOMAIN}"
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${host}/" 2>/dev/null)" || true
    if [[ "${code}" != "200" ]]; then
        printf '%s FAIL:http-%s\n' "${name}" "${code}"
        return
    fi
    body="$(curl -sS --max-time 20 "https://${host}/api/status" 2>/dev/null || true)"
    if ! printf '%s' "${body}" | jq -e 'has("phase") and (.phase|type=="number")' >/dev/null 2>&1; then
        printf '%s FAIL:status-unparseable\n' "${name}"
        return
    fi
    printf '%s ok\n' "${name}"
}
export -f probe
export PACKT_DOMAIN

main() {
    printf '%s L6 watch starting: every %ss, %s at a time\n' "$(stamp)" "${INTERVAL}" "${PARALLEL}" >&2
    : > "${STATE_CACHE}"
    local first=1

    while :; do
        local names account name expected live
        names="$(mktemp)"
        while read -r account; do
            known_clusters "${account}" >> "${names}"
        done < <(accounts_list)
        expected="$(wc -l < "${names}")"

        xargs -a "${names}" -P "${PARALLEL}" -I{} bash -c 'probe "$@"' _ {} \
            2>/dev/null | sort > "${STATE_CACHE}.new"
        rm -f "${names}"

        # Fleet size drift: a cluster that vanished from the driver's own inventory never gets
        # probed, so count it separately rather than inferring health from an empty failure list.
        live=0
        while read -r account; do
            live=$((live + $(live_clusters "${account}" | wc -l)))
        done < <(accounts_list)
        if [[ "${live}" -ne "${expected}" ]]; then
            printf '%s DRIFT expected=%s live=%s\n' "$(stamp)" "${expected}" "${live}" >&2
        fi

        if [[ -n "${first}" ]]; then
            local bad
            bad="$(grep -c ' FAIL:' "${STATE_CACHE}.new" || true)"
            printf '%s baseline: %s clusters, %s failing\n' "$(stamp)" "${expected}" "${bad:-0}" >&2
            grep ' FAIL:' "${STATE_CACHE}.new" | sed "s/^/$(stamp) DOWN /" >&2 || true
            first=""
        else
            # Emit only transitions, in both directions.
            join -j1 -a1 -a2 -e MISSING -o 0,1.2,2.2 "${STATE_CACHE}" "${STATE_CACHE}.new" \
                2>/dev/null | while read -r name was now; do
                [[ "${was}" == "${now}" ]] && continue
                if [[ "${now}" == ok ]]; then
                    printf '%s RECOVERED %s (was %s)\n' "$(stamp)" "${name}" "${was}" >&2
                else
                    printf '%s DOWN %s %s\n' "$(stamp)" "${name}" "${now}" >&2
                fi
            done
        fi

        mv "${STATE_CACHE}.new" "${STATE_CACHE}"
        sleep "${INTERVAL}"
    done
}

main
