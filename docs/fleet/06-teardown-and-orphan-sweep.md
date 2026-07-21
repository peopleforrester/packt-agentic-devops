# 06 · Teardown and orphan sweep

Teardown is not `terraform destroy`. Terraform does not own the load balancers Kubernetes created, and
what it leaves behind both **costs money** and **blocks the VPC from deleting**.

The Unleashed fleet observed **~2 orphaned load balancers per cluster — 100 per account, 400 across four
accounts** — after a teardown that skipped the drain step. Plus 61 detached EBS volumes and 15 orphaned
security groups on one account alone. Assume the same here at 250.

## Ordering (each step exists because skipping it broke something)

### 1. Drain in-cluster load balancers, BEFORE destroy

```
kubectl delete svc  <every type=LoadBalancer>  --wait=true --timeout=150s
kubectl delete ingress -A --all --wait=true --timeout=150s
```

`--wait=true` blocks on the finalizer, which is only removed once the real AWS load balancer is gone.
Skipping this orphans the LB, whose ENIs then hold the subnet and fail `DeleteVpc`. Best-effort: if the
cluster is already unreachable, proceed to destroy.

We already proved this on `adwc-dev`: deleting the VTT Service first removed the CLB cleanly, and the
subsequent destroy completed with 63 resources and no LB left behind.

### 2. Release dynamically-provisioned EBS

```
kubectl delete pvc --all -A
```

PVC-provisioned volumes are deleted by the EBS CSI controller. Destroy the cluster first and that
controller is gone, so the volumes orphan. On `adwc-dev` this left **6 volumes `available`** that had to
be deleted by hand afterward. One PVC may hang on a finalizer; that is acceptable — the node teardown
releases it.

### 3. `terraform destroy` per cluster

```
terraform destroy -state=states/<account>/<cluster>.tfstate -var name=... -var vpc_id=...
```

Remove the state file only on success, so a failure is retryable. Missing state → skip, so a partial
fleet tears down cleanly.

### 4. Orphan sweep per account (AWS CLI, outside Terraform)

In this order:

1. Resolve the lab VPC by tag.
2. **Protect the NAT's EIP allocations first**, then never release those.
3. Delete every remaining ELB/ELBv2 in the VPC and its target groups.
4. **Poll for ELB ENIs to drain** (up to ~10 min). EIPs cannot disassociate until they do.
5. Release non-NAT EIPs.
6. Delete `available` EBS volumes tagged for our clusters.
7. Delete orphaned `eks-cluster-sg-*` security groups — **revoke all ingress and egress rules first**,
   because they cross-reference each other and `DeleteSecurityGroup` fails while the references exist.
8. `terraform destroy` the lab VPC.

**Mass `DeleteLoadBalancer` gets API-throttled.** The Unleashed sweep logs are full of
`(Throttling) ... Rate exceeded (reached max retries: 2)`. Our sweep must use exponential backoff and a
higher retry count, not the awscli default.

### 5. CloudWatch log groups

EKS owns them (`create_cloudwatch_log_group = false`), so they survive destroy. Sweep them separately,
verifying the cluster is actually gone before deleting each.

### 6. KMS keys

Cluster-encryption keys land in `PendingDeletion` (~7–30 day window) and are **not billed** while
pending. This is expected, not an orphan. We observed exactly this on `adwc-dev`: five keys
`PendingDeletion` after destroy.

## Success criterion

Per account, all of:

```
eks=0  ec2=0  clb=0  elbv2=0  volumes=0  nat=0  eip=0(non-protected)  labVPC=0
```

Anything non-zero is a leak and must be explained, not waved through. `tests/test_sweep.sh <account>`
asserts exactly this and exits non-zero otherwise.

## Cost reaping during the event

`fleet.sh reap --keep <file>` destroys any student cluster **not** in the claimed list, sourced from the
claim app's `/admin/export`. Dry-run unless `PACKT_APPLY=1`. At ~$0.43/cluster-hour this is the lever that
turns a 250-cluster spend into a 60-cluster spend once the real room size is known.

Pair it with removing the pool row for any reaped cluster, so the claim app never hands out a dead
cluster.

## Timing

Unleashed tore down 208 clusters in ~1h49m at 25-parallel per account, then a second pass for the rest,
then the sweep. **Budget roughly the same as provisioning, plus the sweep.** Teardown is not a
five-minute afterthought at this scale.
