# versions.lock.md

Pinned chart and image versions for the platform. Resolved June 15, 2026. Re-resolve once the week of July 13, 2026, then freeze. No version changes after the freeze.

Full sources and gotchas are in `docs/research-findings-june-2026.md`. This file is the quick lookup; `components.yaml` is the machine-readable source of truth.

| Component | App version | Chart | Chart version | Chart repo |
|---|---|---|---|---|
| Backstage | 1.51.2 | backstage | 2.8.2 | backstage.github.io/charts |
| Argo CD | v3.4.4 | argo-cd | 9.5.22 | argoproj.github.io/argo-helm |
| Argo Workflows | v4.0.6 | argo-workflows | 1.0.16 | argoproj.github.io/argo-helm |
| Argo Events | v1.9.10 | argo-events | 2.4.22 | argoproj.github.io/argo-helm |
| Argo Rollouts | v1.9.0 | argo-rollouts | 2.41.0 | argoproj.github.io/argo-helm |
| Sealed Secrets | 0.38.1 | sealed-secrets | 2.19.0 | bitnami-labs.github.io/sealed-secrets |
| External Secrets Operator | v2.6.0 | external-secrets | 2.6.0 | charts.external-secrets.io |
| cert-manager | v1.20.2 | cert-manager | v1.20.2 | oci://quay.io/jetstack/charts |
| Kyverno | v1.18.1 | kyverno | 3.8.1 | kyverno.github.io/kyverno |
| KEDA | 2.20.1 | keda | 2.20.1 | kedacore.github.io/charts |
| Score (CLI) | score-k8s 0.14.0 | n/a | n/a | n/a |
| AWS Load Balancer Controller | v3.4.0 | aws-load-balancer-controller | 3.4.0 | aws.github.io/eks-charts |
| AWS EBS CSI driver | v1.62.0 | aws-ebs-csi-driver | 2.62.0 | kubernetes-sigs.github.io/aws-ebs-csi-driver |
| kube-prometheus-stack | operator v0.91.0 | kube-prometheus-stack | 86.3.2 | prometheus-community.github.io/helm-charts |
| Prometheus | v3.12.0 | (bundled) | n/a | n/a |
| Grafana | 13.0.2 | grafana | 12.4.8 | grafana-community.github.io/helm-charts |
| Alertmanager | v0.33.0 | (bundled) | n/a | n/a |
| Loki | 3.7.2 | loki | 17.4.7 | grafana-community.github.io/helm-charts |
| Tempo | 2.10.7 | tempo-distributed | 2.25.4 | grafana-community.github.io/helm-charts |
| OTel Collector | 0.153.0 | opentelemetry-collector | 0.158.2 | open-telemetry.github.io/opentelemetry-helm-charts |
| OTel Operator | 0.153.0 | opentelemetry-operator | 0.115.0 | open-telemetry.github.io/opentelemetry-helm-charts |
| Gateway API | v1.5.1 | n/a (kubectl) | n/a | n/a |
| kgateway | v2.3.4 | kgateway | v2.3.4 | oci://cr.kgateway.dev/kgateway-dev/charts |
| agentgateway | v1.3.0 | agentgateway | v1.3.0 | oci://cr.agentgateway.dev/charts |
| kagent | v0.9.9 | kagent | 0.9.9 | oci://ghcr.io/kagent-dev/kagent/helm |
| LLM Guard | 0.3.16 | n/a (library) | n/a | n/a |
| OpenLLMetry | traceloop-sdk 0.61.0 | n/a (SDK) | n/a | n/a |
| KServe | v0.19.0 | kserve-resources | v0.19.0 | oci://ghcr.io/kserve/charts |
| vLLM | v0.23.0 | n/a (image) | n/a | vllm/vllm-openai-cpu:v0.23.0-x86_64 |
| llm-d | v0.7.0 | n/a (kustomize) | n/a | n/a |

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
| Claude Code | v2.1.183 | The presenter's build agent. Governed via managed-settings; audit hook ships tool invocations to Loki (B17). |

## Not used (and why)

- ingress-nginx: end of life March 24, 2026. Replaced by AWS Load Balancer Controller.
- MetalLB: decorative on EKS. AWS owns the LB layer.
- vcluster: not used. One real EKS cluster per student.
