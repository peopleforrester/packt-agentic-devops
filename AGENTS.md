# CLAUDE.md

Project memory for this repo. An agent builds an AI-native Internal Developer Platform on Amazon EKS from the spec in `spec/`, one phase at a time, and `tests/` proves each phase landed.

Read `docs/architecture.md` for the settled decisions, `docs/reference/decisions.md` for the dated log of how they were reached, and `docs/reference/research-findings-june-2026.md` for how the versions were verified. `docs/what-is-not-included.md` explains what was removed before publication, so a reference that looks broken has an answer.

## Manifest defect classes that recur here. Check for each before believing a build is healthy.

Every one of these produces a component that reports Synced, reports Healthy, and does not work.

1. **An unsubstituted `REPLACE_WITH_*` placeholder.** `grep -rn REPLACE_WITH solution/platform/` must return only tokens a provisioning step is proven to substitute: today that is the load balancer controller's `clusterName` and `vpcId`. Anything else leaves an Application Degraded forever.
2. **`runAsNonRoot: true` with no numeric `runAsUser`** on an image whose USER is root or non-numeric, which the kubelet refuses with `CreateContainerConfigError` before the container starts. Pin the uid the image actually uses; verify with `id` inside it rather than guessing. Hit on vLLM, llm-guard, the openbao and gitea seed jobs, and the MCP server. On a pod with an injected init container the uid has to go on the **pod**, because the init container writes into an emptyDir that needs `fsGroup`.
3. **An image `repository` that repeats the registry host** (`registry: ghcr.io` plus `repository: ghcr.io/...`), producing a doubled path. Repository must not include the host.
4. **A directory the container cannot traverse.** `Cannot find module '/app/...'` for a path that demonstrably holds the module is a permission problem, not a missing build.
5. **Hardcoded credentials that drift.** Read shared credentials from one Secret, never a second copy in a Job manifest.
6. **A custom resource ArgoCD cannot assess.** ArgoCD reports Healthy for anything it has no health check for, so a broken `MCPServer` or `Agent` shows green. `solution/platform/0-bootstrap/argocd-values.yaml` carries the checks and `tests/test_argocd_health_checks.py` fails if a new kind arrives unassessed.

`tests/test_platform_contract.py` asserts 1 through 5. Run the cluster-free suite after any manifest change:

```bash
uv run --with pytest --with pyyaml --with jsonschema python -m pytest -q
```

## What this repo is

A GitOps-driven, AI-native Internal Developer Platform. ArgoCD reconciles everything from Git. The foundation plane is cloud-native (Backstage, the Argo stack, the observability plane, policy and secrets tooling). The AI plane adds agent infrastructure (kgateway, agentgateway, kagent, LLM Guard, OpenLLMetry, KServe with vLLM, llm-d).

## Repo map

- `components.yaml` is the single source of truth for the component set. Every entry carries a pinned version. CI fails if any entry is unpinned.
- `versions.lock.md` records the pinned chart and image versions with the resolution date.
- `solution/platform/0-bootstrap/` holds the ArgoCD install, its values, and one App-of-Apps per plane.
- `solution/platform/1-foundation/` holds one directory per foundation component.
- `solution/platform/2-ai-plane/` holds one directory per AI-plane component.
- `solution/platform/3-self-service/` holds Backstage templates and the ApplicationSet.
- `charts-vendor/` holds vendored Helm charts, so nothing waits on the network mid-build. Every tarball is asserted to match its pin.
- `scripts/` holds chart vendoring, image mirroring, reset, preflight, smoke test, and the probes the phase tests use.
- `prompts/prompt-library.md` holds the prompts that drive each phase.
- `spec/` holds the build spec and one file per phase.

## GitOps rules

- Cluster context safety (this machine is shared, other systems use kubectl): every kubectl/helm command sets an explicit `KUBECONFIG` (a dedicated throwaway file) and `AWS_PROFILE` inline, never a global export. Never write to `~/.kube/config`: pull creds with `aws eks update-kubeconfig --kubeconfig /tmp/<cluster>.kubeconfig`. Verify `kubectl config current-context` matches the cluster you provisioned before any mutating command. Only touch clusters you created this session.
- All cluster changes flow through Git. ArgoCD applies them.
- Install first, enforce last. Every Kyverno policy (foundation `policy-baseline` and AI-plane `ai-policies`) ships with `failureAction: Audit`, not `Enforce`. Audit reports violations without blocking admission. An admission guardrail set to Enforce before the software meant to satisfy it is installed rejects that software's own pods and stalls the build. So the whole platform lands under Audit, then enforcement is turned on only after the platform is healthy. The single sanctioned flip to Enforce is the governance demonstration on the AI-plane set, performed only after the platform is healthy; the foundation baseline stays Audit. Do not set any policy to Enforce during the build, and do not add a namespace-wide enforcing admission webhook that fires before its backing workload exists.
- Never run mutating `kubectl` directly against the cluster, except for the bootstrap (installing ArgoCD) and the scripted Kyverno denial demonstration.
- Bootstrap and ApplicationSet CRDs require server-side apply: use `kubectl apply --server-side --force-conflicts`. The ApplicationSet and Argo Workflows CRDs exceed the client-side apply annotation limit.
- ArgoCD is on the 3.x line. Server-side apply and server-side diff are the modern default. RBAC changed in 3.0: `update` and `delete` no longer cascade to managed sub-resources, and logs need explicit `logs, get` permission.

