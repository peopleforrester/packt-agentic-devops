# Bootstrap

How the cluster goes from empty to `checkpoint/module-0-start` (ArgoCD installed, nothing else synced), then to the foundation plane.

## 1. Install ArgoCD (the one allowed direct install)

ArgoCD is installed via its Helm chart, pinned to the version in `versions.lock.md`. This is the bootstrap exception to the GitOps rule: everything after this flows through ArgoCD.

```bash
helm install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 9.5.21 \
  --namespace argocd --create-namespace \
  --set crds.install=true
```

The chart and ArgoCD CRDs install cleanly client-side at this size. For the ApplicationSet and Argo Workflows CRDs later, use server-side apply.

## 2. Apply the plane App-of-Apps (one per module)

The platform is a plane-of-apps: one App-of-Apps per plane, applied at the start of its
module, so each module shows GitOps doing the work.

- `root-app.yaml` (`platform-foundation`): the foundation plane, applied in Module 1.
- `ai-plane-app.yaml` (`platform-ai-plane`): the AI plane, applied in Module 2.
- `self-service-app.yaml` (`platform-self-service`): the self-service ApplicationSet, applied in Module 3.

Each points ArgoCD at its plane directory and recurses for the per-component Application
manifests. All require the repo reachable by ArgoCD over Git (the `repoURL`, set to the
public repo). Until the repo is public, use the dev path below.

Two paths.

Production path (App-of-Apps from Git): apply the plane app for the module, e.g.
`kubectl apply -n argocd -f platform/bootstrap/root-app.yaml` for Module 1.

Dev validation path (no Git remote needed): the per-component Applications under `platform/foundation/<name>/application.yaml` are Helm-sourced, so each pulls its chart straight from the upstream Helm repo. Apply them directly into the `argocd` namespace:

```bash
kubectl apply -n argocd -f platform/foundation/cert-manager/application.yaml
# ...and the rest, or: kubectl apply -n argocd --recursive -f platform/foundation/
```

ArgoCD then syncs each component from its pinned Helm chart. Sync waves order the rollout.

## Sync waves

- Wave 0: cert-manager (issues webhook certs others depend on).
- Wave 1: secrets and policy tooling (external-secrets, openbao, kyverno).
- Wave 2: scaling and delivery extensions (keda, argo-rollouts), then observability.
- Later waves: Backstage last.

## Checkpoint

After ArgoCD is installed and before any foundation sync, tag `checkpoint/module-0-start`.
