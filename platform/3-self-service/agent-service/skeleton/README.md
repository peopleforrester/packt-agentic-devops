# ${{ values.name }}

${{ values.description }}

A governed agent service generated from the platform golden path. It ships with:

- a kagent Agent (`manifests/agent.yaml`) routed to the in-cluster vLLM via the
  `${{ values.modelConfig }}` ModelConfig
- an agentgateway route (`manifests/httproute.yaml`) so traffic is screened by LLM Guard
  and carries mTLS and audit logging
- OpenTelemetry injection on by default

The platform `agent-services` ApplicationSet deploys `manifests/` automatically once this
repository exists. Owner: `${{ values.owner }}`.
