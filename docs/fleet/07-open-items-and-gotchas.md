# Open items and gotchas before the fleet run

Written 2026-07-22, after the student terminal work and the full teardown. This is the
"pick it up cold" file: what is still owed, what will bite, and the things that were only
in a session transcript. Workshop is 2026-07-23.

## Owed before provisioning 250 clusters

### 1. Rebuild the web-terminal image (REQUIRED)

The GHCR image `ghcr.io/peopleforrester/packt-agentic-devops:web-terminal` is one commit
behind `main`. The credential-store change (keeping the Gitea password out of
`git remote -v`) landed after the last successful build, and no rebuild was triggered
because the cluster was coming down and there was nothing to deploy to.

```bash
gh workflow run build-web-terminal.yml --ref main
gh run watch $(gh run list --workflow build-web-terminal.yml --limit 1 --json databaseId -q '.[0].databaseId') --exit-status
```

The tag is mutable and the Deployment sets `imagePullPolicy: Always`, so a rebuild lands on
the next pod restart. Provision nothing until this is green, or every student gets the
password printed in `git remote -v`.

### 2. Decide on the dead `student-aws-creds` reference in the manifest

`scripts/provision/vtt/web-terminal.yaml` still has an `envFrom` entry for the
`student-aws-creds` secret. It is `optional: true`, so it is harmless, and
`student-aws-creds.sh` now deletes that secret so it cannot shadow Pod Identity. It was
left in place rather than edited with no cluster available to verify against. Either
remove it during the next live run, or leave it: it costs nothing.

### 3. The KodeKloud browser path is live and off-menu

`/browser` returns 200 on production at packt.ai-enhanced-devops.com. The landing page
links to neither "browser" nor "kodekloud", so a student never reaches it by navigation,
but a direct URL works and `/browser-claim` emails the visitor toward
`learn.kodekloud.com/user/courses/the-90-minutes-idp` (which resolves, 200). There is NO
account integration: no API key, no token, just a hardcoded hyperlink. Packt issues EKS
clusters only, so this path should be removed (`/browser`, `/browser-claim`,
`browser*.html`, and the admin browser stats). `scripts/provision/distribution/README.md`
already flags it. Low risk, but it is a wrong-turn a stray visitor can take.

## Gotchas that cost a live debug cycle each

Every one of these is now covered by `tests/test_vtt_provisioning.py`. Listed so the
reason survives, because a test tells you what broke, not why it mattered.

| Symptom | Cause | Fix |
|---|---|---|
| VTT pod stuck Pending, terminal never appears | EKS ships no default StorageClass since 1.30, so the claude-home PVC never binds | apply `gp3-storageclass.yaml` at provisioning, before the VTT |
| Whole VTT down, runc rejects the sandbox | pod-level `runAsGroup` with no `runAsUser`: "group specified without user" | set uid/gid per container; pod level gets `fsGroup` only |
| Student cannot install anything, sudo fails | `allowPrivilegeEscalation: false`; sudo is setuid | true on the ttyd container only; nginx and status stay locked down |
| Every Gitea API call 401s, helm lint passes | chart reads `admin` nested under `gitea:`; top-level is valid YAML in the wrong place | nest it, and derive the seed job's Secret from values.yaml so it cannot drift |
| A Classic ELB appears instead of an NLB | without the LB Controller annotations the in-tree provider builds Classic; quota is 20/region against a fleet need of 50/account | `aws-load-balancer-type: external` + `nlb-target-type: ip` + `scheme: internet-facing` |
| NLB unreachable on a shared VPC | the OLDER in-tree `aws-load-balancer-type: nlb` places it in PRIVATE subnets | never use the in-tree nlb value; use `external` |
| Student can commit but never push; ArgoCD never sees their change | baked clone is `--depth 1` of staging, so its refspec only requests `refs/heads/staging`; against Gitea (main only) every fetch fails behind `|| true` | clone fresh from Gitea rather than converting the shallow copy |
| `aws` has no region and every call fails | with no static-key secret the entrypoint never wrote `~/.aws/config` | write the config unconditionally, before the key guard |
| A stale credentials file silently masks a working identity | a credentials file sits AHEAD of Pod Identity in the CLI credential chain | remove it when `AWS_CONTAINER_CREDENTIALS_FULL_URI` is set |
| ArgoCD blocked at the first command | VTT ServiceAccount could not create CRDs or ClusterRoles | cluster-admin on the student's own single-tenant throwaway cluster |

## Teardown order (matters, reuse in the driver)

Delete the LoadBalancer Service and wait for AWS to actually release the NLB **before**
`terraform destroy`. Otherwise the load balancer orphans, terraform cannot delete the VPC
that holds it, and the destroy stalls late with a confusing dependency error.

```bash
kubectl -n workshop delete svc web-terminal --timeout=120s
# poll until both are 0
aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text
aws elb   describe-load-balancers --query 'length(LoadBalancerDescriptions)' --output text
terraform destroy -auto-approve
```

Then sweep what terraform does not own: the `packt-student-<cluster>` role and its inline
policy, and any detached gp3 volumes left by PVCs.

Do not diagnose a slow destroy from `tail -1` of the log. Terraform interleaves resources,
so the last line can be an old "Still destroying" for one resource while others finish.
Check the AWS API instead (`aws eks describe-nodegroup ... --query nodegroup.status`) and
confirm the log is still growing.

## Account facts

| Profile | Account | Alias |
|---|---|---|
| accen-dev | 515966504359 | was-aws-developer11 |
| aws1-student31 | 948731545609 | aws1-student31 |
| aws1-student32 | 891472436879 | aws1-student32 |
| aws1-student33 | 250699659274 | aws1-student33 |
| aws1-student34 | 783241407859 | aws1-student34 |
| kcd-instructor | 771128797125 | webage-cloudlabs |

All are WebAge/Accenture accounts, IAM user `nwuser` (Instructor on kcd-instructor). None
of them are KodeKloud. `kcd-instructor` was confirmed still functional.

Classic-LB quota is 20 per region against a fleet need of 50 per account. This only gates
the rollout if anything falls back to Classic. With the NLB annotations in place nothing
should, which is why the annotations have a test.

## The scoping finding, in one paragraph

Read `internal/research-student-aws-scope-july-2026.md` for the full version with sources.
Short form: Pod Identity resolves by (namespace, ServiceAccount) and does not check which
workload is using it, so a cluster-admin student can run a pod as the
`aws-load-balancer-controller` ServiceAccount and get that role. Proven on adwc-dev. The
student's AWS reach is therefore the union of all pod identity roles on their cluster, and
scoping the terminal role tighter does not shrink it. AWS tag-scopes `DeleteLoadBalancer`
and `DeleteTargetGroup` but leaves listeners, rules, and security-group ingress at
`Resource: "*"` with no condition, so at ~50 clusters per account a determined student can
reach other students' load balancers. Nobody can launch compute (no `ec2:RunInstances`, no
`iam:PassRole`, Karpenter excluded). Decision for 2026-07-23: change nothing, because every
fix touches a call the controller makes whenever a Service is created or deleted, and the
failure would appear mid-workshop across all 250 clusters. Containment is the AWS account.

## Process note

A subagent dispatched for the scoping research returned nothing and only emitted idle
pings. The knowledge repo it was told to write to
(`~/repos/peopleforrester/mrf-knowledge`) is not cloned on this machine, which probably
stalled it, but it never said so. Check that a delegated target path exists before
dispatching, and treat an empty subagent result as a failure to redo, never as a finding.