## Naming and namespaces

- Descriptive kebab-case everywhere. No UUIDs, no `final-v2` suffixes. No `improved`, `new`, or `enhanced` in names.
- One namespace per logical area: `argocd`, `backstage`, `observability`, `cert-manager`, `kyverno`, `external-secrets`, `openbao`, `kgateway-system`, `agentgateway`, `kagent`, `kserve`.
- Checkpoints are annotated git tags: `checkpoint/module-0-start`, `checkpoint/module-1-end`, `checkpoint/module-2-end`, `checkpoint/module-3-end`. `scripts/reset/reset-to-checkpoint.sh` targets them, so a phase can be redone from a known state.

## Platform facts that are easy to get wrong (verified June 2026)

- ingress-nginx is end of life and MetalLB is decorative on EKS. The ingress and LB path is the AWS Load Balancer Controller. Storage is the AWS EBS CSI driver.
- Workload identity is EKS Pod Identity, not IRSA. Both the AWS Load Balancer Controller and the EBS CSI driver use it; the cluster sets `enable_irsa = false` so no OIDC provider is created. Pod Identity is the AWS-suggested default over IRSA as of July 2026 and avoids 300 per-cluster OIDC trust policies. The EBS CSI association is wired through the add-on's `pod_identity_association` (EKS owns the ordering); the LB controller uses a standalone association. This is a locked decision (D16). Read `docs/architecture.md` and `docs/reference/decisions.md` before changing it, and record a superseding entry; do not silently revert to IRSA.
- The kagent Agent CRD is `kagent.dev/v1alpha2`. The field is `systemMessage`, nested under `spec.type` and `spec.declarative`. Agents run on Google ADK. Do not write v1alpha1 or `systemPrompt`.
- agentgateway is a Linux Foundation (Agentic AI Foundation) project, not CNCF. It is a sibling of kgateway, not its data plane.
- The demo agent routes to the in-cluster vLLM **through agentgateway**, not directly, so the prompt-guard and audit policies apply to it. An agent that calls the model directly bypasses every control the AI plane installs, and the platform then certifies guardrails nothing traverses. No external API spend, no external credentials.
- The Gateway must not be named after the chart that installs its controller. The controller creates one Deployment per Gateway named after the Gateway; the agentgateway chart's own Deployment carries the release name; `spec.selector` is immutable, so naming both `agentgateway` fails permanently while ArgoCD reports the sync succeeded. It is `agentgateway-proxy`.
- Agent tracing is **off** by default in the kagent chart. `otel.tracing.enabled` is the switch that works. The `instrumentation.opentelemetry.io/inject-python` annotation does not: the agent is a Go binary, kagent does not copy Agent annotations onto the Deployment it generates, and no `Instrumentation` resource exists. The annotation stays because a policy requires it; it is not what produces the traces.
- OTel GenAI spans are named for their **operation and target** (`invoke_agent platform_helper`, `execute_tool echo`, `generate_content qwen3-1.7b`), with `gen_ai.*` in the **attributes**. Do not match spans by a `gen_ai.*` name; nothing is named that way.
- OpenTelemetry GenAI semantic conventions are Development grade. Present `gen_ai.*` attributes as current but unstable.

## Writing standards for any doc generated here

- No em-dashes, no en-dashes. Commas, colons, periods.
- Banned words: delve, leverage, robust, seamless, comprehensive, under the hood, navigate complexities, genuinely, in today's landscape.
- No "it's not X, it's Y" inversions. No triadic lists as a default. No mirrored closing sentences.
- Direct and declarative. State things plainly. No hedging filler.
- Claims about maturity stay evidence-grounded. Sandbox projects are described as Sandbox. If evidence for a number does not exist, say so.
- "Tools don't transform organizations. People do." is preserved verbatim if quoted.

## Secrets

The repo contains zero real credentials, and no AWS account id. Both are verifiable rather than asserted; `docs/what-is-not-included.md` gives the two commands. OpenBao (the LF/MPL-2.0 Vault fork, dev mode) is the in-cluster secret backend and External Secrets Operator pulls from it over the Vault-compatible API. Sealed Secrets was dropped (redundant with ESO, and Bitnami retired its chart repo). No manifest references docker.io directly: images are mirrored to a GHCR namespace.
