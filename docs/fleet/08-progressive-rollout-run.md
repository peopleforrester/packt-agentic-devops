# 08 · Progressive rollout run (production)

The execution plan for the 250-cluster fleet. Written 2026-07-22. Treated as a
student-facing production run at every stage: each cluster that comes up is one a
student could be handed, behind `https://studentN.packt.ai-enhanced-devops.com`
with a valid certificate and a `wss://` terminal.

Ladder: **5 → 54 → 250**, additive, nothing torn down between stages.

| Stage | Live total | Shape | Proves |
|---|---|---|---|
| S1 | 5 | 1 per account × 5 | The module applies; all five accounts work; the whole chain to a working HTTPS terminal |
| S2 | 54 | accen-dev to 50, others hold at 1 | Per-account density ceiling (vCPU, ENI, LB, VPC IPs) at 1/5 the cost of finding it at 250 |
| S3 | 250 | 50 per account × 5 | The whole fleet |

Nothing comes down until S3 passes its gate. Then a full teardown and orphan sweep,
and a rebuild on event morning from the driver this run proves.

## Decisions taken for this run

| # | Decision |
|---|---|
| R1 | Fleet lifetime: prove 250, tear the clusters down, re-provision on event morning. The five lab VPCs stay up overnight (~$5) so event morning is a cluster build only. |
| R2 | S2 pushes **accen-dev to 50**, not an even 10-per-account spread. The ceilings that matter are per-account, and this finds them for the cost of 50 clusters instead of 250. |
| R3 | The DNS/TLS wildcard router is **in scope and built first**. Students get HTTPS, not raw NLB hostnames. One wildcard certificate covers all 250; per-host certs are impossible against Let's Encrypt's 50-per-domain-per-week wall. |
| R4 | Every stage is gated by a script that exits non-zero. No stage widens on a judgement call. |

## Phase A · Repo prep (no AWS spend)

A1. **Rebuild the web-terminal image.** `ghcr.io/peopleforrester/packt-agentic-devops:web-terminal`
is one commit behind `main`; the credential-store fix that keeps the Gitea password out
of `git remote -v` is not in it. Nothing provisions until this build is green, or every
student sees the password.

A2. **Fix `scripts/provision/cluster/main.tf`.** It still carries `disk_size = 80`, the
exact trap `01-architecture-and-decisions.md` lists first: silently ignored when the
module manages a launch template, so the node comes up at the 20 GiB AMI default and
DiskPressure evicts the platform. `dev-cluster/` was fixed; the fleet module was not.
Convert to `block_device_mappings` at 100 GiB. Same commit: tag node instances via the
launch template `tag_specifications` so the fleet self-tags `Workshop=packt`, and make
`profile` a required variable so no default can silently point a run at accen-dev.

A3. **Write the tests first.** Static contract tests (no cluster needed) plus the L0–L6
suite from `04-verification-tests.md`. Each fails first, for the right reason.

```
tests/test_fleet_contract.py       block_device_mappings not disk_size; root >= 100 GiB;
                                   prefix delegation + maxPods=110; log group not created;
                                   profile required; the three NLB annotations present;
                                   name guard, account-namespaced state, dry-run default
scripts/provision/fleet/tests/
  test_preflight.sh                L0
  test_cluster.sh <acct> <name>    L1 control plane ACTIVE, node Ready + L2 gp3 default,
                                   PVC Bound, VTT 3/3
  test_surface.sh <url>            L3 five endpoints, /api/status parses with numeric phase
  test_tls.sh <host>               L4 chain validates, SAN covers host, notAfter clear,
                                   http -> https redirect, wss:// upgrades 101
  test_claim.sh                    L5 pool count, claim returns a URL, idempotent, and the
                                   returned URL passes L3
  watch.sh                         L6 daemon, 3-min cadence, one line per state change
  run-gate.sh <s1|s2|s3>           the right subset per stage
```

A4. **Rewrite `fleet.sh` to the `02-fleet-driver-spec.md` contract.** Today's script is
the old single-account one: `packt-student-NNN` naming, flat state, hardcoded accen-dev,
no VTT chain, no health assertions, no guards. The rewrite carries:

- `states/<account>/<name>.tfstate` plus a `.account` membership file (D2, D5).
- `assert_ours`: name must match `^student[0-9]+$`, the account must match the persisted
  membership, and `adwc-dev` is refused by name (D6).
- `up_one` chains to a *working terminal*, not to `terraform apply` exiting 0 (D9):
  apply → isolated kubeconfig → secondary identity check (API endpoint and `Workshop`
  tag, independent of current-context) → `vtt/apply.sh` → `student-aws-creds.sh` →
  L1/L2/L3 → route registration. A cluster counts as done only when its HTTPS URL answers.
- `down_one` chains in the order that actually works: drain LoadBalancer Services and
  wait for AWS to release the NLB, delete PVCs so the CSI controller reclaims the
  volumes while it still exists, then `terraform destroy`. State file removed on success
  only, so a failure is retryable.
- Per-account subshell pools so `VPC_ID` and profile cannot leak across accounts.
- Destructive verbs are dry-run unless `PACKT_APPLY=1`.
- **Additive and idempotent `up`**: `up <account> 50` brings that account *to* 50,
  skipping names that already hold state and pass health. That is what makes the ladder
  progressive rather than three separate builds, and what lets us scale back down and up
  again without a rebuild.

