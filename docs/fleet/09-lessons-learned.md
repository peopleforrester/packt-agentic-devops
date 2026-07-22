# 09 · Lessons learned, fleet run 2026-07-22

A running log, appended as the rollout proceeds. Every entry is something that actually happened
on this run, with the symptom first, because a symptom is what you will recognise next time.

The theme so far: **`terraform validate`, `plan`, and shellcheck all passed on code that was
broken in five different ways.** Every defect below needed real infrastructure and a real request
to surface. That is the entire argument for the canary stage.

---

## Defects that would have reached students

### 1. The router dialled port 0 on every request

**Symptom:** valid certificate, correct SAN, HTTP redirecting properly, and every page a 502.
Router log: `dial tcp 184.34.19.222:0: i/o timeout`.

**Cause:** `reverse_proxy {upstream}` where `{upstream}` is a placeholder does **not** default to
port 80. Caddy dials port 0.

**Fix:** put the port in the map value (`<nlb-host>:80`), not in the `reverse_proxy` line.

**Related:** Caddy also rejects a placeholder upstream that carries a scheme
(`reverse_proxy http://{upstream}` fails to parse). No scheme, explicit port.

### 2. The sweep would have destroyed live clusters

**Symptom:** a dry run against a populated account listed the `eks-cluster-sg-*` groups of five
**running** clusters as orphans to revoke and delete.

**Cause:** the sweep is written for a post-teardown account and identifies orphans structurally
(everything of a given shape inside the lab VPC). Nothing enforced that teardown had happened.
Run at the wrong moment it severs every node's networking and deletes live load balancers.

**Fix:** a hard guard that refuses to sweep an account with live student clusters, overridable
only by an explicit `SWEEP_FORCE=1`. Operator discipline is not a control.

### 3. The sweep silently dropped the last resource in every list

**Symptom:** one NLB present in the lab VPC, sweep reported nothing to delete.

**Cause:** the retry helper ended with `printf '%s' "${out}"`. Command substitution strips the
trailing newline, and a `while read` loop handed a final line without one **sets the variable but
returns non-zero**, so the body never runs for that element:

```
printf 'a\nb\nc'   | while read -r x; ... -> processes 2 of 3
printf 'a\nb\nc\n' | while read -r x; ... -> processes 3 of 3
```

Every list in the sweep is consumed that way, so the last load balancer, target group, volume and
security group were always skipped. With exactly one of something, that is all of them, and the
account reports clean while the resource keeps billing.

**Fix:** `printf '%s\n'`. Worth grepping any script for `printf '%s' "$(...)"` feeding a loop.

### 4. `disk_size` is ignored, so nodes came up at 20 GB

Known and already fixed in `dev-cluster/`, but the **fleet** module still carried it. When the EKS
module manages a launch template, `disk_size` is silently dropped and the node takes the AMI
default of 20 GB. DiskPressure then evicts the platform while terraform reports success.

**Fix:** `block_device_mappings`. Verified live: 50 GB gp3, 110 allocatable pods.

### 5. Node instances were invisible to the orphan sweep

Managed node groups do **not** propagate provider `default_tags` to EC2 instances or their
volumes, because launch-template `tag_specifications` are data inside the template rather than
resources the provider tags. Previously tagged by hand; at 250 that does not happen, and the sweep
filters on `Workshop=packt`.

**Fix:** `launch_template_tags` plus explicit `tag_specifications`. Verified: the node's volume now
carries `Student=student1`.

---

## Test defects, which are worse than they look

A broken test either hides a real failure or invents a fake one. Both cost a debug cycle at the
moment you can least afford it.

### 6. Two different waits sharing one budget

`up_one` polled "is the surface healthy" on a single timer that started before the NLB even
existed. The clock was half spent waiting for AWS to assign the load balancer, leaving too little
for the DNS propagation that only **starts** at that point, so a perfectly healthy cluster recorded
a failure. Separate the wait for assignment from the wait for resolution, and log progress so a
slow cluster is visible rather than failing silently at the boundary.

### 7. `|| echo 000` on top of `%{http_code}`

curl already writes `000` via `%{http_code}` when a request fails, so the fallback appended a
second value and produced the status `000000`. Harmless to the comparison, actively misleading in
the failure message. Let curl own the value; swallow only its exit code.

### 8. Websocket checks must pin HTTP/1.1

`curl` negotiated HTTP/2 via ALPN, where the upgrade handshake is not valid, and the edge answered
404. This read as "the terminal is broken" for a terminal that was working perfectly. Browsers open
websockets over HTTP/1.1; the test must too.

### 9. A test that aborts silently reports nothing, and the gate calls it a failure

The claim test died after its first assertion with no error. The `railway` CLI resolves its project
from the working directory, and the test ran from `fleet/tests`. Under `set -euo pipefail` the
failed call inside a command substitution killed the script mid-run. Any external CLI in a test
needs its exit code contained.

### 10. Grepping a page for a bare number passes for the wrong reason

The pool-size check grepped the whole admin HTML for `5`, which matches the claimed count, a
region, a timestamp, anything. It passed initially by luck and failed later for an unrelated
reason. Parse the specific field. A check that can pass accidentally is not a check.

