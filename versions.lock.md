# versions.lock.md

Pinned chart and image versions for the platform. Originally resolved 15 June 2026 and frozen for
the 23 July 2026 delivery.

**The freeze applied to the event, not to this repository.** A four-hour live build wants versions
that cannot move under it; a repo people read and run for years wants the opposite. Those are
different goals and they now have different homes:

| Where | Policy |
|---|---|
| Tag [`v1.0.0`](../../releases/tag/v1.0.0) | The frozen state. Reproduces the build exactly as delivered. Never re-pinned. |
| `main` | Maintained. Versions move on the cadence in [`docs/version-maintenance.md`](docs/version-maintenance.md). |

So if you want what was on screen, check out the tag. If you want a platform that installs against a
current cluster, use `main` and expect these numbers to change.

`components.yaml` is the machine-readable source of truth; this file is the quick lookup.

| Component | App version | Chart | Chart version | Chart repo |
|---|---|---|---|---|
| Backstage | 1.51.2 | backstage | 2.10.0 | backstage.github.io/charts |
| backstage-techdocs | 1.51.2 | (bundled in backstage) | 2.10.0 | backstage.github.io/charts |
| backstage-software-catalog | 1.51.2 | (bundled in backstage) | 2.10.0 | backstage.github.io/charts |
| backstage-scaffolder | 1.51.2 | (bundled in backstage) | 2.10.0 | backstage.github.io/charts |
| backstage-github-oauth | 1.51.2 | (bundled in backstage) | 2.10.0 | backstage.github.io/charts |
| backstage-argocd-plugin | 2.12.5 | (bundled in backstage) | 2.10.0 | backstage.github.io/charts |
| Argo CD | v3.5.2 | argo-cd | 10.8.4 | argoproj.github.io/argo-helm |
| Argo Workflows | v4.1.2 | argo-workflows | 2.0.4 | argoproj.github.io/argo-helm |
| Argo Events | v1.9.11 | argo-events | 2.4.27 | argoproj.github.io/argo-helm |
| Argo Rollouts | v1.10.0 | argo-rollouts | 2.43.0 | argoproj.github.io/argo-helm |
| OpenBao | v2.6.2 | openbao | 0.29.4 | openbao.github.io/openbao-helm |
| External Secrets Operator | v2.10.0 | external-secrets | 2.10.0 | charts.external-secrets.io |
| cert-manager | v1.20.2 | cert-manager | v1.20.2 | oci://quay.io/jetstack/charts/cert-manager |
| Kyverno | v1.19.0 | kyverno | 3.9.0 | kyverno.github.io/kyverno |
| KEDA | 2.20.2 | keda | 2.20.2 | kedacore.github.io/charts |
| AWS Load Balancer Controller | v3.5.0 | aws-load-balancer-controller | 3.5.0 | aws.github.io/eks-charts |
| AWS EBS CSI driver | v1.62.0 | aws-ebs-csi-driver | 2.62.0 | kubernetes-sigs.github.io/aws-ebs-csi-driver |
| kube-prometheus-stack | operator v0.93.1 | kube-prometheus-stack | 90.0.0 | prometheus-community.github.io/helm-charts |
| prometheus | v3.12.0 | (bundled in kube-prometheus-stack) | 90.0.0 | prometheus-community.github.io/helm-charts |
| grafana | 13.0.2 | (bundled in kube-prometheus-stack) | 90.0.0 | prometheus-community.github.io/helm-charts |
| alertmanager | v0.33.0 | (bundled in kube-prometheus-stack) | 90.0.0 | prometheus-community.github.io/helm-charts |
| kube-state-metrics | 7.5.1 | (bundled in kube-prometheus-stack) | 90.0.0 | prometheus-community.github.io/helm-charts |
| prometheus-node-exporter | 4.55.0 | (bundled in kube-prometheus-stack) | 90.0.0 | prometheus-community.github.io/helm-charts |
| Loki | 3.7.7 | loki | 18.12.1 | grafana-community.github.io/helm-charts |
| Tempo | 2.9.0 | tempo | 1.25.0 | grafana-community.github.io/helm-charts |
| OTel Collector | 0.159.0 | opentelemetry-collector | 0.172.1 | open-telemetry.github.io/opentelemetry-helm-charts |
| OTel Operator | 0.158.0 | opentelemetry-operator | 0.122.0 | open-telemetry.github.io/opentelemetry-helm-charts |
| Gateway API | v1.6.2 | n/a (kubectl) | n/a | n/a |
| kgateway | v2.4.4 | kgateway | v2.4.4 | oci://cr.kgateway.dev/kgateway-dev/charts |
| agentgateway | v1.5.0 | agentgateway | v1.5.0 | oci://cr.agentgateway.dev/charts |
| kagent | v0.10.0 | kagent | 0.10.0 | oci://ghcr.io/kagent-dev/kagent/helm |
| LLM Guard | 0.3.16 | n/a (library) | n/a | n/a |
| OpenLLMetry | traceloop-sdk 0.61.0 | n/a (library) | n/a | n/a |
| KServe | v0.20.0 | kserve-resources | v0.20.0 | oci://ghcr.io/kserve/charts |
| vLLM | v0.23.0 | n/a (kubectl) | n/a | n/a |
| llm-d | v0.7.0 | n/a (kustomize) | n/a | n/a |
| MCP demo server | everything-2025-11-25 | n/a (kubectl) | n/a | n/a |
| Gitea | 1.27.0 | gitea | 12.7.0 | dl.gitea.com/charts/ |
| Self-service templates | built-live-module-3 | n/a (kubectl) | n/a | n/a |

## CPU model

- Primary: `Qwen/Qwen3-1.7B`
- Backup: `Qwen/Qwen3-0.6B`

## Supporting tooling

| Tool | Version |
|---|---|
| eksctl | v0.226.0 |
| terraform-aws-eks | v21.20.0 |
| Karpenter (reference only, not self-managed here) | v1.13.0 |
| ingress2gateway (migration reference) | 1.0 |

## Agent protocols and CLI tooling

| Piece | Version | Notes |
|---|---|---|
| MCP spec | 2025-11-25 | Stable revision. stdio and Streamable HTTP transports; HTTP+SSE deprecated. |
| MCP demo server | mcp/everything | Streamable HTTP reference server for the agent-calls-MCP beat; mirror to GHCR. |
| KMCP | v0.3.0 | kagent MCP server platform; bundled with kagent 0.7+ (kmcp.enabled). MCPServer is v1alpha1, RemoteMCPServer is v1alpha2. |
| A2A | v1.0.0 | Linux Foundation Agent2Agent project; agentgateway mediates via an a2a route policy. |
| Claude Code | v2.1.183 | The presenter's build agent. Governed by the project's `.claude/settings.json` (allow/ask/deny plus PreToolUse and PostToolUse hooks), not by managed settings. The shipped file sets no `defaultMode`, so the `ask` rules actually prompt; an unprompted mode belongs in the gitignored `settings.local.json`. Audit hook ships tool invocations to Loki. |

## Not used (and why)

- ingress-nginx: end of life March 24, 2026. Replaced by AWS Load Balancer Controller.
- MetalLB: decorative on EKS. AWS owns the LB layer.
- vcluster: not used. One real EKS cluster per student.
