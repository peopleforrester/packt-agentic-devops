# Fleet: 250 student clusters across 5 AWS accounts

Plan of record for provisioning the Packt workshop fleet. Grounded in the Watch It Burn fleet, which
provisioned **259 clusters in 1h49m with zero failures** on 2026-06-28; every deviation from that design
is stated and justified rather than improvised.

## Documents

| Doc | Contents |
|---|---|
| [00-preflight-verification.md](00-preflight-verification.md) | Verified accounts, quotas, permissions. Evidence, not assumptions. |
| [01-architecture-and-decisions.md](01-architecture-and-decisions.md) | Topology and the ten locked decisions (D1–D10) |
| [02-fleet-driver-spec.md](02-fleet-driver-spec.md) | The driver: commands, parallelism, safety guards |
| [03-dns-tls-spec.md](03-dns-tls-spec.md) | Wildcard cert, router, `wss://`, Namecheap rules |
| [04-verification-tests.md](04-verification-tests.md) | The test suite (L0–L6) and the 3-minute watch |
| [05-rollout-gates.md](05-rollout-gates.md) | G0→G4 gates: preflight, canary, 25, 50, 250 |
| [06-teardown-and-orphan-sweep.md](06-teardown-and-orphan-sweep.md) | Teardown order and the orphan sweep |

## Shape

- **250 clusters = 5 accounts × 50.** `accen-dev`, `aws1-student31/32/33/34`. All verified admin.
- **One shared VPC per account**, ~50 clusters inside it, single NAT.
- **`student1` … `student250`**, contiguous ranges per account.
- **1 × t3.2xlarge per cluster**, 100 GiB gp3 root, prefix delegation, maxPods 110.
- **Each cluster ships the VTT** (two-pane lab + terminal) and is "done" only when its terminal answers.
- **HTTPS via one wildcard cert** on a Caddy router; per-host certs are impossible (LE 50/week/domain).
- **No per-student IAM users** — the VTT wires kubectl from its ServiceAccount.

## Current status

| Item | State |
|---|---|
| Accounts + admin verified | Done — 5 fleet accounts + `kcd-instructor` spare, all AdministratorAccess |
| Quotas verified | Done — vCPU/ALB/NLB/EKS/VPC/EIP all sufficient |
| **Classic-LB quota** | **BLOCKER for G3/G4 only**: 20 applied, 50 needed, adjustable. Canary and 25 fit. |
| Fleet driver | Not built |
| DNS + TLS router | Not built |
| Test suite | Not built |
| Canary | Not run |

## Known blocker

The VTT's bare `type: LoadBalancer` creates a **Classic** ELB (quota 20/account, need 50). Fix by raising
`L-E9E9831D` to 100 in all five accounts, and/or annotating the Service into an internet-facing ip-target
NLB (NLB quota is already 100). Note the in-tree `aws-load-balancer-type: nlb` annotation **does not work
on a shared VPC** — it lands the NLB in private subnets, unreachable. See D3.

## Out of scope, do not touch

`scripts/provision/dev-cluster/` and the running `adwc-dev` cluster are Michael's. The driver's
`assert_ours` refuses any name that is not `^student[0-9]+$`, which excludes it by construction.

## Costs

~$0.43 per cluster-hour (node + EKS control plane + storage) → **~$107/hour at 250**. An 18-hour warm
window is ~$2,000. `reap` trims unclaimed clusters once the real headcount is known.
