# Provisioning runbook

What every provisioning tool is and **when to run it**. Read top to bottom; it is the
event lifecycle in order.

## The pieces

| Path | What it is |
|---|---|
| `../vendor-charts.sh` | Vendors every Helm chart into `charts-vendor/`. Copy, run once. |
| `../mirror-images.sh` | **Copies** every container image the platform pulls into `ghcr.io/$GHCR_ORG`. Existing images, re-hosted so 300 clusters do not hit Docker Hub limits. |
| `../../internal/images/backstage/build-and-push.sh` | **Builds** the one custom image that has no upstream (the Backstage app) and pushes it. |
| `lab-vpc/` | The shared VPC (one `/16`, `/18` subnets, one NAT). `terraform apply` once. |
| `cluster/` | One student cluster (the validated t3.2xlarge shape). Not run directly. |
| `fleet/fleet.sh` | Stamps out N student clusters from `cluster/` against the shared VPC. |
| `fleet/cleanup-log-groups.sh` | Deletes orphaned EKS log groups after teardown. |
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
```bash
cd lab-vpc && terraform init && terraform apply     # 5. shared VPC, once
cd ../fleet && ./fleet.sh up 60                     # 6. N student clusters
# 7. build pool.csv from the fleet credentials, then:
cd ../distribution && uv run python app.py          # 8. run credential distribution
KUBECONFIG_FILE=... EXPECTED_CONTEXT=... ../../preflight.sh   # 9. verify ready
```

### C. During and after
```bash
../../smoke-test.sh                                 # validate a built platform
../reset/reset-to-checkpoint.sh <tag>               # reset between modules
cd fleet && ./fleet.sh down all                     # tear down clusters
./cleanup-log-groups.sh --delete                    # remove orphan log groups
cd ../lab-vpc && terraform destroy                  # remove the shared VPC last
```

## GHCR access

The mirror and the image builds push to `ghcr.io/peopleforrester`. That needs a token with
`write:packages`:
```bash
gh auth refresh -s write:packages,read:packages -h github.com
```
`crane` and `docker` then use `gh auth token` to authenticate. Without this scope, pushes
return 403.
