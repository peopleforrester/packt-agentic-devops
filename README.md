<p align="center">
  <img src="docs/images/hero.png" alt="An orchestrating agent assembling a layered Kubernetes platform" width="100%">
</p>

# Agentic DevOps with Claude

**An AI-native Internal Developer Platform, built live by an agent, on Amazon EKS.**

[![License: MIT](https://img.shields.io/badge/License-MIT-FA7040.svg)](LICENSE)
[![Components](https://img.shields.io/badge/components-71%20pinned-2e9e5b.svg)](components.yaml)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue.svg)](solution/platform/0-bootstrap)
[![Fleet](https://img.shields.io/badge/fleet-250%20clusters%20validated-blue.svg)](docs/fleet/08-progressive-rollout-run.md)

This is the companion repo for the Packt workshop delivered on 23 July 2026. Every component the
agent built on screen is here, pinned and reproducible. Nothing was demoed from a slide.

> "Tools don't transform organizations. People do."

---

## What actually happened

The workshop was not a scripted demo. Attendees got a bare EKS cluster and an agent, and built the
platform themselves from the same spec the presenter used. What that took to support:

| | |
|---|---|
| **250 single-tenant clusters** | provisioned and torn down cleanly across five AWS accounts, roughly 2h45m at 40-wide |
| **39/39 ArgoCD Applications** | Synced and Healthy from a cold provision, zero manual steps |
| **~7 minutes** | bare cluster to a converged foundation plane |
| **71 components** | every one version-pinned in [`components.yaml`](components.yaml) before the event |
| **Real inference** | vLLM serving an in-cluster model, no external API spend, no credentials to leak |

The defects found during the live run were not quietly patched out. They are written down in
[`defects/July-23rd-Defects-run.md`](defects/July-23rd-Defects-run.md), remediated in the manifests,
and the durable lessons are in [`defects/lessons-learned.md`](defects/lessons-learned.md).

## What the platform contains

Three planes, built in order, each reconciled by ArgoCD from Git.

**Cloud-native foundation.** Backstage as the developer portal, the full Argo stack (CD, Workflows,
Events, Rollouts), an OpenTelemetry observability plane with Prometheus, Loki and Tempo,
cert-manager, Kyverno for policy, and External Secrets backed by OpenBao.

**AI plane.** kgateway and agentgateway for agent traffic, kagent for declarative agents as
first-class Kubernetes objects, LLM Guard for prompt-injection defense, OpenLLMetry emitting OTel
GenAI semantic conventions, and KServe serving a CPU model through vLLM, with llm-d for the
distributed-inference picture.

**Self-service golden path.** A Backstage scaffolder template that generates a governed agent, wired
through an ArgoCD ApplicationSet so the platform deploys it without a human in the loop.

## The engineering worth reading

If you are skimming this as a portfolio piece, these are the parts with real decisions in them.

- **[`docs/fleet/09-lessons-learned.md`](docs/fleet/09-lessons-learned.md)** is the honest record: every
  defect class found running this at 250-cluster scale, and what fixed it. Including the ones that
  were embarrassing.
- **[`docs/architecture.md`](docs/architecture.md)** carries the settled decisions and why. EKS Pod
  Identity over IRSA. Audit-mode policy before enforcement. Why MetalLB and ingress-nginx are the
  wrong answer on EKS in 2026.
- **[`tests/test_fleet_contract.py`](tests/test_fleet_contract.py)** encodes the defect classes that
  recur in these manifests as assertions, so the same mistake cannot ship twice. Unsubstituted
  placeholders, `runAsNonRoot` without a numeric uid, registry hosts doubled into image paths.
- **[`scripts/provision/fleet/`](scripts/provision/fleet)** is the fleet driver: provision, converge,
  tag-audit, sweep, teardown. The converge pass is mandatory, and
  [the rollout record](docs/fleet/08-progressive-rollout-run.md) explains why a run without it
  reports 89% success and is wrong.
- **A known, unfixed security finding is documented rather than hidden.** The browser terminals had
  no authentication, a student reached the instructor cluster, and that is written up in
  `CLAUDE.md` and the lessons file with the analysis of why the obvious fixes do not work.

## Repo map

- [`spec/`](spec) the attendee-facing spec the agent builds from, plus the per-phase breakdown.
- [`components.yaml`](components.yaml) the pinned component set and single source of truth.
  [`versions.lock.md`](versions.lock.md) is the quick lookup.
- [`solution/platform/`](solution/platform) the reference build, numbered in build order:
  `0-bootstrap` (ArgoCD and the App-of-Apps), `1-foundation`, `2-ai-plane`, `3-self-service`.
- [`charts-vendor/`](charts-vendor) vendored Helm charts, so nothing waits on the network live.
- [`prompts/prompt-library.md`](prompts/prompt-library.md) every live prompt, rehearsed verbatim.
- [`scripts/`](scripts) provisioning, image mirroring, reset, preflight, smoke tests, and the fleet driver.
- [`docs/`](docs) attendee docs, the architecture record, the runbook, and the fleet documentation set.
- [`tests/`](tests) the contract tests and one pytest file per build phase.
- [`defects/`](defects) what broke live, and what was learned.

## Running it yourself

You need an EKS cluster, an agentic CLI on your own plan, and the prerequisites in
[`docs/prerequisites.md`](docs/prerequisites.md). Point your agent at
[`spec/WORKSHOP-SPEC.md`](spec/WORKSHOP-SPEC.md) and let it build, one phase at a time.

If a phase breaks or you want to skip ahead, [`copy-paste-commands.md`](copy-paste-commands.md) is the
catch-up path: run a module's block and you are current. The reference build in `solution/platform/`
is always the answer key.

## Honest framing

Components carry real maturity labels. Sandbox projects are described as Sandbox. The OTel GenAI
semantic conventions are current but unstable, and the repo says so rather than implying they are
settled. Versions were pinned and frozen before the event, nothing was built from source live, and
every image was served from a mirror so the build stayed fast and self-contained.

Where something is broken or unfinished, it is labelled. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## License

MIT. See [`LICENSE`](LICENSE).
