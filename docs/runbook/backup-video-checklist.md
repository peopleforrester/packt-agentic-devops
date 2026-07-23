# Backup Video Checklist

The recording contract (deliverable D10). One row per beat. Recording is Michael's task; this file is the list it must satisfy. Every beat that runs on screen has a backup so any beat can go to recording the moment it exceeds its bail-out budget.

## Rules

- Filename scheme: `backup-<beatID>-<short-slug>.mp4`, lowercase, in the backup video directory `preflight.sh` checks.
- Target duration is the run-of-show time budget for that beat. A recording that runs long defeats the bail-out; keep it at or under budget.
- Record the rehearsed, known-good run, not a first take. The recording is the safety net, so it must show the clean path.
- Fill the recorded date and check verified-plays only after watching the file play start to finish from the backup directory.
- Priority order to record first: the never-cut beats (B07, B08, B09), then the golden path (B15), then the rest.

## Module 1: cloud-native foundation

| Beat | Prompt | Filename | Target | Recorded | Verified plays |
|---|---|---|---|---|---|
| B01 | P01 | `backup-B01-explain-components.mp4` | 6 min | | [ ] |
| B02 | P02 | `backup-B02-foundation-sync.mp4` | 20 min | | [ ] |
| B04 | (presenter) | `backup-B04-backstage-tour.mp4` | 8 min | | [ ] |

## Module 2: the AI plane

| Beat | Prompt | Filename | Target | Recorded | Verified plays |
|---|---|---|---|---|---|
| B05 | P05 | `backup-B05-kgateway.mp4` | 8 min | | [ ] |
| B06 | P06 | `backup-B06-agentgateway.mp4` | 6 min | | [ ] |
| B07 | P07 | `backup-B07-kagent-crd.mp4` | 12 min | | [ ] |
| B08 | P08 | `backup-B08-mcp-call.mp4` | 6 min | | [ ] |
| B09 | P09 | `backup-B09-injection-block.mp4` | 6 min | | [ ] |
| B10 | P10 | `backup-B10-tempo-trace.mp4` | 8 min | | [ ] |
| B11 | P11 | `backup-B11-vllm-inference.mp4` | 6 min | | [ ] |
| B12 | (architecture) | `backup-B12-llmd-architecture.mp4` | 5 min | | [ ] |

## Module 3: self-service

| Beat | Prompt | Filename | Target | Recorded | Verified plays |
|---|---|---|---|---|---|
| B13 | P13 | `backup-B13-scaffolder-template.mp4` | 12 min | | [ ] |
| B14 | P14 | `backup-B14-applicationset.mp4` | 8 min | | [ ] |
| B15 | P15 | `backup-B15-golden-path.mp4` | 10 min | | [ ] |

## Wrap

| Beat | Prompt | Filename | Target | Recorded | Verified plays |
|---|---|---|---|---|---|
| B16 | P16 | `backup-B16-kyverno-denial.mp4` | 8 min | | [ ] |
| B17 | P17 | `backup-B17-loki-attribution.mp4` | 6 min | | [ ] |
| B18 | (audience) | `backup-B18-commitment.mp4` | 6 min | | [ ] |

## Degraded-mode note

If the agent or the API is unavailable on event day, the modules run from these recordings with live cluster verification between modules. That path only works if every row above is recorded and verified, so a missing or unverified row is a live-event risk, not a nice-to-have.
