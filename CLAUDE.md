# CLAUDE.md

Project memory for the Agentic DevOps with Claude workshop repo. This is the platform Claude Code builds live on Amazon EKS during the Packt workshop on July 23, 2026. Read `internal/build-spec.md` for the full build spec and `internal/research-findings-june-2026.md` for verified versions.

## Fleet provisioning and validation (read before touching provisioning or platform manifests)

The 250-cluster fleet, its driver, and the full from-cold validation are documented in
`docs/fleet/`. Read these before changing provisioning or debugging a platform sync:

- `docs/fleet/08-progressive-rollout-run.md` is the rollout plan (5 to 54 to 250, the gates).
- `docs/fleet/09-lessons-learned.md` is the running record of every defect found and fixed.
- The driver is `scripts/provision/fleet/fleet.sh` (+ `lib.sh`); `tag-audit.sh` finds and
  repairs untagged resources; `sweep.sh` is the orphan cleanup.

**Validated (2026-07-23):** 250 clusters provisioned and torn down cleanly across five accounts;
the foundation and AI plane both converge from a cold provision with zero manual steps (foundation
to 19/21 in ~7 min, the two exceptions being the intentional P03 fault and, until fixed, the
Backstage image). vLLM serves real in-cluster completions. The filming build had masked most
foundation bugs because its Applications were suspended and hand-patched; the only faithful test is
a clean cluster syncing from an untouched repo.

**Defect classes that recur in these manifests. Grep for each before a run:**

1. **Unsubstituted `REPLACE_WITH_*` placeholders.** `grep -rn REPLACE_WITH platform/` must return
   only tokens a provisioning step is proven to substitute (currently the LB controller
   clusterName/vpcId, done by the Gitea seed job from the `platform-cluster-facts` ConfigMap). An
   unsubstituted placeholder leaves an Application Degraded forever.
2. **`runAsNonRoot: true` with no numeric `runAsUser`** on an image whose USER is non-numeric →
   `CreateContainerConfigError`. Pin the image's actual uid (verify with `id` in the image). Hit on
   vLLM, llm-guard (D18), and the openbao and gitea seed jobs.
3. **Image `repository` that repeats the registry host** (`registry: ghcr.io` +
   `repository: ghcr.io/...`) → a doubled path. Repository must not include the host.
4. **A directory the container cannot traverse.** `Cannot find module '/app/...'` for a path that
   demonstrably contains the module is a permission/ownership problem (container runs as a uid that
   cannot read the tree), not a missing build. Backstage `/app` shipped 0700 root under `USER node`.
5. **Hardcoded credentials that drift.** Read shared creds from one Secret (e.g. `gitea-seed-creds`),
   never a second copy in a Job manifest.

Contract tests in `tests/test_fleet_contract.py` assert all of the above; run
`uv run --with pytest --with pyyaml python -m pytest tests/test_fleet_contract.py -q` after any
manifest or provisioning change.

## GO-LIVE BLOCKER: web terminals have no authentication

Confirmed live on 2026-07-23: a student reached the instructor's admin cluster through its terminal
URL. Every VTT terminal is served at a predictable, unauthenticated public URL (`studentN` is
sequential and enumerable; plus `admin1`/`admin2`), and each is a `sudo`-capable cluster-admin shell
with the cluster's EKS Pod Identity AWS reach. Anyone with a URL can open another student's or the
admin's terminal and destroy it. **Do not run this workshop again until terminals require
authentication.** IP allow-listing at the NLB does NOT work (it blocks the Caddy router, the only
thing the NLB sees); the browser's real IP is visible only at the router via `X-Forwarded-For`. Fix
directions and full write-up: `docs/fleet/09-lessons-learned.md` (final section).

## Railway and the claim portal (read before any `railway` command)

Full detail in `scripts/provision/distribution/RAILWAY-OPS.md`. The critical facts:

- **The LIVE claim/provisioning app is the `packt-provisioning` service**, serving
  `https://packt.ai-enhanced-devops.com/`. It owns the persistent volume and the claim DB
  (`/data/pool.db`). Deploy the claim app ONLY here. `packt-router` (Caddy) serves the
  `studentN.packt.ai-enhanced-devops.com` terminals and is deployed by `routes.sh`.
  `ai-enhanced-devops-website` is a STALE/failed sibling that serves nothing live: do not deploy
  to it. The tell you are on the wrong service is `railway ssh -s <svc> -- echo ok` returning the
  Railway meta-gateway JSON instead of `ok`.
- **`railway ssh` exec: pipe the script over STDIN** (`railway ssh -s packt-provisioning -- python3
  < script.py`); inline `python3 -c "..."` breaks because the CLI re-parses through a remote shell.
  **`railway variables` truncates in the table view**: use `--kv`/`--json` for full tokens.
  **`Failed to stream build logs` on `railway up` is transient**: verify the deploy via URLs or
  `railway status`, not the CLI exit code.
- **The claim pool DB only adds rows on restart, never removes.** Editing `pool.csv` + restart does
  NOT shrink it. Prune by editing the DB directly via `railway ssh`, or use a fresh `DATABASE_PATH`.
  The pool must contain the real banded cluster names (student1-20, 51-70, 101-120, 151-170,
  201-220), not sequential `student1-N`, or students past the first band claim clusters that were
  never built. Regenerate with `scripts/provision/gen-pool.sh`; run `routes.sh` after every scale
  change or the URLs 404.

## What this repo is

A GitOps-driven, AI-native Internal Developer Platform. ArgoCD reconciles everything from Git. The foundation plane is cloud-native (Backstage, the Argo stack, the observability plane, policy and secrets tooling). The AI plane adds agent infrastructure (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry, KServe with vLLM, llm-d).

