# 00 · Preflight verification (evidence, not assumptions)

Everything here was verified against the live AWS APIs on 2026-07-21, not inferred. Re-run
`scripts/provision/fleet/preflight.sh` to reproduce; it is the executable form of this document.

## Accounts

Six profiles exist locally. Five carry the fleet; the sixth is a spare.

| Profile | Account ID | IAM principal | Policies | EKS | LBs | VPCs |
|---|---|---|---|---|---|---|
| `accen-dev` | 515966504359 | `user/nwuser` | AdministratorAccess | 1 | 1 CLB / 2 v2 | 3 |
| `aws1-student31` | 948731545609 | `user/nwuser` | AdministratorAccess | 0 | 0 | 1 |
| `aws1-student32` | 891472436879 | `user/nwuser` | AdministratorAccess | 0 | 0 | 1 |
| `aws1-student33` | 250699659274 | `user/nwuser` | AdministratorAccess | 0 | 0 | 1 |
| `aws1-student34` | 783241407859 | `user/nwuser` | AdministratorAccess | 0 | 0 | 1 |
| `kcd-instructor` | 771128797125 | `user/Instructor` | AdministratorAccess, IAMUserChangePassword | 0 | 0 | 1 |

Findings:

- **All five fleet accounts have full admin.** No permission work is required.
- **`kcd-instructor` is alive and admin-capable**, contrary to expectation. It is NOT in the fleet
  plan; it is held as a spare capacity account (adds a 6th × 50 = 300 headroom if needed).
- **`accenture-workshop` is dead** (`InvalidClientTokenId`). Ignore it.
- **`accen-dev` is not empty**: 1 EKS cluster (`adwc-dev`, Michael's, explicitly out of scope), 1 Classic
  ELB (that cluster's VTT), 3 VPCs. Every fleet count for `accen-dev` must subtract this pre-existing load.

## Region

`us-west-2` for all accounts, matching the Unleashed fleet and the existing `adwc-dev`.

## Service quotas (per account, us-west-2)

Required column assumes the target of 50 clusters per account, 1 node each (`t3.2xlarge` = 8 vCPU).

| Quota | Code | Applied (all 5) | Needed | Status |
|---|---|---|---|---|
| Running On-Demand Standard vCPUs | `L-1216C47A` | 800 | 400 | OK |
| Application LBs per Region | `L-53DA6B97` | 100 | 50 | OK |
| Network LBs per Region | `L-69A177A2` | 100 | 50 | OK |
| **Classic LBs per Region** | `L-E9E9831D` | **20** | **50** | **SHORT** |
| EKS clusters per Region | `L-1194D53C` | 100 | 50 | OK |
| VPCs per Region | `L-F678F1CE` | 5 | 1 | OK |
| Elastic IPs | `L-0263D0A3` | 5 | 1 | OK |

The ALB/NLB/vCPU values are already raised — these are the increases filed for the Unleashed fleet on
2026-06-27 and they persist per account. **Only the Classic-LB quota is short**, and it is marked
`Adjustable: true`.

### Why Classic-LB matters and what it gates

Our VTT Service (`scripts/provision/vtt/web-terminal.yaml`) is a bare `type: LoadBalancer` with no
annotations. On EKS the legacy in-tree provider turns that into a **Classic ELB**, one per cluster. This
is the identical trap Unleashed hit and documented: *"the un-annotated `console` Service builds a Classic
ELB"*, and separately *"Skipping [LB drain] orphans ~2 LBs per cluster ... observed: 100 orphaned LBs per
account after a fleet teardown."*

Consequences, by rollout stage:

| Stage | CLBs per account | Fits quota 20? |
|---|---|---|
| Canary (1 cluster) | 1 | Yes |
| 5 per account (25 total) | 5 | Yes |
| **50 per account (250 total)** | **50** | **No** |

So the canary and the 5-per-account gate can proceed **immediately with no quota change**. Only the final
50/account push is blocked. Two independent remedies, tracked in `01-architecture-and-decisions.md` (D3):

1. Raise `L-E9E9831D` to 100 in all five accounts (adjustable, no code change), and/or
2. Annotate the VTT Service into an internet-facing ip-target **NLB**, which uses the already-raised
   NLB quota of 100. This requires the AWS Load Balancer Controller present at provisioning time.

## What is explicitly out of scope

- `scripts/provision/dev-cluster/` and the running `adwc-dev` cluster. Michael's. The fleet driver must
  never read or write that Terraform state, and `assert_ours` must refuse the name.
- The `accenture-workshop` profile (dead credentials).

## Reproducing

```bash
scripts/provision/fleet/preflight.sh            # prints the tables above, exits non-zero on any gap
scripts/provision/fleet/preflight.sh --json     # machine-readable, for the test suite
```
