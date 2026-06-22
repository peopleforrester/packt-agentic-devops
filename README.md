# Agentic DevOps with Claude

An AI-native Internal Developer Platform, built live by an agent, on Amazon Kubernetes. This is the companion repo for the Packt workshop on July 23, 2026. It is also the take-home: everything built on screen is here, pinned and reproducible.

"Tools don't transform organizations. People do."

## What gets built

Over four hours, Claude Code builds a working platform on a real EKS cluster, one phase at a time:

- A cloud-native foundation: Backstage, the Argo stack, an OpenTelemetry observability plane, cert-manager, Kyverno, External Secrets with OpenBao.
- An AI plane: kgateway and agentgateway, kagent for declarative agents, LLM Guard for prompt-injection defense, OpenLLMetry with OTel GenAI conventions, KServe serving a CPU model with vLLM, and llm-d for the distributed-inference picture.
- A self-service golden path: a Backstage scaffolder template that generates a governed agent, wired through an ApplicationSet so ArgoCD deploys it automatically.

The whole platform is GitOps. ArgoCD reconciles every component from Git. The one agent governance lesson runs through all of it: the agent that builds the platform runs on an allowlist and shows up in the platform's own audit trail.

## Following along

You build on your own provided cluster with your own agentic CLI, driven by the same spec the presenter uses. If your build breaks or runs slow, you rejoin at the next phase boundary; the reference build on screen always carries the session.

- New here or arrived late: `copy-paste-commands.md` is the catch-up path. Run a module's block and you are current.
- What you need before you start: `docs/prerequisites.md`.
- If you fall behind: `docs/catch-up-guide.md`.

## Two model roles, kept separate

The building agent (Claude Code or an equivalent) runs on your own plan. The agents the platform deploys call a small in-cluster model served by vLLM, with no external spend and no credentials to leak. The no-external-spend rule is about the deployed agents, not your build CLI.

## Repo map

- `components.yaml`: the pinned component set, the single source of truth.
- `versions.lock.md`: the quick version lookup.
- `platform/bootstrap/`: ArgoCD install and the per-plane App-of-Apps (one per module).
- `platform/foundation/`, `platform/ai-plane/`, `platform/self-service/`: one directory per component.
- `charts-vendor/`: vendored Helm charts, so nothing waits on the network live.
- `prompts/prompt-library.md`: every live prompt, rehearsed verbatim.
- `docs/runbook/`: the run of show, preflight checklist, and failure recovery.
- `docs/build-spec.md` and `docs/research-findings-june-2026.md`: the full plan and the verified versions behind the design.
- `scripts/`: provisioning, mirroring, reset, preflight, and smoke-test automation.

## Honest framing

Components carry real maturity labels. Sandbox projects are described as Sandbox. The OTel GenAI semantic conventions are current but unstable, and the repo says so. Versions are pinned and frozen before the event; nothing is built from source live, and every image is served from a mirror so the build is fast and self-contained.

## License

MIT. See `LICENSE`.
