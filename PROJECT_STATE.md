# PROJECT_STATE

## Active operation: end-to-end validation run (started 2026-06-21)

A live EKS cluster is (or may be) running. **If this session resets, tear it down.**

### The cluster
- Name: `adwc-dev`
- Region: `us-west-2`
- AWS profile: `accen-dev`
- Shape: 1 x t3.2xlarge (the per-student shape)
- Tag on every resource: `Workshop=packt`
- Terraform: `scripts/provision/dev-cluster/`
- Isolated kubeconfig: `/tmp/adwc-dev.kubeconfig` (never `~/.kube/config`)

### Baseline at provision time
No EKS clusters and no running instances existed in the account before this run. Any
cluster named `adwc-dev` or any resource tagged `Workshop=packt` is ours. The account is
shared with another project (watchitburn) — never touch a cluster that is not `adwc-dev`.

### TEARDOWN (run this if anything is left running)
```bash
cd scripts/provision/dev-cluster && AWS_PROFILE=accen-dev terraform destroy -auto-approve
# then verify zero packt resources:
AWS_PROFILE=accen-dev aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Workshop,Values=packt --region us-west-2 \
  --query 'length(ResourceTagMappingList)'
```

### Secondary identity check (before ANY mutating kubectl/helm)
The kubeconfig must point at OUR packt cluster, verified independently of current-context:
```bash
KC=/tmp/adwc-dev.kubeconfig
SERVER=$(KUBECONFIG=$KC kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
EXPECT=$(AWS_PROFILE=accen-dev aws eks describe-cluster --name adwc-dev --region us-west-2 --query 'cluster.endpoint' --output text)
TAG=$(AWS_PROFILE=accen-dev aws eks describe-cluster --name adwc-dev --region us-west-2 --query 'cluster.tags.Workshop' --output text)
[ "$SERVER" = "$EXPECT" ] && [ "$TAG" = "packt" ] || echo "ABORT: wrong cluster"
```

### Independent records (outside TF state)
- `scripts/provision/dev-cluster/cluster-inventory.txt` — cluster ARN/UID/VPC/node IDs (written post-provision).
- `scripts/provision/dev-cluster/terraform.tfstate.backup-<ts>` — copy of the state.
- AWS Resource Group `packt-agentic-devops` (tag-based, live console view).

### Status
- [x] Sized to 1x t3.2xlarge, tagged, validated, committed.
- [x] Provisioned. Cluster ACTIVE, node i-0e5e2d5f32754c402 Ready. Inventory +
      state backup written. Secondary identity check PASSED (kubeconfig endpoint ==
      AWS API endpoint, Workshop=packt).
- [x] Bootstrapped: gp3 default SC + ArgoCD (Helm 9.5.21). Foundation Helm apps applied.
- [x] Full platform synced + single-node fit assessed. KEY FINDING: the platform fits
      one t3.2xlarge on RAM (36%) and CPU (32%), but the node caps at 58 pods and the
      platform needs ~75, so ~15 (Backstage, seeds, ~8 kagent agents) went Pending.
      Constraint is pod density, not RAM. Fix committed to Terraform: VPC CNI prefix
      delegation + maxPods=110 (raises the ceiling to ~110, stays single-node).
      Also validated: ArgoCD OCI Helm pulls work (kgateway/agentgateway/kagent/kserve all
      Synced+Healthy, no oci:// prefix, anonymous). Spike saved to mrf-knowledge/eks/.
- [x] Destroyed + verified. terraform destroy: 61 resources destroyed, TF state empty,
      no EKS clusters, no running instances. Independent tag query: 4 entries are
      tag-index lag on terminated/deleted resources (age out ~1hr); 1 is the KMS key in
      its mandatory 30-day PendingDeletion window (auto-deletes 2026-07-21, free).
      NOTHING LIVE, NOTHING BILLABLE.

## Prefix-delegation re-validation: PASSED and torn down (2026-06-21). No cluster running.

Teardown verified independently: destroy 61 resources, TF state 0, no clusters, no running
instances, both nodes terminated, NAT/subnet/volumes deleted, log group deleted. Only the
2 KMS keys remain in their mandatory PendingDeletion window (auto-delete 2026-07-21, $0).
ZERO LIVE, ZERO BILLABLE.

RESULT: node reported **110 allocatable pods** (up from 58). Full platform applied:
**0 scheduling failures, 0 "Too many pods"** — the 15 pods that were Pending before all
scheduled. Prefix delegation + maxPods=110 is confirmed; the student cluster stays a
single t3.2xlarge. Also committed the log-group idempotency fix (create_cloudwatch_log_
group=false) after hitting the orphan collision live.

### NEW finding to fix in the kagent component
kagent's chart deploys built-in agents (cilium, istio, helm, k8s, kgateway, argo-rollouts
agents) that all require a `kagent-openai` Secret (`OPENAI_API_KEY`). The workshop uses
in-cluster vLLM, not OpenAI, so they CreateContainerConfigError. Fix in
platform/ai-plane/kagent/application.yaml: disable the built-in agents via chart values
(workshop only needs the custom demo agent), or seed a kagent-openai Secret pointed at
vLLM with a dummy key. Verify with helm show values kagent for the disable flag.

### Teardown note
With create_cloudwatch_log_group=false, destroy may leave /aws/eks/adwc-dev/cluster
behind. Verify after destroy and delete it if present:
  aws logs delete-log-group --region us-west-2 --log-group-name /aws/eks/adwc-dev/cluster

### Open follow-up for the next session
- Re-validate with prefix delegation: provision once more (now 1x t3.2xlarge + prefix
  delegation + maxPods=110), confirm the node reports ~110 allocatable pods and nothing
  stays Pending, then run the phase gate tests against that clean per-phase cluster.
- Fleet: tag EKS node instances via the node group launch template tag_specifications
  (managed node groups do not propagate default_tags to instances).
- KMS key f3c2cfa7-... is in PendingDeletion until 2026-07-21 (harmless; tagged packt).

### Known follow-up (not blocking this run)
EKS managed node groups do not propagate Terraform default_tags to the EC2 instances.
The node instance + its volume were tagged Workshop=packt manually for this run. For the
300-cluster fleet, fix the Terraform to tag instances via the node group launch template
tag_specifications, so the fleet self-tags.
