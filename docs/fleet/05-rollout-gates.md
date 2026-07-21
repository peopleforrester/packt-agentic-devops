# 05 · Progressive rollout gates

Four stages. **Each gate must pass before the next stage starts**, and each gate is a script that exits
non-zero, not a judgement call. If a gate fails, we fix and re-run that stage; we never widen on a
yellow.

The point of the ladder is that each stage tests something the previous one could not:

| Stage | Size | What it proves that the previous stage could not |
|---|---|---|
| G0 Preflight | 0 clusters | Accounts, quotas, permissions, tooling |
| G1 Canary | 1 cluster, 1 account | The module actually applies; the VTT serves; teardown is clean |
| G2 Spread | 5 per account = **25** | All five accounts work; cross-account isolation; parallelism |
| G3 Scale probe | 50 in **one** account | Per-account quota ceilings under real load |
| G4 Full | 50 × 5 = **250** | The whole fleet |

## G0 — Preflight

Run `fleet/preflight.sh` for every account. Gate: exit 0 for all five.

Blocking item today: **Classic-LB quota is 20, need 50** (see `00-preflight-verification.md`). This does
**not** block G1 or G2 (they need 1 and 5). It blocks G3/G4. Resolve via D3a (raise to 100) or D3b
(annotate to NLB) before G3.

## G1 — Canary (1 cluster)

One cluster in `accen-dev`, named `student1`. This is the stage that catches what `terraform plan` cannot;
Unleashed found five separate bugs that only appeared on a real apply.

Gate (all must pass):
1. L1 cluster ACTIVE, node Ready, k8s 1.35.
2. L2 gp3 default StorageClass, PVC Bound, VTT 3/3.
3. L3 all five endpoints answer; `/api/status` returns `phase:0` with a near-empty `up[]` — proving the
   Blueprint reports honestly on a bare cluster rather than false-greening.
4. **Teardown is clean**: destroy, then the orphan sweep reports `eks=0 clb=0 elbv2=0 vols=0` for the
   cluster's resources, with no leaked security groups blocking the VPC.
5. **Then rebuild it**, to prove the cycle is repeatable rather than a one-shot.

Do not proceed on a partial pass. A canary that "mostly worked" is the most expensive kind of pass.

## G2 — Spread (5 per account, 25 total)

Five clusters in each of the five accounts, concurrently. This is the first test of the things that only
exist across accounts.

Gate:
1. All 25 pass L1–L3.
2. **Account isolation**: each cluster resolves in the account its state says it does. Assert that
   `student1..5` exist in `accen-dev` and nowhere else, and so on. This catches the class of bug where a
   VPC id or profile leaks across the per-account subshells.
3. **Membership persistence** (D5): `states/<account>/<cluster>.account` exists and matches reality for
   all 25.
4. **Parallelism holds**: no throttling errors in any apply log; wall-clock consistent with ~10 min of
   control-plane create rather than serialized.
5. Pool ingest produces 25 rows and a claim returns a working URL (L5).
6. Teardown all 25 clean, orphan sweep zero across all five accounts.

## G3 — Scale probe (50 in one account)

Before committing 250, push a **single** account to the target density. This is the cheapest way to find
a per-account ceiling, and the ceilings are per-account, not global.

Gate:
1. 50/50 clusters pass L1–L3.
2. **No quota rejection** in any log: watch specifically for LB-per-region, vCPU, ENI.
3. Observed counts land inside quota: CLBs (or NLBs) ≤ quota, vCPU = 400 of 800, EKS 50 of 100.
4. VPC IP headroom sane: ~5,600 of 32,768 used, LB ENIs allocating without error.
5. Teardown clean, including the SG-revoke step that Unleashed found blocks `DeleteVpc`.

If this fails on load balancers, that is D3 asserting itself and the fix is known.

## G4 — Full fleet (250)

All five accounts, 50 each, concurrent.

Gate:
1. 250/250 through L1–L3, with the failure list empty (a per-cluster failure file, not a swallowed exit
   code — Unleashed's bug #15).
2. L4 TLS green for every hostname.
3. L5 claim flow: pool has 250 rows, spot-check claims across **all five** accounts resolve to a working
   terminal in the right account.
4. L6 continuous watch running on a 3-minute cadence for the remainder.

Expected wall-clock, from the Unleashed run of the same shape: **~1h50m** at 75-wide including bootstrap.
Budget the same again for teardown plus the orphan sweep.

## Spot-check protocol (G4)

Random sample, not the first N (the first N are the ones most likely to have been hand-fixed):

- 3 clusters per account (15 total), chosen at random from the live list.
- For each: full L1–L4, then claim its URL through the real claim app and open the terminal.
- Any single failure demotes the fleet to "investigate", not "ship".

## Abort criteria

Stop and reassess rather than pushing on, if:

- any gate fails twice for the same reason,
- teardown leaves orphans that the sweep cannot clear,
- provisioning wall-clock exceeds 2× the Unleashed baseline (signals throttling),
- the cost meter diverges from ~$107/hr at full size by more than 25%.
