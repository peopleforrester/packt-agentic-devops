# CLAUDE.md

Project memory for the Agentic DevOps with Claude workshop repo. This is the platform Claude Code builds live on Amazon EKS during the Packt workshop on July 23, 2026. Read `internal/build-spec.md` for the full build spec and `internal/research-findings-june-2026.md` for verified versions.

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
