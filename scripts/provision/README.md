# Provisioning runbook

What every provisioning tool is and **when to run it**. Read top to bottom; it is the
event lifecycle in order.

## The pieces

| Path | What it is |
|---|---|
| `../vendor-charts.sh` | Vendors every Helm chart into `charts-vendor/`. Copy, run once. |
| `../mirror-images.sh` | **Copies** every container image the platform pulls into `ghcr.io/$GHCR_ORG`. Existing images, re-hosted so 300 clusters do not hit Docker Hub limits. |
| `../../internal/images/backstage/build-and-push.sh` | **Builds** the one custom image that has no upstream (the Backstage app) and pushes it. |
| `lab-vpc/` | The shared VPC (one `/16`, `/18` subnets, one NAT). One apply **per account**. |
| `cluster/` | One student cluster (the validated t3.2xlarge shape). Not run directly. |
| `fleet/fleet.sh` | The driver. Brings each account TO a target cluster count and chains every cluster to a working HTTPS terminal. |
| `fleet/preflight.sh` | L0 gate: identity, quotas, tools, per stage. Run before every stage. |
| `fleet/routes.sh` | Regenerates the router's hostname table and deploys it. Run after every scale change. |
| `fleet/ingest.sh` | Writes `distribution/pool.csv` from the live fleet and deploys it. |
| `fleet/sweep.sh` | Orphan sweep: load balancers, volumes, security groups terraform does not own. |
| `fleet/tests/` | L1–L6 assertions plus `run-gate.sh <s1\|s2\|s3>`, the stage gate. |
| `fleet/cleanup-log-groups.sh` | Deletes orphaned EKS log groups after teardown. |
| `router/` | Caddy service mapping `studentN.packt.ai-enhanced-devops.com` to that cluster's NLB. |
| `distribution/` | The Flask app that hands a cluster's credentials to each student by email. |
| `dev-cluster/` | A throwaway single cluster for validating the platform. NOT part of the fleet. |
| `../preflight.sh` / `../smoke-test.sh` | Event-day readiness check / post-build validation. |
| `../reset/reset-to-checkpoint.sh` | Roll a cluster back to a module checkpoint. |

## mirror vs build vs vendor (the confusing three)

- **vendor-charts.sh** = Helm *charts* (the YAML templates) into the repo.
- **mirror-images.sh** = container *images* the charts reference, COPIED to GHCR. It does
  not build anything; it re-hosts what already exists upstream.
- **build-and-push.sh** = the Backstage *image*, BUILT from source because no upstream
  image carries our plugins and config.

## Order of operations

### A. One-time prep (before the event, needs GHCR write access)
```bash
./vendor-charts.sh                                  # 1. vendor charts
GHCR_ORG=peopleforrester ../mirror-images.sh        # 2. copy images to GHCR
GHCR_ORG=peopleforrester TAG=2026-07-23 \
  ../../internal/images/backstage/build-and-push.sh          # 3. build + push Backstage
# 4. (MCP "everything" image: build + push, see platform/2-ai-plane/mcp-server)
```

### B. Stand up the fleet (event-day setup)

The rollout ladder and its gates are in `docs/fleet/08-progressive-rollout-run.md`. `up` is
additive and idempotent: it brings an account **to** a count, skipping clusters that already
pass health. So the same verb grows the fleet, converges a partial one, and re-runs safely.

```bash
cd fleet
./preflight.sh s1                  # 5. L0 gate for the stage you are about to run
./fleet.sh vpc-up all              # 6. one shared VPC per account
./fleet.sh up-fleet 1              # 7. one cluster per account  (5 total)
./tests/run-gate.sh s1             #    gate: must pass before widening

./fleet.sh up accen-dev 50         # 8. density probe in one account (54 total)
./tests/run-gate.sh s2

./fleet.sh up-fleet 50             # 9. the full fleet (250)
./fleet.sh routes                  #    publish the HTTPS routing table
./fleet.sh ingest                  #    seed and deploy the claim pool
./tests/run-gate.sh s3
./tests/watch.sh &                 #    L6 continuous watch until teardown
```

### C. During and after
```bash
../smoke-test.sh                                    # validate a built platform
../reset/reset-to-checkpoint.sh <tag>               # reset between modules
cd fleet
./fleet.sh status                                   # known vs live per account
./fleet.sh reap --keep claimed.txt                  # cost lever: drop unclaimed clusters
PACKT_APPLY=1 ./fleet.sh down-fleet                 # tear down clusters (drains LBs first)
PACKT_APPLY=1 ./sweep.sh all                        # orphan sweep; add --with-vpc to drop the VPCs
./cleanup-log-groups.sh --delete                    # remove orphan log groups
```

Destructive verbs (`down`, `down-fleet`, `reap`, `sweep`) are dry-run unless `PACKT_APPLY=1`.
The lab VPCs are kept by default, so a rebuild is a cluster build only.

## GHCR access

The mirror and the image builds push to `ghcr.io/peopleforrester`. That needs a token with
`write:packages`:
```bash
gh auth refresh -s write:packages,read:packages -h github.com
```
`crane` and `docker` then use `gh auth token` to authenticate. Without this scope, pushes
return 403.