## Repo map

- `components.yaml` is the single source of truth for the component set. Every entry carries a pinned version. CI fails if any entry is unpinned.
- `versions.lock.md` records the pinned chart and image versions with the resolution date.
- `platform/0-bootstrap/` holds the ArgoCD install and the root App-of-Apps.
- `platform/1-foundation/` holds one directory per foundation component.
- `platform/2-ai-plane/` holds one directory per AI-plane component.
- `platform/3-self-service/` holds Backstage templates and ApplicationSets.
- `charts-vendor/` holds vendored Helm charts. Nothing waits on the network live.
- `scripts/` holds provisioning, reset, preflight, smoke-test, and image-mirror scripts.
- `prompts/prompt-library.md` holds every live prompt, rehearsed verbatim.
- `docs/runbook/` holds the run-of-show, preflight checklist, and failure-recovery docs.

## GitOps rules

- Cluster context safety (this machine is shared, other systems use kubectl): every kubectl/helm command sets an explicit `KUBECONFIG` (a dedicated throwaway file) and `AWS_PROFILE` inline, never a global export. Never write to `~/.kube/config`: pull creds with `aws eks update-kubeconfig --kubeconfig /tmp/<cluster>.kubeconfig`. Verify `kubectl config current-context` matches the cluster you provisioned before any mutating command. Only touch clusters you created this session.
- All cluster changes flow through Git. ArgoCD applies them.
- Install first, enforce last. Every Kyverno policy (foundation `policy-baseline` and AI-plane `ai-policies`) ships with `failureAction: Audit`, not `Enforce`. Audit reports violations without blocking admission. An admission guardrail set to Enforce before the software meant to satisfy it is installed rejects that software's own pods and stalls the build. So the whole platform lands under Audit, then enforcement is turned on only after the platform is healthy. The single sanctioned flip to Enforce is the B16/P16 governance demo on the AI-plane set; the foundation baseline stays Audit through the workshop. Do not set any policy to Enforce during the build, and do not add a namespace-wide enforcing admission webhook that fires before its backing workload exists.
- Never run mutating `kubectl` directly against the cluster, except for the bootstrap (installing ArgoCD) and the scripted Kyverno denial demo (B16).
- Bootstrap and ApplicationSet CRDs require server-side apply: use `kubectl apply --server-side --force-conflicts`. The ApplicationSet and Argo Workflows CRDs exceed the client-side apply annotation limit.
- ArgoCD is on the 3.x line. Server-side apply and server-side diff are the modern default. RBAC changed in 3.0: `update` and `delete` no longer cascade to managed sub-resources, and logs need explicit `logs, get` permission.

## Naming and namespaces

- Descriptive kebab-case everywhere. No UUIDs, no `final-v2` suffixes. No `improved`, `new`, or `enhanced` in names.
- One namespace per logical area: `argocd`, `backstage`, `observability`, `cert-manager`, `kyverno`, `external-secrets`, `openbao`, `kgateway-system`, `agentgateway`, `kagent`, `kserve`.
- Checkpoints are annotated git tags: `checkpoint/module-0-start`, `checkpoint/module-1-end`, `checkpoint/module-2-end`, `checkpoint/module-3-end`. Reset scripts target these tags.

## Platform facts that are easy to get wrong (verified June 2026)

- ingress-nginx is end of life and MetalLB is decorative on EKS. The ingress and LB path is the AWS Load Balancer Controller. Storage is the AWS EBS CSI driver.
- Workload identity is EKS Pod Identity, not IRSA. Both the AWS Load Balancer Controller and the EBS CSI driver use it; the cluster sets `enable_irsa = false` so no OIDC provider is created. Pod Identity is the AWS-suggested default over IRSA as of July 2026 and avoids 300 per-cluster OIDC trust policies. The EBS CSI association is wired through the add-on's `pod_identity_association` (EKS owns the ordering); the LB controller uses a standalone association. This is a locked decision (D16). Read `docs/architecture.md` and `internal/decisions.md` before changing it, and record a superseding entry; do not silently revert to IRSA.
- The kagent Agent CRD is `kagent.dev/v1alpha2`. The field is `systemMessage`, nested under `spec.type` and `spec.declarative`. Agents run on Google ADK. Do not write v1alpha1 or `systemPrompt`.
- agentgateway is a Linux Foundation (Agentic AI Foundation) project, not CNCF. It is a sibling of kgateway, not its data plane.
- The demo agent on attendee clusters routes to the in-cluster vLLM via an OpenAI-compatible endpoint. No external API spend, no external credentials. See `internal/build-spec.md` section 6.7.
- OpenTelemetry GenAI semantic conventions are Development grade. Present `gen_ai.*` attributes as current but unstable.

## Writing standards for any doc generated here

- No em-dashes, no en-dashes. Commas, colons, periods.
- Banned words: delve, leverage, robust, seamless, comprehensive, under the hood, navigate complexities, genuinely, in today's landscape.
- No "it's not X, it's Y" inversions. No triadic lists as a default. No mirrored closing sentences.
- Direct and declarative. State things plainly. No hedging filler.
- Claims about maturity stay evidence-grounded. Sandbox projects are described as Sandbox. If evidence for a number does not exist, say so.
- "Tools don't transform organizations. People do." is preserved verbatim if quoted.

## Secrets

The repo contains zero real credentials. Presenter keys live in environment variables loaded before OBS starts. OpenBao (the LF/MPL-2.0 Vault fork, dev mode) is the in-cluster secret backend and External Secrets Operator pulls from it over the Vault-compatible API. Sealed Secrets was dropped (redundant with ESO, and Bitnami retired its chart repo). No manifest references docker.io directly: images are mirrored to a GHCR namespace.