### 11. `readonly FLEET_DIR` before sourcing the library

The test scripts declared the variable readonly, then `lib.sh` assigned it and the source failed.
Let the library own its own variables.

---

## Assumptions that were wrong

### 12. Concurrency is CPU-bound on the provisioning host, not RAM-bound and not API-bound

The design assumed ~600 MB per terraform build tree and sized parallelism around memory. Measured
at 25-wide: **90 MB average RSS, 2.1 GB total, 40 GiB still free.** That is 6.7x pessimistic, so
memory is not the constraint.

Neither is the AWS API: zero throttling errors across 26 concurrent cluster builds in one account.

The actual constraint is **local CPU**. At 25 concurrent builds on a 16-core host:

```
load average: 29.9        (~1.9x core count)
%Cpu(s): 67.6 us, 20.4 sy, 10.9 id    -> 88% busy
```

Load average alone would have been misleading, since it counts network-blocked processes; the
`%idle` figure is what confirms real saturation. The cost is concentrated in the **bootstrap**
phase (helm, kubectl, and an `aws eks get-token` credential exec on every kubectl call), not in the
~10 minute control-plane wait, which is nearly idle. So load is bursty and gets worse when many
clusters reach the bootstrap phase together, which is exactly what a single-account wave does.

Consequence for sizing: total concurrency across **all** accounts is the number that matters, not
per-account. Oversubscribing does not just slow things down, it risks tripping the fixed timeouts
in the bootstrap chain (`helm --wait --timeout 10m`, `kubectl rollout status --timeout=180s`) and
turning contention into spurious cluster failures. Running five accounts naturally desynchronises
the phases, which helps, but the ceiling is still the host.

### 13. The Docker Hub rate-limit risk is already retired

Listed as a standing trap for fleet scale. In practice every image pulled at provisioning comes
from in-region ECR (`602401143452.dkr.ecr...`), `public.ecr.aws`, or Gitea's own
`docker.gitea.com`. Docker Hub is not in the path. Worth re-checking whenever an image changes,
but it is not a live risk today.

---

## Operational notes

### 14. `railway up` respects `.gitignore`

The rendered `Caddyfile`, `routes.map` and `pool.csv` are all generated and therefore gitignored,
which is exactly what the deploy needs to ship. Without `--no-gitignore` the router deploys with no
routing table and the claim app seeds zero clusters. `.railwayignore` then becomes the only ignore
list.

### 15. Validate generated config at build time

The router's Dockerfile runs `caddy validate`. It caught a malformed config and failed the build
instead of deploying a router that would have taken every student offline at once. Any generated
config should be validated in the build that ships it.

### 16. Namecheap `setHosts` replaces the entire zone

It is not additive. The zone carries live workshop email (Resend DKIM, SPF, DMARC, an SES MX) and
the claim app's own record, so the change was scripted to read the current zone, reconstruct every
record, add only what was missing, and refuse if anything it expected to preserve had gone. Backup
first, diff, then apply: 11 preserved, 2 added, 0 removed.

### 17. Check what already exists before creating it

The `_railway-verify.packt` TXT record Railway asked for was already present with the exact same
token, from an earlier attempt. Reading the zone first turned a "create three records" job into
"add two".

---

## 18. Most fleet infrastructure is not tagged by whatever created it

Audit of one account holding 50 clusters: **451 resources carried no `Workshop` tag.**

| Resource | Tagged by | Was it tagged? |
|---|---|---|
| EKS clusters, VPC, subnets, NAT, IAM roles | terraform `default_tags` | yes |
| EC2 instances, root volumes | launch template `tag_specifications` | yes (after an earlier fix) |
| Load balancers, target groups | LB controller annotation | yes |
| **PVC volumes** | EBS CSI driver | **no** (100) |
| **Network interfaces** | VPC CNI | **no** (201) |
| **`eks-cluster-sg-*` groups** | EKS itself | **no** (100) |
| **Control-plane log groups** | EKS itself | **no** (50) |

Terraform `default_tags` only reach what terraform creates. Everything provisioned by a Kubernetes
controller or by EKS itself is outside that, and each one needs its own mechanism. There is no
single switch.

This matters because the orphan sweep selects on `Workshop=packt`. Untagged infrastructure is
infrastructure the sweep cannot see, and what it cannot see bills after the workshop ends. Scaled to
the full fleet that is roughly 2,250 resources, including 500 EBS volumes.

`scripts/provision/fleet/tag-audit.sh <account|all> [--fix]` audits every taggable type and repairs
what is missing. It refuses to touch anything not provably ours: an EKS name matching
`^student[0-9]+$`, membership of the lab VPC, a `kubernetes.io/cluster/student<N>` tag, or the
fleet's IAM naming scheme. Anything else is reported and left alone, because these accounts are
shared with a co-tenant project.

**Run `tag-audit.sh all --fix` after every provisioning run, before teardown.** The source-level
fixes (StorageClass `tagSpecification_*`, CNI `ADDITIONAL_ENI_TAGS`) reduce what it has to repair
but cannot cover resources EKS creates for itself, notably the log groups, which exist precisely
because `create_cloudwatch_log_group = false` keeps a reused cluster name from colliding.
