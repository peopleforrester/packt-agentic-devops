# Lessons learned: the July 2026 remediation

ABOUTME: Durable lessons from remediating the D1-D27 defects and wiring the platform to a
ABOUTME: fully-green state on the standing admin1 reference cluster. Read before the next run.

This captures what generalizes past the individual fixes. The per-defect record is in
`July-23rd-Defects-run.md`; this is the reusable knowledge.

## 1. The ArgoCD controller-default drift class

The single most common reason an Application never reaches Synced is not a bad manifest. It
is a controller that mutates the resource after it is applied, adding fields the manifest did
not set, which ArgoCD then reports as drift forever. Seen this run on:

- **Kyverno** (D17, D22): the admission webhook defaults `spec.admission`,
  `spec.emitWarning`, `spec.validationFailureAction`, and per-rule `skipBackgroundRequests`
  and `validate.allowExistingViolations` onto every ClusterPolicy, plus empty
  `labels: {}` / `annotations: {}` on the CEL CRDs.
- **KServe** (D23): rewrites the `serving.kserve.io/deploymentMode` annotation from
  `RawDeployment` to its current name `Standard`.
- **External Secrets** (D24): defaults `data[].remoteRef.{conversionStrategy,
  decodingStrategy,metadataPolicy,nullBytePolicy}` and `target.deletionPolicy`.

The fix is `ignoreDifferences` on the mutated fields. Two rules that matter:

- **Use `jqPathExpressions`, not `jsonPointers`, when the drift is inside an array.**
  jsonPointers cannot address `spec.rules[].skipBackgroundRequests`; the D17 fix looked
  right with jsonPointers but the app stayed OutOfSync until it was rewritten as jq paths.
- **Get the actual diff before writing the ignore rule. Do not guess.** The right method is
  to dump the desired manifest and the live resource, strip ArgoCD's own tracking
  annotation, and diff them. Guessing the fields either misses some (app stays OutOfSync) or
  ignores real ones (masks future problems). This discipline is also why D16 was **refuted**:
  the external-secrets CRD on the pinned chart has no conversion webhook and no caBundle, so
  the drift the report blamed cannot occur, and adding `ignoreDifferences` would have been
  dead config.

## 2. Verify against a live cluster, not the summary table

The remediation table was wrong in both directions. D14 was listed as pending but was already
fixed in the manifest. D16 and D18 were listed as real but were refuted once checked against
the pinned versions and a live cluster. The standing admin1 reference cluster was the
highest-fidelity verification bed: every fix was proven there before it was trusted, and
several "defects" dissolved on contact with reality. Keep a reference cluster up during
remediation.

## 3. The App-of-Apps refresh cascade

Pushing a manifest fix into the in-cluster Gitea is not enough to see it take effect. The
child Applications (opentelemetry-collector, kyverno, backstage, ...) get their spec from the
App-of-Apps (platform-foundation / platform-ai-plane / platform-self-service), which reads
the Git path. So the order is: push to Gitea, then hard-refresh the **App-of-Apps** so it
pulls the new child specs, then the child re-renders. Refreshing the child alone does nothing,
because its spec comes from the parent, not directly from Git. A Helm child app's
`status.sync.revision` is the chart version, not the Git SHA, which makes this easy to
misread.

## 4. Backstage does not load its production config by default

The Backstage Helm chart runs `node packages/backend` with no `--config`, so Backstage loads
only the baked scaffold `app-config.yaml`. None of the workshop config in
`app-config.production.yaml` took effect, which is the real root of D15 (catalog 401) and D19
(wrong ArgoCD service name). The fixes:

- Set `backstage.args: ["--config", "app-config.production.yaml"]`. The production config is
  complete (it has baseUrl, listen, database, auth, integrations, catalog), so load it
  **alone**. Loading the scaffold config too pulls in its `../../examples/*` file locations,
  which are absent from the image and leave the catalog empty.
- `backstage.appConfig` **replaces** the base config rather than appending, so a small
  overlay crashes the backend on missing `backend.baseUrl`. It is not a way to add one value.
- The production config needs per-cluster env (base URL, gitea creds, an ArgoCD token). A
  provisioning job assembles the `backstage-integrations` Secret; Backstage retries until it
  exists.

## 5. Unsubstituted placeholders hide beyond `REPLACE_WITH_`

The contract test greps for `REPLACE_WITH`, but the golden path shipped `REPLACE_GITEA_ORG`
and `REPLACE_GITEA_HOST` (D25), which nothing substituted, so the ApplicationSet errored
`GetOrgByName` and platform-self-service was Degraded. Any token that a provisioning step is
not proven to replace is a landmine, whatever its prefix. Widen the placeholder scan to
`REPLACE_` and audit each hit against a substitution step.

## 6. Remote kustomize bases fail and are not allowed

The llm-d kustomization (D26) pulled `github.com/llm-d/llm-d/deploy?ref=v0.7.0`. ArgoCD's
repo-server cannot fetch a remote git base (the no-live-network rule), and worse, the `deploy`
path does not exist in v0.7.0. Vendor manifests locally. When a component is GPU-oriented and
the workshop is CPU-only, show it as an architecture reference rather than pretend to run it.

## 7. KServe InferenceService health needs an ArgoCD customization

KServe reports `Ready=False` whenever `IngressReady=False`. In RawDeployment mode with no
KServe-managed ingress (the model is reached in-cluster), IngressReady never becomes True, so
the app sits Progressing though the model serves (D27). Add a `resource.customizations.health`
Lua check for `serving.kserve.io_InferenceService` that treats `PredictorReady=True` as
Healthy, applied through the bootstrap ArgoCD install values.

## 8. Two recurring test-side traps

- **incluster_curl output is not clean JSON.** It appends the http code and a kubectl "pod
  deleted" line, so `json.loads(body.rsplit("\n", 1)[0])` always fails. Extract the JSON by
  its brackets (`body.find("[")` to `body.rfind("]")`), or match by substring. This bit the
  phase-2 datasource check (D12) and the phase-3 catalog check.
- **Poll for eventually-consistent state.** A trace is not searchable in Tempo the instant it
  is sent (D11), and the in-memory Backstage catalog repopulates a processing cycle after a
  restart. Single-shot assertions race these; poll with a timeout.

## 9. Small integration gotchas worth remembering

- The Gitea SCM ApplicationSet generator needs the token to carry the `read:issue` scope, on
  top of the obvious repo/org scopes (D25).
- The Kubernetes API returns pretty-printed JSON, so a `"key":"value"` regex with no allowance
  for the space after the colon matches nothing. Compact the whitespace before grepping when
  parsing API responses in a shell with no jq.
- The bundled Bitnami PostgreSQL regenerates its password on resync, which breaks auth against
  the persistent volume. For a throwaway catalog, in-memory sqlite is simpler and correct; the
  catalog just rebuilds from its config location.
- A minted ArgoCD **session** token expires (24h). It is fine for a run that reprovisions, but
  a long-lived cluster needs a re-mint or a proper account token.
