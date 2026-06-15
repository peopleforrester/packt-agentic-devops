# Architecture

The diagram source (Excalidraw export) and the full prose are written as the platform takes shape. This file records the architectural decisions that are already settled, stated honestly.

## Platform

Amazon EKS, one cluster per student, managed control plane plus a T3 managed node group (2 to 3 t3.xlarge or t3.2xlarge workers). Kubernetes 1.34 or 1.35. vcluster is not used.

## Load balancing and ingress

The AWS Load Balancer Controller is the ingress and LB path: ALB for Ingress, NLB for Service type=LoadBalancer, Gateway API supported. Authenticate via EKS Pod Identity, one reusable scoped role rather than per-cluster IAM users.

MetalLB is not used. On EKS, AWS owns the load balancer and VIP layer, so MetalLB is decorative at best and conflicting at worst.

ingress-nginx is not used. It reached end of life on March 24, 2026, the repo is read-only with no security patches, and its planned successor InGate was abandoned. Platform ingress can route through kgateway and Gateway API to keep a vendor-neutral story, with the AWS Load Balancer Controller provisioning the NLB in front.

## Storage

The AWS EBS CSI driver provides PersistentVolumes for Prometheus, Loki, Tempo, and Grafana.

## GitOps and sync waves

ArgoCD reconciles everything from Git. Sync waves order the foundation so dependencies do not race: cert-manager and the AWS controllers first, then ingress and secrets tooling, then observability, then the Argo extensions, then Backstage last.

ArgoCD shards by cluster, not by app. With this component count on one cluster, all apps live in one shard, so controller sharding buys nothing. The repo server is the manifest-generation bottleneck; the HA default of two replicas is enough. The default kubectl parallelism limit of 20 is adequate. Bootstrap with server-side apply: the ApplicationSet and Argo Workflows CRDs exceed the client-side apply annotation limit. This tuning is itself teachable content.

## Demo agent model routing

Attendee clusters route the kagent demo agent to the in-cluster vLLM over an OpenAI-compatible endpoint: no external API spend, no external credentials. The presenter cluster shows one real cloud route (Bedrock via Pod Identity, or Anthropic behind a LiteLLM proxy), scoped and capped. See `build-spec.md` section 6.7.

## Observability and the AI plane

Every agent call, MCP invocation, and LLM request flows through OpenTelemetry to Tempo (traces) and Grafana (dashboards). OpenTelemetry GenAI semantic conventions are Development grade as of June 2026; `gen_ai.*` attributes are presented as current but unstable.