Verbs: `preflight`, `vpc-up`, `up`, `up-fleet`, `health`, `routes`, `ingest`, `down`,
`down-fleet`, `sweep`, `status`, `reap --keep`.

A5. **`fleet/preflight.sh`** (L0) per `00-preflight-verification.md`: identity resolves
and the account ID matches the expected map, admin actions present, quotas meet the
stage being attempted, local tools present, lab VPC state present, and a refusal if
`adwc-dev` would be touched. `--json` for the test suite.

A6. **`fleet/sweep.sh`** per `06-teardown-and-orphan-sweep.md`, including exponential
backoff on `DeleteLoadBalancer` (mass deletes throttle) and the security-group step:
revoke ingress and egress before delete, because `eks-cluster-sg-*` groups
cross-reference each other and block `DeleteVpc`.

## Phase B · DNS and TLS router (no AWS spend, runs alongside A)

Per `03-dns-tls-spec.md`. TLS terminates at the Railway edge on one wildcard
certificate; everything inward is plain HTTP to a cluster that lives hours.

B1. New Railway service `packt-router`: Caddy with `auto_https off`, a
`map {host} {upstream}` table read from `routes.map`, and a friendly 404 for a hostname
with no match.

B2. Add the wildcard custom domain `*.packt.ai-enhanced-devops.com` to that service and
capture the three records Railway emits.

B3. Namecheap: add the `*.packt` CNAME, the `_acme-challenge.packt` CNAME, and the
ownership TXT. All three are required or the certificate never issues. The existing
`packt` CNAME (the claim app) is not touched.

B4. `fleet.sh routes` regenerates `routes.map` from the live fleet and redeploys the
router. It runs after every scale change, so the routing table can never describe a
fleet that no longer exists.

B5. `test_tls.sh` gates it, including the `wss://` upgrade. That assertion is the one
that protects the workshop: corporate proxies block plain `ws://` far more often than
`wss://`, and because the terminal is a same-origin iframe, HTTPS on the hostname
upgrades the socket with no code change.

**Hard rule, enforced in the script and the README:** never delete and recreate the
router service. Re-adding the domain forces fresh Let's Encrypt validation and new
records.

## Phase C · S1, five clusters (one per account)

1. `vpc-up` for all five accounts.
2. `up-fleet 1` → `student1` (accen-dev), `student51`, `student101`, `student151`,
   `student201`.
3. Gate `run-gate.sh s1`:
   - L1–L4 pass on all five.
   - Account isolation: each cluster resolves in the account its membership file claims,
     and nowhere else. This catches VPC-id or profile leakage across the pools.
   - Membership files exist and match reality.
   - L5: a claim through the real distribution app returns a URL that passes L3. That is
     the assertion proving the pool row and the live cluster are the same thing, which no
     other check covers.

Nothing comes down.

## Phase D · S2, accen-dev to 50 (54 live)

1. `up accen-dev 50` (adds 49; the existing `student1` is skipped, not rebuilt).
2. Gate `run-gate.sh s2`:
   - 50/50 in accen-dev pass L1–L4, and the other four accounts still pass (no regression
     from load in a sibling account).
   - No quota rejection in any apply log: NLB-per-region, vCPU, ENI.
   - Observed counts inside quota: NLB ≤ 100, vCPU 400 of 800, EKS 50 of 100.
   - VPC IP headroom sane: ~5,600 of 32,768 consumed, LB ENIs allocating without error.
   - `routes.map` has 54 entries and a random sample of 5 resolve over HTTPS.

Nothing comes down.

## Phase E · S3, 250

1. `up-fleet 50` (adds 196).
2. Gate `run-gate.sh s3`:
   - 250/250 through L1–L4 with the per-cluster failure file empty. A swallowed
     background exit code is the failure mode that makes a partial fleet look complete.
   - L5 spot-check: 3 clusters per account chosen at random (not the first N, which are
     the ones most likely to have been hand-fixed), each claimed through the real app and
     opened.
   - L6 watch running on a 3-minute cadence.
3. Regenerate `pool.csv` from the live fleet, deploy with `railway up --no-gitignore`
   from `scripts/provision/distribution`, and confirm `/admin` reports Total = 250 before
   calling the stage passed.

## Phase F · Teardown and sweep

1. `down-fleet` with the drain-first ordering.
2. `sweep` per account. Success is `eks=0 clb=0 elbv2=0 volumes=0 nat=0 eip=0`
   non-protected, with the lab VPC deliberately retained.
3. `cleanup-log-groups.sh --delete`.
4. KMS keys in `PendingDeletion` are expected and unbilled, not orphans.

The five lab VPCs stay. Event morning is `up-fleet 50` plus `routes` plus `ingest`
against a driver that has already done it once.

## Abort criteria

Stop and reassess rather than widening:

- any gate fails twice for the same reason,
- teardown leaves orphans the sweep cannot clear,
- wall-clock exceeds 2× the Unleashed baseline for the same shape, which signals
  throttling,
- the cost meter diverges from ~$107/hr at full size by more than 25%.

## Cost and wall-clock

| Stage | Live | Rate | Build |
|---|---|---|---|
| S1 | 5 | ~$2/hr | ~25 min |
| S2 | 54 | ~$23/hr | ~30 min |
| S3 | 250 | ~$107/hr | ~1h50m |
| Teardown | | | ~2h + sweep |

Baselines are the Watch It Burn run of the same shape: 259 clusters in 1h49m at 40-wide,
zero failures.
