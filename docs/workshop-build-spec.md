# Workshop Build Spec: Agentic DevOps with Claude

You are going to build an AI-native Internal Developer Platform on Kubernetes, with Claude Code
doing the platform engineering. This file is your input. You will not be handed the finished YAML;
you will generate it, guided by this spec, and deploy it through GitOps. When you get stuck, there
is a reference build in `solution/` you can fall back to (see "When you are stuck").

This is the primary path. The `solution/` directory is the safety net, not the starting point.

---

## 1. What you are building

A GitOps-driven platform where ArgoCD reconciles everything from Git, in two planes:

- **Foundation plane** (cloud-native): ArgoCD and the Argo stack, cert-manager, External Secrets +
  OpenBao, Kyverno, the observability stack (Prometheus, Grafana, Loki, Tempo, OpenTelemetry),
  KEDA, and Backstage as the developer portal. On EKS the ingress and load-balancer path is the
  **AWS Load Balancer Controller** and storage is the **AWS EBS CSI driver**.
- **AI plane**: kgateway and agentgateway (the agentic data plane), kagent (agents as Kubernetes
  resources), LLM Guard, OpenLLMetry with OpenTelemetry GenAI semantic conventions, KServe with
  vLLM for in-cluster model serving, and llm-d.

The exact component set and pinned versions are in `components.yaml` and `versions.lock.md`. Those
files are given to you: they are the sourcing. Do not invent versions; read them.

Your cluster starts bare. By the end it is a running, observable, governed platform, deployed the
same way real platforms are: manifests in Git, ArgoCD syncing them, you fixing what does not
converge.

---

## 2. How to work: the loop

For every component, and every module, work in this loop. Do not skip the validation and test
steps; they are what keep a 33-component build from turning into a debugging swamp.

1. **Read** the relevant section of this spec and the component's row in `components.yaml`.
2. **Plan** in one or two sentences what you are about to generate and why. Do not apply yet.
3. **Generate** the manifest(s): the ArgoCD `Application`, its Helm `valuesObject` or its raw
   manifests. Follow the rules in section 4.
4. **Validate** before applying. A manifest that does not parse wastes a sync cycle:
   - `yaml` parses (round-trip it, or `kubectl apply --dry-run=client`).
   - Helm values are shaped right (`helm template` the chart with your values, or `helm lint`).
   - For anything with a policy or security context, re-read section 4's rules against it.
5. **Write the check first (TDD).** Before you rely on a component being healthy, write the
   assertion that proves it: the Application is `Synced` and `Healthy`, the pod is `Ready`, the
   endpoint answers. Run it, watch it fail for the right reason, then make it pass. The reference
   build's `solution/tests/` shows the pattern; you are writing the same kind of check as you go.
6. **Apply through Git.** Commit the manifest to your in-cluster Gitea repo. ArgoCD deploys it.
   You do not `kubectl apply` platform resources directly (the one exception is installing ArgoCD
   itself, the bootstrap).
7. **Watch it converge**, and when it does not, diagnose from ArgoCD status and the pod events,
   fix the root cause **in the values file**, and commit. Deleting a pod does not fix a Git-sourced
   fault; ArgoCD will recreate it from Git. Fix Git.

---

## 3. Sourcing and the golden path

You are given the sources so you do not have to hunt for them or guess versions.

- **Charts** come from the pinned Helm repositories in `components.yaml`, vendored under
  `charts-vendor/` so nothing waits on the network mid-build.
- **Images**: pull from in-region ECR (the AWS-managed EKS add-on registry), `public.ecr.aws`, or
  the workshop GHCR namespace. **Never reference `docker.io` in a manifest.** Docker Hub rate-limits
  anonymous pulls, and at fleet scale that stalls the build. If a chart defaults to Docker Hub,
  override the image to the mirrored copy.
- **The App-of-Apps is the pattern, not a file you copy.** You generate a root `Application` per
  plane that points ArgoCD at that plane's directory and recurses for the per-component
  `application.yaml` files. cert-manager first, Backstage last, ordered by sync waves.

---

## 4. The rules (every one of these is a failure someone already paid for)

Follow these when you generate manifests. Each prevents a specific class of failure that will
otherwise leave an Application `Degraded` with a confusing error.

### 4.1 Per-cluster values are parameters, never hardcodes
Anything that differs per cluster (the cluster name, the VPC id) must be templated and substituted
at provisioning, never pasted in. A hardcoded cluster name is wrong the moment the cluster is
rebuilt; a hardcoded VPC id is wrong on the next cluster. The AWS Load Balancer Controller needs
both its `clusterName` and its `vpcId` set explicitly. Do not rely on the controller reading the
VPC from instance metadata: under VPC-CNI prefix delegation that IMDS fetch times out and the
controller crash-loops.

### 4.2 `runAsNonRoot` always pairs with a numeric `runAsUser`
If you set `securityContext.runAsNonRoot: true` on a pod whose image declares its user
non-numerically, kubelet cannot verify non-root and the pod fails with
`CreateContainerConfigError`. Always pin the image's actual numeric uid (and gid). Find it: run
`id` in the image, or read the chart. This bites seed Jobs especially (they are easy to forget).

