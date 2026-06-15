# Failure Recovery

What to do when a beat goes wrong on screen. Built in Phase 6.

## Principles

- Every beat has three safety layers: a checkpoint to reset to, a reset script under 5 minutes, and a recorded backup of the exact beat.
- The only sanctioned on-screen failure is B03, the scripted Grafana sync error. It is rehearsed until boring.
- Any beat over budget by 50 percent triggers its bail-out. Play the recording, verify the cluster between beats, move on.

## Recovery paths

- Reset to a checkpoint: `scripts/reset/reset-to-<checkpoint>.sh` (Phase 6).
- Promote the hot spare: `promote-spare.sh`, under 60 seconds (Phase 6).
- Anthropic API outage: continue from recordings, with live cluster verification between modules.

Per-failure playbooks are filled in Phase 6 as rehearsals surface the real failure modes.
