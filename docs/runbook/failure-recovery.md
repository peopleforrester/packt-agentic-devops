# Failure Recovery

What to do when a beat goes wrong on screen.

## Principles

- Every beat has three safety layers: a checkpoint to reset to, a reset script under 5 minutes, and a recorded backup of the exact beat.
- The only sanctioned on-screen failure is B03, the scripted Grafana sync error. It is rehearsed until boring.
- Any beat over budget by 50 percent triggers its bail-out. Play the recording, verify the cluster between beats, move on. The audience never watches unrehearsed troubleshooting.

## Recovery paths (the three moves)

- **Reset to a checkpoint:** `scripts/reset/reset-to-checkpoint.sh <tag>` re-points the App-of-Apps to the tag, force-syncs with prune, verifies app health. Under 5 minutes. The checkpoint tags are immutable known-good revisions of the frozen platform, so a reset recovers a broken or drifted foundation to a verified state rather than stripping a later module.
- **Promote the hot spare:** `promote-spare.sh` swaps the presenter kubeconfig and Backstage URL to the pre-synced spare, under 60 seconds. This is the move for a dead control plane.
- **Continue from recordings:** when the agent or the API is unavailable, play the beat recording and verify the live cluster between modules.

## Per-failure playbooks

### A foundation or AI-plane app will not sync (not B03)
- Symptom: an Application stuck Progressing or Degraded past its budget.
- Decision: this is not the rehearsed failure; do not debug live.
- Action: at 50 percent over budget, play the plane-green recording and pick up at the next beat. Between modules, reset to the last checkpoint and re-sync.

### vLLM inference is cold or slow (B11)
- Symptom: first token does not appear within the gate.
- Action: reveal the pre-warmed request that was fired during B10. The model is warm by preflight; never let a cold inference sit on screen.
- If the predictor crashed: promote the spare (its model is warm) rather than reload live.

### Backstage is down or slow (B04, B15)
- Symptom: the portal does not load or the golden-path form hangs.
- Action: `promote-spare.sh` swaps to the spare's Backstage URL. For B15 specifically, if any link in the chain stalls past budget, cut to the recorded golden-path take.

### The golden path stalls mid-chain (B15)
- Symptom: scaffold, ApplicationSet detection, sync, or trace does not complete.
- Action: it is rehearsed as one continuous take; if it stalls, play the recorded take. Do not debug the chain on screen.

### Kyverno admits the violating fixture (B16)
- Symptom: the violating agent applies instead of being denied.
- Cause: policies still in audit, not enforce.
- Action: confirm enforce mode and re-apply the fixture, or play the denial recording.

### The audit query returns nothing (B17)
- Symptom: no per-agent lines in Loki.
- Cause: the audit hook did not ship, or the label filter is wrong.
- Action: use the rehearsal screenshot fallback. Verify the hook during preflight so this does not happen.

### Primary cluster failure mid-session
- Symptom: the primary control plane is unreachable.
- Action: `promote-spare.sh`. The spare is pre-synced to `checkpoint/module-0-start` and carries warm images and a warm model. This is why the spare is non-negotiable.

### Agent or API outage
- Symptom: the building agent cannot run a prompt.
- Action: degraded mode. Continue the modules from the per-beat recordings, verifying the live cluster between modules. Backup recordings cover every agent-dependent beat.

## After the event

Each rehearsal adds the real failure modes it surfaces to the playbooks above, with the recovery that worked. The second rehearsal should surface nothing new.
