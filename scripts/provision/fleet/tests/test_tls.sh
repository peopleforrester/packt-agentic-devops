#!/usr/bin/env bash
# ABOUTME: L4 gate for one student hostname: valid certificate chain, correct SAN, HTTPS serving,
# ABOUTME: plain HTTP redirecting, and a websocket that upgrades over wss.
#
# The websocket assertion is the one that actually protects the workshop. Corporate proxies block
# plain ws:// far more often than wss://, and because the terminal is a same-origin iframe, HTTPS
# on the hostname is what upgrades the socket. So this test really asserts "the hostname is HTTPS",
# end to end, from outside.
set -euo pipefail

readonly HOST="${1:-}"
# The certificate must outlive the event by a margin, not merely be valid right now.
readonly EVENT_DATE="${EVENT_DATE:-2026-07-23}"
readonly MIN_DAYS="${MIN_DAYS:-7}"

FAILS=0

usage() { printf 'Usage: %s <hostname>\n' "${0##*/}" >&2; exit 2; }
[[ -n "${HOST}" ]] || usage

fail() { printf '  FAIL  %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
pass() { printf '  ok    %s\n' "$*" >&2; }

check_certificate() {
    local cert notafter notafter_epoch need_epoch
    if ! cert="$(echo | timeout 20 openssl s_client -connect "${HOST}:443" -servername "${HOST}" \
            2>/dev/null | openssl x509 -noout -text 2>/dev/null)"; then
        fail "${HOST}: no TLS handshake"
        return
    fi

    # Chain validation is a separate call: -verify_return_error makes a bad chain a non-zero exit
    # rather than a warning buried in the handshake output.
    if echo | timeout 20 openssl s_client -connect "${HOST}:443" -servername "${HOST}" \
            -verify_return_error >/dev/null 2>&1; then
        pass "${HOST}: certificate chain validates"
    else
        fail "${HOST}: certificate chain does NOT validate"
    fi

    # The wildcard must actually cover this host. One cert serves all 250 hostnames, so a SAN that
    # does not match is a fleet-wide failure, not a per-cluster one.
    if printf '%s' "${cert}" | grep -A1 "Subject Alternative Name" | grep -qE "DNS:\*\.|DNS:${HOST}"; then
        pass "${HOST}: SAN covers the hostname"
    else
        fail "${HOST}: SAN does not cover the hostname"
    fi

    notafter="$(echo | timeout 20 openssl s_client -connect "${HOST}:443" -servername "${HOST}" \
        2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
    if [[ -n "${notafter}" ]]; then
        notafter_epoch="$(date -d "${notafter}" +%s 2>/dev/null || echo 0)"
        need_epoch="$(date -d "${EVENT_DATE} + ${MIN_DAYS} days" +%s)"
        if (( notafter_epoch > need_epoch )); then
            pass "${HOST}: certificate valid until ${notafter}"
        else
            fail "${HOST}: certificate expires ${notafter}, inside ${MIN_DAYS} days of the event"
        fi
    else
        fail "${HOST}: could not read certificate expiry"
    fi
}

check_https() {
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${HOST}/" 2>/dev/null)" || true
    [[ "${code}" == "200" ]] && pass "${HOST}: GET https:// -> 200" || fail "${HOST}: GET https:// -> ${code}"

    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${HOST}/api/status" 2>/dev/null)" || true
    [[ "${code}" == "200" ]] && pass "${HOST}: /api/status -> 200" || fail "${HOST}: /api/status -> ${code}"
}

check_http_redirects() {
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "http://${HOST}/" 2>/dev/null)" || true
    case "${code}" in
        301|302|307|308) pass "${HOST}: http:// redirects (${code})" ;;
        200) fail "${HOST}: http:// serves 200 instead of redirecting to https" ;;
        *) fail "${HOST}: http:// -> ${code}" ;;
    esac
}

check_websocket() {
    # ttyd sits behind nginx at /terminal/. A successful upgrade answers 101; anything else means
    # the socket will not open in the student's browser.
    local key resp
    key="$(openssl rand -base64 16)"
    # --http1.1 is required. Over an ALPN-negotiated HTTP/2 connection the upgrade handshake is not
    # valid and the edge answers 404, which reads as a broken terminal when the terminal is fine.
    # Browsers open websockets over HTTP/1.1 too, so this matches what a student actually does.
    resp="$(curl -sS -i --max-time 20 --http1.1 \
        -H "Connection: Upgrade" -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: ${key}" \
        -H "Sec-WebSocket-Protocol: tty" \
        "https://${HOST}/terminal/ws" 2>/dev/null | head -1 || true)"
    if printf '%s' "${resp}" | grep -q "101"; then
        pass "${HOST}: wss:// upgrade returns 101"
    else
        fail "${HOST}: wss:// upgrade did not return 101 (got: ${resp:-nothing})"
    fi
}

main() {
    printf '[L4 TLS] %s\n' "${HOST}" >&2
    check_certificate
    check_https
    check_http_redirects
    check_websocket
    if [[ "${FAILS}" -gt 0 ]]; then
        printf '[L4 TLS] %s FAILED (%d)\n' "${HOST}" "${FAILS}" >&2
        exit 1
    fi
    printf '[L4 TLS] %s PASSED\n' "${HOST}" >&2
}

main
