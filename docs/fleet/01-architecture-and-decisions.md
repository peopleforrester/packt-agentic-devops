# 01 · Fleet architecture and locked decisions

250 student clusters across 5 AWS accounts, 50 each. This design is a port of the Watch It Burn fleet,
which provisioned **259 clusters in 1h49m with zero failures** on 2026-06-28. Where we deviate, the
deviation is called out and justified.

## Topology

```
per ACCOUNT (x5):
  one shared lab VPC  10.0.0.0/16
    private: 10.0.0.0/18, 10.0.64.0/18     (two AZs; ~60 clusters of headroom)
    public:  10.0.128.0/24, 10.0.129.0/24  (NAT + public LBs)
    single NAT gateway                      (1 EIP, not 50)
    subnet tags: kubernetes.io/role/elb, kubernetes.io/role/internal-elb   (role tags ONLY)
  50 x EKS cluster, each:
    1 x t3.2xlarge managed node (min=max=desired=1)
    100 GiB gp3 root  <- via block_device_mappings, NOT disk_size
    vpc-cni prefix delegation, maxPods=110
    the VTT (nginx + ttyd + status sidecar) + its 1Gi claude-home PVC + gp3 StorageClass
```

Cluster-to-account mapping is by contiguous range: account *i* owns `student[i*50+1 .. (i+1)*50]`.

## Locked decisions

### D1 — One shared VPC **per account**, not one per cluster and not one globally
50 clusters share one VPC. A node with `maxPods=110` consumes ~112 IPs; two `/18`s = 32,768 IPs holds
~60 clusters. At 50/account we use ~5,600 of 32,768. One NAT per account instead of 50 keeps EIPs at 1
(quota 5) and NAT cost flat. **Do not** put all 250 in one VPC: ~28,000 IPs leaves no room for LB ENIs.

### D2 — Per-cluster Terraform state, namespaced by account
`states/<account>/<cluster>.tfstate`. One `terraform init` against a shared module dir, N concurrent
applies differing only in `-state` and `-var`. **Deviation from Unleashed:** they used a flat
`states/<cluster>.tfstate` keyed globally by name, which forced a `NAME_OFFSET` hack to avoid collisions.
Namespacing by account removes that class of bug.

### D3 — Load balancer type for the VTT (open, gates the 250)
The VTT Service is currently a bare `type: LoadBalancer` → **Classic ELB** → quota 20/account (need 50).
Two remedies, not mutually exclusive:

- **D3a (preferred, no code):** raise `L-E9E9831D` to 100 in all five accounts. Adjustable.
- **D3b (code):** annotate into an internet-facing **ip-target NLB** (NLB quota already 100):
  ```yaml
  service.beta.kubernetes.io/aws-load-balancer-type: external
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
  service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  ```
  Requires the AWS Load Balancer Controller installed **at provisioning**, before the student's phase 1.
  Unleashed's warning applies: the older in-tree `aws-load-balancer-type: nlb` **does not work on a shared
  VPC** — it places the NLB in private subnets and the browser cannot reach it. Use `external` + the
  controller, or stay on Classic.

Canary and the 5/account gate run fine on Classic today. Decide before the 50/account push.

### D4 — Naming: `student1` … `student250`
No dashes, no zero-padding (Michael's call). Watch the **IAM `name_prefix` 38-char cap** that broke
Unleashed applies at runtime: `student250` (10 chars) plus any module suffix is far inside the limit.

### D5 — Account membership is persisted, not recomputed
Write `states/<account>/<cluster>.account` at apply time and read it on destroy/health/harvest.
**Deviation from Unleashed**, whose `down-fleet` recomputed membership from `offset + idx*n` arithmetic —
pass a different `n` than you used for `up` and you silently orphan clusters.

### D6 — `assert_ours` name guard, plus an account guard
Refuse any name not matching `^student[0-9]+$`. The accounts are shared (co-tenant Watch It Burn, plus
Michael's `adwc-dev` in `accen-dev`), so this guard is not optional. **Deviation:** Unleashed guarded the
name but nothing asserted the cluster actually lived in the target account. We assert both.

### D7 — Parallelism: 15 per account × 5 accounts = 75 concurrent
Unleashed's measured model: most of a build is an idle ~9m30s wait on the EKS control plane, so the local
binding constraint is RAM (~600 MB per build tree). Their real run used 8/account (40-wide) and finished
259 clusters in 109 minutes; the default was later raised to 15. We start at 15 and tune from the canary.

### D8 — No per-student IAM users
Unleashed minted an IAM user + access key + EKS access entry per attendee, and it was the most fragile
part of their chain (AWS returns a secret key once, forcing a persisted CSV and a recovery branch). **Our
VTT wires kubectl from the pod ServiceAccount**, so students need no AWS credentials at all. Drop the
entire subsystem.

### D9 — Provision and bootstrap in the same pool slot
`up_one` chains the VTT deploy on a successful apply, so a slot is held for the control-plane create plus
the VTT rollout. A cluster is "done" only when its terminal answers HTTP. Nothing is left as a "then run
this script" step — at 250 that step does not happen.

### D10 — Central secrets, never cross-account Secrets Manager
Unleashed crash-looped four accounts by pointing in-cluster ESO at a Secrets Manager that only existed in
the hub account. Anything secret is read on the provisioning box and pushed in. We currently need none.

## Measured expectations (from the Unleashed run, same shape)

| Metric | Value |
|---|---|
| EKS control-plane create | 9m28s – 10m9s (irreducible) |
| Managed node group | ~1m48s |
| 259 clusters, 40-wide | 109 min |
| Teardown, 25-wide | ~2h + orphan sweep |
| Cost | ~$0.43/cluster-hour → **~$107/hr at 250** |
| Orphaned LBs if drain is skipped | ~2 per cluster (**400 at 250**) |

## Known traps, pre-empted

1. **`disk_size` is silently ignored** when a custom launch template exists (cloudinit); the node falls
   back to 20 GiB and hits DiskPressure. Set the root volume via `block_device_mappings`.
2. **Drain LB Services before `terraform destroy`** or ENIs block VPC deletion and LBs bill on.
3. **Mass `DeleteLoadBalancer` gets API-throttled**; the sweep needs exponential backoff.
4. **`eks-cluster-sg-*` security groups** orphan outside Terraform state and fail `DeleteVpc` with
   `DependencyViolation`; revoke rules, then delete, then destroy the VPC.
5. **Docker Hub anonymous pulls 429 at fleet scale.** Our images are on public GHCR, but any docker.io
   reference in the student build inherits this risk.
6. **`terraform validate`/`plan` proves nothing.** Five bugs only surfaced on a real apply. The canary is
   not optional.
