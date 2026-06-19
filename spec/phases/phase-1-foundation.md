# Phase 1: GitOps bootstrap and core foundation (Module 1, budget 25 min)

**Goal:** ArgoCD installed and reconciling the App-of-Apps, with the core foundation (cert-manager, Sealed Secrets, External Secrets Operator, Kyverno) synced and healthy.

**Inputs:** A bare cluster confirmed by Phase 0. The repo cloned. AWS Load Balancer Controller and the EBS CSI driver are provided by the cluster's add-ons (out of the in-cluster build scope).

**Outputs:**
- ArgoCD installed via server-side apply (the one allowed direct install), pinned to chart 9.5.22 (app v3.4.4)
- The root App-of-Apps applied, reconciling `platform/foundation/`
- cert-manager (v1.20.2), Sealed Secrets (controller 0.38.1, chart 2.19.0), External Secrets Operator (v2.6.0, chart 2.6.0), Kyverno (chart 3.8.1, app v1.18.1) synced and healthy
- A gp3 StorageClass marked default (the cluster ships none)

**Test criteria (tests/test_phase_1_foundation.py):**
- ArgoCD server, repo-server, and application-controller are Ready
- The app-of-apps Application exists and is Synced
- cert-manager, external-secrets, sealed-secrets, kyverno Applications are Synced and Healthy
- A default StorageClass exists (gp3) and is the only default
- No Application is OutOfSync

**Completion promise:** `<promise>PHASE1_DONE</promise>`

**Key decisions:**
- Install ArgoCD CRDs with `kubectl apply --server-side --force-conflicts`; the ApplicationSet CRD exceeds the client-side apply annotation limit. This is the bootstrap exception to the GitOps rule.
- Author RBAC for the ArgoCD 3.x model: explicit `logs, get`; explicit `update/*` and `delete/*` on managed resources (3.0 stopped cascading).
- External Secrets Operator: use `external-secrets.io/v1` (v1beta1 is retired) and add Argo CD `ignoreDifferences` on `/spec/dataFrom`, `/spec/data`, `/spec/refreshInterval` to stop conversion-webhook drift.
- Kyverno chart is 3.8.1 (the 3.x line), app v1.18.1. Write new policies as CEL types; the AI-plane policies arrive in Phase 4.
- Sealed Secrets: back up the active sealing key Secret; the controller name is `sealed-secrets` while kubeseal defaults to `sealed-secrets-controller`.

**Stop here.** Output the completion promise and wait. The presenter explains the App-of-Apps reconcile and the sync waves during this stop.
