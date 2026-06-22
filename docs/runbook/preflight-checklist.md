# Preflight Checklist

The 9:30 AM EDT event-day ritual, 90 minutes before the 11:00 AM start. Most of this is `scripts/preflight.sh`, which exits nonzero on any failure. Run it against the primary and the hot spare, then clear the manual items.

## Run the script (primary, then spare)

Each cluster uses an explicit kubeconfig file, never the ambient context (this is a shared machine).

```bash
KUBECONFIG_FILE=/tmp/primary.kubeconfig EXPECTED_CONTEXT=<primary-arn-substr> \
GHCR_ORG=peopleforrester BACKUP_VIDEO_DIR=<path> \
REQUIRED_ENV_VARS="<presenter vars>" \
scripts/preflight.sh

# then the same with /tmp/spare.kubeconfig and the spare context substring
```

A clean run prints `== preflight PASSED ==`. Any `FAIL` line stops the event prep until cleared.

## What each check means and the fix

- [ ] **Cluster reachable, context matches.** `get nodes` succeeds on the expected context. Fail: wrong kubeconfig or a cluster that did not come up. Fix: repoint the kubeconfig; if the cluster is bad, promote the spare to primary.
- [ ] **ArgoCD all Synced and Healthy.** Every Application Synced and Healthy at the start state. Fail: a drifted or degraded app. Fix: reset to `checkpoint/module-0-start` and re-sync.
- [ ] **Checkpoint tags present.** `module-0-start`, `module-1-end`, `module-2-end`, `module-3-end` all resolve. Fail: a missing tag breaks the reset scripts. Fix: re-tag from the known-good commit before going live.
- [ ] **Image mirror complete.** Every image in `image-map.tsv` resolves in GHCR. Fail: a missing mirror means a live pull (forbidden). Fix: re-run `scripts/mirror-images.sh`.
- [ ] **vLLM InferenceService Ready.** The model server reports Ready. Fail: model not warm, the inference beat will stall. Fix: wait for it to finish loading the baked weights, or restart the predictor and re-check.
- [ ] **Presenter env vars present.** Existence only, values never printed. Fail: a missing key breaks the presenter cloud route. Fix: load the env file before OBS starts.
- [ ] **Backup videos present.** At least the per-beat `.mp4` files exist at the expected path. Fail: no safety net for a beat. Fix: place the recordings; verify the per-beat checklist.

## Manual items (not auto-checked)

- [ ] **Hot spare synced to `checkpoint/module-0-start`** and `promote-spare.sh` tested within the last day (target under 60 seconds).
- [ ] **OBS scenes loaded** and the correct opening scene is live. The script surfaces this as a `MANUAL` line.
- [ ] **Backup video checklist** reviewed: every beat ID has a file that plays.
- [ ] **Attendee distribution** ready: credential pool loaded, the distribution app reachable.

When the script passes on both clusters and the manual items are clear, the build is the least risky thing on the schedule.
