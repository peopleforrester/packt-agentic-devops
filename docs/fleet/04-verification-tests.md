# 04 · Verification and test suite (TDD)

The rule: **never trust AWS's own "success" signal.** `terraform apply` exiting 0 means Terraform is
happy, not that a student can open a terminal. Every gate below asserts the property we actually care
about, from outside, and re-asserts it on a timer so drift is caught while there is still time to fix it.

Tests are written **before** the thing they verify, and every one of them must fail first for the right
reason.

## Layers

| Layer | Question it answers | Runs |
|---|---|---|
| L0 Preflight | Can we even build? Accounts, quotas, permissions, tools. | Before anything, and on every gate |
| L1 Cluster | Is the control plane live and the node Ready? | Per cluster, at build |
| L2 Platform floor | StorageClass, PVC bound, VTT pods Ready | Per cluster, at build |
| L3 Student surface | Does the terminal actually answer over the network? | Per cluster, at build + continuous |
| L4 TLS | Valid cert, correct SAN, HTTPS + `wss://` | Per hostname, at build + continuous |
| L5 Claim flow | Pool seeded, claim returns the right URL, idempotent | Fleet-wide, after ingest |
| L6 Continuous | Is all of the above *still* true? | Every 3 min until teardown |

## L0 — Preflight (`fleet/preflight.sh`)

Asserts, per account, exiting non-zero on any failure:

- `sts get-caller-identity` resolves and the account ID matches the expected map.
- The principal has admin (or at least the concrete actions: eks:*, ec2:*, elasticloadbalancing:*).
- Quotas meet the requirement for the **stage being attempted** (canary/25/250 have different CLB needs).
- Local tools present: `terraform`, `kubectl`, `aws`, `jq`, `curl`.
- The shared lab VPC state exists for the account (or is the documented default-account case).
- **Refuses to proceed if `adwc-dev` would be touched.**

## L1 — Cluster liveness

Not "terraform said ok". Assert from the API and the cluster itself:

```
aws eks describe-cluster --name <c> --query 'cluster.status'   == ACTIVE
kubectl get nodes                                              >= 1 node in Ready
kubectl version                                                server minor == 1.35
```

## L2 — Platform floor

This is where the fresh-cluster rebuild caught a real fleet-blocker (no default StorageClass on a fresh
EKS since 1.30, so the VTT PVC hung Pending and the terminal never started):

```
kubectl get storageclass gp3 -o jsonpath='{...is-default-class}'   == "true"
kubectl -n workshop get pvc student-claude -o jsonpath='{.status.phase}'  == Bound
kubectl -n workshop get deploy web-terminal                        3/3 containers Ready
```

## L3 — Student surface (the one that matters)

Poll the URL a student would actually open, from outside the cluster:

```
GET  <base>/           -> 200 and body contains "This cluster is yours"
GET  <base>/terminal/  -> 200 and body contains "ttyd"
GET  <base>/diagram    -> 200
GET  <base>/links      -> 200
GET  <base>/api/status -> 200 and parses as JSON with a numeric "phase"
```

`/api/status` doubles as a liveness probe for the status sidecar **and** proves cluster read access is
working, since the sidecar can only answer if its ServiceAccount can read the API.

## L4 — TLS (must fail before the router exists)

Per student hostname:

```
openssl s_client -connect <host>:443 -servername <host>
  -> cert chain validates
  -> SAN covers <host>            (wildcard *.packt.ai-enhanced-devops.com)
  -> notAfter is > event date + 7 days
curl -sS https://<host>/          -> 200, no TLS error
curl -sS http://<host>/           -> 301/308 to https
websocket: wss://<host>/terminal/ -> upgrade succeeds (101)
```

The websocket assertion is the one that actually protects the workshop: corporate proxies block plain
`ws://` far more often than `wss://`. Because the terminal is a same-origin iframe under one hostname,
HTTPS on that host upgrades the socket to `wss://` with zero code change — so this test is really
asserting "the hostname is HTTPS", and it must be verified, not assumed.

## L5 — Claim flow

```
GET  /healthz                       -> 200
GET  /admin/export?token=...        -> row count == expected fleet size
POST /eks-claim  (fresh email)      -> 200, body contains an https://studentN... URL
POST /eks-claim  (same email again) -> 200, SAME cluster (idempotence)
follow the returned URL             -> L3 assertions pass against it
```

The last line is the important one: it proves the pool's URL and the live cluster are the same thing. A
pool row pointing at a dead or wrong cluster is the failure mode that ruins a workshop, and it is
invisible to every other check.

## L6 — Continuous watch (every 3 minutes)

A daemon that re-runs L1–L4 across the fleet on a 3-minute cadence and emits **one line per state
change**, not per poll. It must alarm on:

- any cluster that was ACTIVE and is no longer,
- any VTT that stops answering 200,
- any TLS cert within 7 days of expiry,
- any `/api/status` that stops parsing,
- **fleet size drift**: live cluster count != expected.

Design rules learned the hard way: the filter must match failure signatures, not just success, or a
crashloop looks identical to "still running". Silence must mean healthy, and that only holds if failures
are guaranteed to print.

## Sampling at scale

Full L1–L4 across 250 clusters every 3 minutes is ~1,000 HTTP calls plus 250 EKS describes. That is
fine for HTTP but will throttle the AWS APIs. So:

- **HTTP checks (L3/L4): all 250, every cycle.** They are cheap and they are the student's reality.
- **AWS API checks (L1): one `list-clusters` per account per cycle** (5 calls) for the count, with
  per-cluster `describe` only for clusters that failed an HTTP check.

This inverts the usual instinct on purpose: the network surface is the source of truth, and AWS is only
consulted to explain a failure we already detected.

## Test artifacts

```
scripts/provision/fleet/tests/
  test_preflight.sh        L0
  test_cluster.sh <name>   L1 + L2
  test_surface.sh <url>    L3
  test_tls.sh <host>       L4
  test_claim.sh            L5
  watch.sh                 L6 daemon (3-min cadence, state-change events only)
  run-gate.sh <stage>      runs the right subset for canary | acct5 | full
```

Every one exits non-zero on failure and prints the specific assertion that failed with the observed
value. No test prints "OK" without having made an assertion.
