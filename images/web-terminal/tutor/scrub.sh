#!/bin/bash
# ABOUTME: Redacts obvious secret shapes from text on stdin, so a terminal transcript can be sent to the
# ABOUTME: tutor model or shown in a nudge without leaking AWS keys, tokens, passwords, or JWTs.
sed -E \
 -e 's/(AKIA|ASIA)[A-Z0-9]{16}/[REDACTED-AWS-KEY]/g' \
 -e 's/(aws_secret_access_key[[:space:]]*=[[:space:]]*)[A-Za-z0-9\/+=]{40}/\1[REDACTED]/g' \
 -e 's/(secret|token|password|passwd|api[_-]?key|bearer)([":= ]+)[^[:space:]"'\'']+/\1\2[REDACTED]/gI' \
 -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[REDACTED-JWT]/g'
