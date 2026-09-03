<!-- ABOUTME: Why the agentgateway data path is a separate component from the controller install, -->
<!-- ABOUTME: and what each manifest here is responsible for. -->

# agentgateway-runtime

The `agentgateway` Application installs the **controller**. This one creates the **data path**.

Keeping them apart matters because the failure they produce together is misleading. A controller
with no Gateway reconciles nothing, every Application still reports Synced and Healthy, and routes
sit `Accepted=False` with "no parent found" — which reads as a route defect rather than a missing
Gateway.

| File | What it does |
|---|---|
| `gateway.yaml` | The Gateway, and the namespace label that lets `kagent` routes attach to it |
| `vllm-backend.yaml` | `AgentgatewayBackend` for the in-cluster vLLM, plus the route that reaches it |
| `injection-policy.yaml` | Prompt-guard policy sending requests and responses through LLM Guard |

## Two things that are easy to get wrong

**Listener namespace policy is `Selector`, not `Same`.** The generated agent routes live in
`kagent`, so `Same` silently refuses every route the golden path produces: route exists, Gateway
exists, nothing joins them. `Selector` opts a namespace in by label, which is narrower than `All`
and auditable.

**The guardrail fails closed.** If the scanner is unreachable, prompts are refused rather than
passed unscanned. A guardrail that fails open is one an attacker only has to knock over.

## Schemas are verified, not assumed

Every CR here was validated against the CRDs vendored in `charts-vendor/`, and the first draft was
wrong in ways that would have been rejected at apply time: the API group is `agentgateway.dev`, not
`gateway.agentgateway.dev`; `host`/`port` sit under `spec.ai.provider`, not `spec.ai`; `promptGuard`
lives under `spec.backend.ai` and its `request`/`response` are arrays; and `failureMode` takes
`FailClosed`/`FailOpen`, not `Deny`/`Allow`. `tests/test_agentgateway_manifests.py` runs that
validation without a cluster, so the next schema change fails a test rather than a sync.

## Not here: mTLS

Client-certificate validation is **not** implementable on the pinned Gateway API. v1.5.1's standard
channel exposes only `certificateRefs`, `mode` and `options` on a listener; `frontendValidation`,
which carries `AllowValidOnly`, is experimental-channel only. See the tracking issue rather than
assuming it was overlooked.