### 4.3 An image `repository` must not repeat the registry host
Helm charts build the image ref as `registry/repository`. If you set `registry: ghcr.io` and
`repository: ghcr.io/org/name`, the ref becomes `ghcr.io/ghcr.io/org/name`, a different path that
pulls the wrong image (or nothing). Set `repository: org/name`.

### 4.4 The container's runtime user must be able to traverse its working directory
`Cannot find module '/app/...'` for a path that clearly contains the module is a permission
problem, not a missing file. If the image's `WORKDIR` is `0700 root` and the container runs as a
non-root user, it cannot enter the directory. Ensure the runtime user can traverse the tree.

### 4.5 Read shared credentials from one source
Never hardcode a password in a manifest that also lives in a chart's values. They drift, and every
authenticated call then 401s. Reference the one Secret the platform creates, so the two cannot
disagree.

### 4.6 Size and shape the node correctly
On EKS with the managed node group module, `disk_size` is silently ignored when a launch template
exists; the node comes up at the AMI default (20 GiB) and DiskPressure evicts the platform. Size
the root volume via `block_device_mappings`. Enable VPC-CNI prefix delegation and set `maxPods`
explicitly, or a `t3.2xlarge` caps at 58 pods and the platform (which needs ~75) leaves pods
Pending.

### 4.7 Install first, enforce last
Every Kyverno policy ships with `failureAction: Audit`, not `Enforce`. An admission guardrail set
to Enforce before the software it governs is installed rejects that software's own pods and stalls
the build. The only sanctioned flip to Enforce is the governance demo on the AI-plane policy set,
after the platform is healthy. The foundation baseline stays Audit throughout.

### 4.8 Tag everything you create
Every AWS resource that can carry a tag gets `Workshop=packt`. Provider default_tags do not reach
node instances (use launch-template tag_specifications) or CSI-provisioned volumes or CNI-created
ENIs (tag them at the addon). An untagged resource is invisible to cleanup and bills after the
event.

---

## 5. Build order (this is the sequence; do not reorder)

### Bootstrap (the one direct install)
Install ArgoCD via its pinned Helm chart into the `argocd` namespace. This is the only time you run
Helm or `kubectl apply` directly against the cluster; everything after flows through Git.

### Module 1: Foundation
Generate and apply the foundation plane through the root App-of-Apps. Order the sync waves so
dependencies never race:
1. cert-manager and the AWS controllers (LB controller, EBS CSI) first.
2. secrets and policy tooling (External Secrets, OpenBao, Kyverno in Audit).
3. scaling and delivery (KEDA, Argo Rollouts/Workflows/Events), then observability
   (kube-prometheus-stack, Loki, Tempo, OpenTelemetry).
4. Backstage last (slowest, depends on the DB and the rest).

**Validation gate:** every foundation Application `Synced` and `Healthy`. On a clean cluster this
converges in well under 15 minutes. If one sticks, diagnose from ArgoCD status, fix the values,
commit. (Reference convergence: the `solution/` build reaches all-foundation-green in about
7 minutes.)

### Module 2: AI plane
Apply the AI-plane App-of-Apps: kgateway and agentgateway (the data plane), kagent, LLM Guard,
KServe + vLLM, llm-d. Then the centerpiece: **write a kagent Agent CRD** from a prompt describing
the agent's job. Get the CRD shape exactly right (verified against kagent v0.9.9):
`apiVersion: kagent.dev/v1alpha2`, the field is `systemMessage` (not `systemPrompt`), nested under
`spec.type` and `spec.declarative`, runtime is Google ADK, with a `modelConfig` reference. The
agent routes to the in-cluster vLLM over its OpenAI-compatible endpoint (no external API spend).

**Validation gate:** AI-plane Applications healthy; the agent reaches Ready; a real inference
request to vLLM returns a completion; the trace lands in Tempo. Note: KServe's InferenceService may
read `Ready=False` because of `IngressReady` while the predictor is fully up and serving; the
workshop uses the in-cluster endpoint, so that condition is expected and not a failure.

### Module 3: Self-service
Write a Backstage scaffolder template for an `agent-service` and the ApplicationSet that watches for
the repos it generates. Fire the golden path: request an agent through the portal and watch the
chain execute to a running agent and a first trace.

### Wrap: governance
Flip the AI-plane Kyverno policies from Audit to Enforce (the one sanctioned flip) and show a
violating agent being denied. Show per-agent attribution in Loki.

---

## 6. When you are stuck

If Claude cannot get a component healthy and you have spent more time than the module allows, use
the reference build. Do not copy the whole thing; recover the one component:

> Read `solution/platform/1-foundation/<component>/` and `solution/README.md`. Apply the reference
> manifests for `<component>` to get it healthy, then show me the difference between what I
> generated and the reference, so I understand what I missed.

This unblocks you and teaches you what was different. The reference build in `solution/` is the
battle-hardened version: it is what these rules were learned from, and it is proven to converge
from a cold cluster. Reach for it when you are stuck, not before.

---

## 7. Component reference

`components.yaml` is the authoritative list: name, plane, upstream project, chart source, pinned
version, namespace, and the module it appears in. Read a component's row there before you generate
its manifest. `versions.lock.md` records the resolved chart and image versions with the date they
were frozen. Do not change a pinned version during the build.
