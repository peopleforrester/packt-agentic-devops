#!/usr/bin/env bash
# ABOUTME: Runs the phase gate tests against a live cluster. This is the E2E command declared in
# ABOUTME: AGENTS.md. It refuses to run without a cluster instead of passing on skipped tests.
#
# Without KUBECONFIG_FILE every cluster-bound test skips itself and pytest exits 0, so a run with no
# cluster would report the phase gates as passed. tests/conftest.py aborts when the current context
# does not contain EXPECTED_CONTEXT, which is why both must be set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -z "${KUBECONFIG_FILE:-}" || -z "${EXPECTED_CONTEXT:-}" ]]; then
    printf 'KUBECONFIG_FILE and EXPECTED_CONTEXT must both be set; see tests/README.md\n' >&2
    exit 1
fi

uv run --with pytest --with pyyaml --with jsonschema --with requests python -m pytest -q tests/
