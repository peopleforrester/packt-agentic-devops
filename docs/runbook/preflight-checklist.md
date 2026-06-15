# Preflight Checklist

The 7:30 AM EDT event-day ritual. Built in Phase 6. Pairs with `scripts/preflight.sh`.

- [ ] Primary EKS cluster healthy
- [ ] Hot-spare cluster healthy and synced to `checkpoint/module-0-start`
- [ ] All images cached on node caches or the mirror registry
- [ ] All checkpoint tags reachable
- [ ] ArgoCD green at `checkpoint/module-0-start`
- [ ] vLLM model server warm
- [ ] OBS scenes listed (manual)
- [ ] API key env vars present (existence only, never printed)
- [ ] Backup video files present at expected paths
- [ ] `promote-spare.sh` tested within the last day
