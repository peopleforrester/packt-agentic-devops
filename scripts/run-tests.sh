#!/usr/bin/env bash
# ABOUTME: Runs every cluster-free test in the repo: the platform suite and the distribution app's
# ABOUTME: own suite. This is the light Test command declared in AGENTS.md.
#
# One script instead of a chained command line: the gate that runs the declared command passes it
# straight to exec without a shell, so `&&` reached pytest as an argument. The distribution app runs
# in its own uv project because it carries its own dependencies, and pyproject.toml keeps it out of
# the root collection.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

uv run --with pytest --with pyyaml --with jsonschema --with requests python -m pytest -q
uv run --directory scripts/provision/distribution --frozen pytest
