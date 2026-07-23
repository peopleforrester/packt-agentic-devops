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

---

## Measured timings (run 1, 2026-07-22)

The numbers to plan the event morning against. All at `MAX_PARALLEL=8` per account across five
accounts, so 40 concurrent builds, on a 16-core / 62 GB host.

| Stage | Built | Wall clock | Notes |
|---|---|---|---|
| Lab VPCs, 5 accounts | 5 VPCs | **2.5 min** | run concurrently, one apply per account |
| S1: 1 per account | 5 | ~25 min | dominated by the ~10 min control-plane create |
| S2: accen-dev to 50 | 49 | ~50 min | 25-wide, single account |
| S3: all accounts to 50 | 200 | **2h 23m** | 40-wide; accen-dev already held 50 |
| Instructor cluster | 1 | **20 min** | single cluster, no contention |
| Router deploy | n/a | ~1.5 min | rebuild + redeploy of the routing table |
| Pool ingest + deploy | 250 rows | ~2.5 min | |
| Full S3 gate (L0–L5) | 250 | ~9 min | health 30-wide, TLS 30-wide |

**A from-cold 250 build is therefore roughly 2h45m at 40-wide**, plus about 15 minutes for routes,
pool and the gate. The per-cluster floor is ~22 minutes (≈13 min terraform, ≈6 min bootstrap, plus
the load-balancer wait), and that floor is irreducible; only concurrency moves the total.

### The converge pass is not optional at scale

4 of 5 accounts needed one, covering **27 of 250 clusters (11%)**, every one of them a fully built
cluster whose fresh NLB hostname had not become resolvable inside the health window. All 27 passed
on the retry. Final result: **250 ok, 0 failed.**

Without the converge pass this run would have reported 27 failures and looked like an 89% success
rate, and the natural response, re-running the whole stage, would have been both slow and wrong.

## Tag coverage after the run

`tag-audit.sh` brought one account from 451 untagged resources to 0 (903 tagged). Run
`tag-audit.sh all --fix` after **every** provisioning run and before teardown, because a resource
the sweep cannot see is a resource that bills after the event.

---

## Prompt walkthrough on a clean-room cluster (2026-07-23)

Stood up an isolated cluster, seeded its Gitea with current `main`, installed ArgoCD, and ran
the Module 1 prompts (P01–P03) as a student would. The filming build (`adwc-dev`) had masked
what follows because its foundation Applications were **suspended and hand-patched**; this was
the first from-scratch foundation sync with no intervention, and it does not cleanly converge.

### Timings

| Step | Wall clock |
|---|---|
| ArgoCD install (the opening "bootstrap exception") | **56 s** to all pods Ready |
| P01 (read manifests, explain) | read-only, no cluster wait |
| P02 (apply root-app, watch foundation) | **~7 min to 15 of 21 Healthy, then STALLS** |
| P03 fault | presents immediately and correctly |

The run-of-show budgets P02 at 20 min and claims "green in well under the 12 min gate." On a
clean cluster it does **not** reach green: three apps stay unhealthy indefinitely, two of them
for real reasons.

### P03 fault: works perfectly

Grafana pod: `ImagePullBackOff`, message `docker.io/grafana/grafana:13.0.2-hotfix: not found`.
The tag is named in the error, discoverable from the ArgoCD UI alone. The fixture is correct.
Sub-note: Grafana pulls from **docker.io** (Docker Hub), the one student-facing image that
does. Small and pulled once, but it is the lone Docker Hub dependency in the student path.

### Bug 1: the LB controller placeholder is never substituted

`platform/1-foundation/aws-load-balancer-controller/application.yaml` ships
`clusterName: REPLACE_WITH_CLUSTER_NAME`. Nothing substitutes it: a repo-wide grep finds the
string only in the file that declares it. The manifest comment says "template vpcId at
provisioning the same way clusterName is templated," but **nothing templates clusterName**.

When ArgoCD syncs this, the controller starts with a literal placeholder cluster name and no
vpcId, falls back to IMDS for the VPC, times out (`failed to fetch VPC ID from instance
metadata: context deadline exceeded`), and crash-loops. The provisioning-time `helm install` in
`vtt/apply.sh` works because it passes `--set clusterName --set vpcId --set region`, so the two
coexist: the working provisioning pods keep the VTT up while ArgoCD's revision crashes and the
Application sits Degraded forever.

Fix: substitute the real cluster name (and vpcId) into the Gitea-seeded manifest at
provisioning, per cluster. The seed step is the right place, since each cluster's name and VPC
differ.

### Bug 2: the OpenBao seed job runs as root under runAsNonRoot

