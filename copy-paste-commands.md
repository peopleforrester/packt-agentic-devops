# copy-paste-commands.md

The attendee catch-up path. Numbered top to bottom, grouped by module, every command idempotent and safe to re-run. Each module boundary is a jump-in point: arrive late, run that module's block, and you are current.

These commands target your own provided cluster. `kubectl` is already pointed at it in your browser terminal. The platform Applications pull this repo and the pinned Helm charts from the public sources, so you do not push anything to make the platform sync; you push only in Module 3, when the golden path generates an agent repo into the in-cluster Gitea.

Wait commands block until the plane is Healthy. If one times out, open the ArgoCD UI and re-run the same block; nothing here is destructive.

## Module 0: start state

Your environment lands at `checkpoint/module-0-start`: cluster up, ArgoCD installed, this repo cloned, nothing else synced. Confirm it:

```bash
# ArgoCD is up
kubectl get pods -n argocd

# Nothing synced yet (no platform Applications)
kubectl get applications -n argocd
```

If ArgoCD is not installed (you started from a bare cluster), install it once. This is the only direct install; everything after flows through ArgoCD.

```bash
helm upgrade --install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 9.5.21 \
  --namespace argocd --create-namespace \
  --set crds.install=true

kubectl -n argocd rollout status deploy/argo-cd-argocd-server --timeout=300s
```

## Module 1: cloud-native foundation

Apply the foundation App-of-Apps and wait for the plane to go Healthy.

```bash
kubectl apply -n argocd -f platform/bootstrap/root-app.yaml

# Wait for the foundation plane (cert-manager first, Backstage last)
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/platform-foundation --timeout=900s
```

Open Backstage once the foundation is green (the URL is the AWS Load Balancer Controller NLB for the Backstage Service):

```bash
kubectl get svc -n backstage
```

## Module 2: the AI plane

Apply the AI-plane App-of-Apps. CRDs land first via server-side apply, then the controllers and workloads.

```bash
kubectl apply -n argocd -f platform/bootstrap/ai-plane-app.yaml

kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/platform-ai-plane --timeout=1200s
```

Confirm the model server is serving (it loads the baked Qwen3 weights from disk, no download):

```bash
kubectl get inferenceservice -n kserve
# READY should be True
```

## Module 3: self-service

Apply the self-service App-of-Apps. It syncs the ApplicationSet that watches the in-cluster Gitea for scaffolder-generated agent repos.

```bash
kubectl apply -n argocd -f platform/bootstrap/self-service-app.yaml

kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/platform-self-service --timeout=300s
```

From here, request an agent through the Backstage portal (the golden path). The form generates a repo into Gitea, the ApplicationSet creates an ArgoCD Application for it, ArgoCD syncs it, and the agent runs. Watch it land:

```bash
# New Applications appear as the ApplicationSet detects generated repos
kubectl get applications -n argocd

# The generated agent reconciles in the kagent namespace
kubectl get agents -n kagent
```

## Full platform in one block (catch-up from zero)

If you arrived late and want the whole platform, run Module 0, then 1, then 2, then 3 in order. Each waits for its plane before the next. The full build from a bare cluster takes roughly 20 minutes.
