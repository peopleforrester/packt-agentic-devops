# Catch-Up Guide

For anyone who falls behind or joins late. It pairs with `copy-paste-commands.md`: each module boundary has a jump-in block, and running one block makes your cluster current with the room.

Watching has full value. Following along is encouraged but never required, because every outcome is reached on the presenter's cluster regardless. If your own build breaks, stop debugging it and jump in at the next module boundary below.

## How to use this

Find the module the room is starting, run that jump-in block from `copy-paste-commands.md`, wait for it to report Healthy, and you are caught up. Each block is idempotent, so re-running it is safe.

## Jump-in points

### Start of Module 1 (cloud-native foundation)
Confirm ArgoCD is up, then apply the foundation plane.
- Run the Module 0 check and the Module 1 block in `copy-paste-commands.md`.
- Done when `platform-foundation` is Healthy and Backstage answers.

### Start of Module 2 (the AI plane)
You need the foundation green first. If you skipped Module 1, run its block, wait for green, then continue.
- Run the Module 2 block. It applies the AI-plane App-of-Apps; CRDs land first, then controllers and the model server.
- Done when `platform-ai-plane` is Healthy and the vLLM InferenceService reads `READY=True`.

### Start of Module 3 (self-service)
You need the AI plane green first. If you skipped ahead, run Modules 1 and 2 in order, then continue.
- Run the Module 3 block. It applies the self-service App-of-Apps and its ApplicationSet.
- Done when `platform-self-service` is Healthy. From here you can request an agent through the Backstage portal and watch the golden path.

## From zero in one pass

If you want the whole platform from a bare cluster, run Module 0, then 1, then 2, then 3 in order. Each block waits for its plane before the next. The full build from a bare cluster takes roughly 20 minutes.

## What matters versus what you can skip

The beats to watch even if your own build lags: the kagent Agent written and reconciled by GitOps (Module 2), the prompt-injection block, and the golden path (Module 3). Those are the workshop. The foundation sync and the dashboard walkthroughs are worth following but safe to catch up on later from the repo.
