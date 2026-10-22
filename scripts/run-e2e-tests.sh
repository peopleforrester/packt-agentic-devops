#!/usr/bin/env bash
# ABOUTME: Runs the phase gate tests against a live cluster, by hand after a build. It refuses to
# ABOUTME: run without a cluster instead of passing on skipped tests.
#
# AGENTS.md declares no E2E command: the gate host has no cluster, so these run by hand (see
# decisions.md, question 552).
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
