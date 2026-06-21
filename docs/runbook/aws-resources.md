# AWS resource tracking

The AWS account is shared with another project (watchitburn). To avoid collisions, every
resource this project creates is tagged and tracked. Never identify or delete resources
by guessing; filter by the tag.

## Tagging convention

Terraform applies these via provider `default_tags`, so every taggable resource carries
them automatically:

| Tag | Value |
|---|---|
| `Workshop` | `packt` |
| `Project` | `packt-agentic-devops` |
| `Purpose` | `agentic-devops-validation` |
| `ManagedBy` | `terraform` |
| `Ephemeral` | `true` |

`Workshop=packt` is the identifier. watchitburn resources do not carry it.

## Tracking beyond the state file

- **Terraform state** is the primary record (`scripts/provision/dev-cluster/terraform.tfstate`,
  gitignored, never committed).
- **AWS Resource Group** `packt-agentic-devops` (created by Terraform, tag-based) lists
  every `Workshop=packt` resource live in the console, independent of the state file.
- **This ledger** is the human record of every spin-up.

### List everything tagged packt

```bash
# Via the resource group
AWS_PROFILE=accen-dev aws resource-groups list-group-resources \
  --group-name packt-agentic-devops --region us-west-2

# Or directly by tag (Resource Groups Tagging API)
AWS_PROFILE=accen-dev aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Workshop,Values=packt --region us-west-2
```

### Confirm a clean teardown

After `terraform destroy`, verify nothing tagged `packt` remains:

```bash
AWS_PROFILE=accen-dev aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Workshop,Values=packt --region us-west-2 \
  --query 'length(ResourceTagMappingList)'
# expect 0 (the resource group itself is removed with the stack)
```

## Spin-up ledger

Record every cluster or stack here. Update the status when torn down.

| Date | Stack / cluster | Region | Profile | Purpose | Status |
|---|---|---|---|---|---|
| 2026-06-20 | adwc-dev (EKS) | us-west-2 | accen-dev | Foundation plane live validation | Destroyed (verified 0 resources) |