`openbao-seed-demo` is `CreateContainerConfigError`: "container has runAsNonRoot and image will
run as root". Same class as the vLLM and llm-guard fixes earlier in the project: an image with a
root or non-numeric USER under a `runAsNonRoot` security context needs an explicit numeric
`runAsUser`. Blocks `openbao-config` from Healthy.

### cert-manager-issuers: likely expected

`letsencrypt-staging` ClusterIssuer stays `Ready=False` (ACME cannot validate on a throwaway
cluster with no public issuer path); `selfsigned` is Ready. Probably by design, but it shows as
Degraded in the UI and should either be removed from the foundation set or documented as
expected, so it does not read as a failure during P02.

### The meta-lesson

A build validated with suspended, hand-patched Applications does not prove the student's
from-scratch GitOps path. The only faithful test is a clean cluster syncing from an untouched
repo, exactly what a student does. Every run before the event should include one.

---

## Module 1 fully validated on a clean cluster (2026-07-23)

After fixing the bugs below, the foundation converges from scratch to **19 of 21 Applications
Healthy**, the two exceptions being the intentional P03 fault and the separately-broken
Backstage image. P03 then heals in **103 seconds** (student corrects the Grafana tag and commits,
ArgoCD self-heals). Every fix is in code and covered by a contract test; none is a hand-patch.

### The unsubstituted-placeholder class

Three manifests shipped `REPLACE_WITH_*` placeholders that **nothing substituted**. Each left an
Application permanently Degraded on a student's from-scratch sync, and each was masked on the
filming build because those Applications were suspended and hand-patched.

| Placeholder | Manifest | Consequence | Fix |
|---|---|---|---|
| `REPLACE_WITH_CLUSTER_NAME` (+ added `REPLACE_WITH_VPC_ID`) | aws-load-balancer-controller | controller crash-loops on an IMDS VPC-id timeout | seed job substitutes both from `platform-cluster-facts` |
| `REPLACE_WITH_EMAIL` | cert-manager-issuers | ACME registration fails `invalidContact` | static workshop email (no per-cluster value) |

The lesson: a `REPLACE_WITH_*` token is a landmine unless something is proven to replace it. A
repo-wide grep for `REPLACE_WITH` should return only tokens a provisioning step is known to
substitute, and a contract test should assert exactly that.

### The runAsNonRoot-without-runAsUser class (D18, again)

Three more jobs repeated the D18 defect: `runAsNonRoot: true` with no numeric `runAsUser`, on an
image whose USER is non-numeric, which kubelet rejects with `CreateContainerConfigError`.

| Job | Image user | Fix |
|---|---|---|
| openbao-config seed | uid 100 (openbao) | `runAsUser: 100`, `runAsGroup: 1000` |
| gitea-config seed | uid 100 (curl_user), gid 101 | `runAsUser: 100`, `runAsGroup: 101` (verified by running `id` in the image) |

D18 fixed this for vLLM and llm-guard but the two foundation seed jobs were never swept for the
same pattern. Any pod with `runAsNonRoot` and no `runAsUser` is suspect; verify the image's uid
rather than guessing.

### Credential drift, the exact failure the code already warned about

The gitea-config seed job hardcoded `ADMIN_PASS: workshop-dev-only` while the chart's real
password is `Workshop-Dev-Only1!`, so every API call 401'd. The **platform** seed job carries a
comment describing this precise drift and reads its creds from the `gitea-seed-creds` Secret
instead, but the gitea-config job was never given the same treatment. Both now read from that one
Secret, so they cannot disagree. When one instance of a class is fixed with "read from the single
source," grep for every other instance of the class.

### Still open: the Backstage custom image is broken

`backstage` stays Degraded for a reason no manifest fixes: the custom image
`ghcr.io/peopleforrester/backstage:2026-07-23` crashes with
`Error: Cannot find module '/app/packages/backend'`. The image build (`internal/images/backstage/
build-and-push.sh`) produced an image with no backend package, so the pod cannot start. The
PostgreSQL secret fix above was necessary but not sufficient. Backstage is the Module 1 finale
(B04, a presenter action, cuttable in the run-of-show), so this does not block P01–P03, but the
"Backstage in the browser" beat fails until the image is rebuilt correctly. Tracked as a
follow-up; it needs the image rebuilt and pushed, not a manifest change.

### ArgoCD cache when hot-patching (rehearsal only, not a workshop issue)

Hot-patching an already-synced Application meant fighting the repo-server manifest cache: a
`refresh=hard` annotation was not always enough, and a `rollout restart` of the repo-server was
sometimes needed before ArgoCD re-read the pushed revision. This is an artifact of iterating on a
live cluster; a from-cold build seeds the fixed manifests once and never hits it.
