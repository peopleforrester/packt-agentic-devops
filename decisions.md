# Decisions

Decisions taken while running this repo's work through hecaton. The platform's own architecture decisions live in `docs/reference/decisions.md`.

## question 552: no E2E command line (issue #48)

Date: 2026-10-22

Question: the heavy gate ran `bash scripts/run-e2e-tests.sh`, which needs a live, fully built EKS platform cluster (`KUBECONFIG_FILE` plus `EXPECTED_CONTEXT`). The gate host has no cluster, so the gate was always red and main could not follow staging. How should this repo's heavy gate work?

Answer: remove the `E2E command:` line from AGENTS.md, so the heavy gate does not run the live-cluster phase gates for this repo. They stay a manual step after a build, as `tests/README.md` describes.

Decided by: hecaton's research under Michael's standing rules, not by Michael.

What it changes: AGENTS.md declares only `Test command: bash scripts/run-tests.sh`, and main is gated on that command and CI. `scripts/run-e2e-tests.sh` stays as the manual runner for the phase gates against a cluster someone has built, and it still exits 1 when `KUBECONFIG_FILE` or `EXPECTED_CONTEXT` is unset. No platform cluster is kept running for a gate, because that would be ongoing AWS spend.
