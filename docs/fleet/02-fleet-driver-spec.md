# 02 · Fleet driver specification

`scripts/provision/fleet/fleet.sh`. A port of Watch It Burn's proven driver with three deliberate
corrections (D2 state namespacing, D5 membership persistence, D6 account guard).

**It must never touch `scripts/provision/dev-cluster/` or the `adwc-dev` cluster.**

## Layout

```
scripts/provision/fleet/
  fleet.sh                 the driver
  preflight.sh             L0 gate (see 04-verification-tests.md)
  lab-vpc/main.tf          shared VPC, one apply per account
  cluster/main.tf          one student cluster, fully parameterized
  states/<account>/        <cluster>.tfstate + <cluster>.account   (gitignored)
  logs/<account>/          <cluster>.{apply,destroy,vtt}.log       (gitignored)
  tests/                   the test suite
```

Single `main.tf` per root with inline variables; every value passed as `-var` by the driver. That is what
makes the module stampable across accounts with no per-account code.

## Commands

| Command | Purpose |
|---|---|
| `preflight [stage]` | L0 gate for canary\|acct5\|scale\|full |
| `vpc-up <account>` | Apply the shared lab VPC for one account |
| `up <account> <n>` | N clusters in one account |
| `up-fleet <n>` | N per account across all five, concurrent |
| `health <scope>` | L1–L3 assertions per cluster |
| `ingest <scope>` | Push live cluster URLs into the claim app pool |
| `down <account> <names...>` | Selective teardown |
| `down-fleet <n>` | Mirror of up-fleet |
| `sweep <account>` | Orphan sweep (see 06) |
| `status` | Live cluster counts per account |
| `reap --keep <file>` | Destroy clusters not in the claimed list |

## Environment

```
PACKT_ACCOUNTS="accen-dev,aws1-student31,aws1-student32,aws1-student33,aws1-student34"
PACKT_REGION="us-west-2"
MAX_PARALLEL=15            # per account; x5 accounts = 75 concurrent
PACKT_NAME_PREFIX="student"
PACKT_APPLY=""             # destructive verbs are DRY-RUN unless =1
PACKT_DRY_RUN=""
```

## Core loop

`up_one <account> <name>`:

1. `assert_ours "$name"` — refuse anything not `^student[0-9]+$`.
2. `assert_account "$account" "$name"` — the cluster must not already exist in a different account.
3. `terraform apply -state=states/<account>/<name>.tfstate -var name=<name> -var vpc_id=... -var private_subnet_ids=...`
4. Write `states/<account>/<name>.account`.
5. On success, **in the same pool slot**, deploy the VTT (`vtt/apply.sh`) so the slot covers the whole
   build. A cluster is done only when its terminal answers.
6. On failure, `record_fail` to a per-run failures file. Never swallow a backgrounded exit code.

Parallelism is a bash `wait -n` sliding window at `MAX_PARALLEL`, one pool per account, each pool inside
its own `( ... ) &` subshell so `VPC_ID` / `TF_PROFILE` cannot leak across accounts.

Range arithmetic: account *i* owns `[i*n+1, (i+1)*n]`, disjoint by construction.

## Safety guards

```bash
assert_ours() {
    [[ "$1" =~ ^student[0-9]+$ ]] || { log "REFUSING non-fleet name: $1"; exit 1; }
}
```

The name is the state file, the Terraform `-var name`, the IAM role prefix, and the `Workshop=packt` tag,
so a refused name cannot produce an apply, a destroy, or a tagged resource. Layered on top:

- every resource tagged `Workshop=packt` (the co-tenant convention already in use),
- `reap` and `sweep` filter the **live** AWS listing by that tag and the name regex before acting,
- destructive verbs are dry-run unless `PACKT_APPLY=1`,
- an explicit refusal of `adwc-dev` by name.

## Network wiring

The cluster root has no VPC of its own; it takes `vpc_id` and `private_subnet_ids` as required inputs.
The driver reads them with `terraform output -json` from the account's VPC state and passes them as
`-var`. No `terraform_remote_state` data source — the shell-mediated coupling is what lets one cluster
module target five accounts with zero per-account code. If an account's VPC state is missing, fail loudly
with the exact apply command rather than falling back to another account's VPC.

## Cluster module requirements

Non-negotiable settings, each one a bug someone already paid for:

- `instance_types = ["t3.2xlarge"]`, node min=max=desired=1.
- Root volume **100 GiB via `block_device_mappings`**, never `disk_size` (silently ignored under a custom
  launch template → 20 GiB → DiskPressure → Pending pods).
- vpc-cni addon with `ENABLE_PREFIX_DELEGATION=true`, `WARM_PREFIX_TARGET=1`, and `maxPods=110` set
  explicitly in nodeadm (AL2023 ignores prefix delegation when computing max-pods).
- `create_cloudwatch_log_group = false` so a reused name never collides on reprovision.
- EBS CSI + Pod Identity so the VTT's PVC can bind.
- `default_tags` including `Workshop=packt` and the cluster name.

## Deviations from Unleashed, restated

| # | Unleashed | Here | Why |
|---|---|---|---|
| D2 | flat `states/<name>.tfstate` | `states/<account>/<name>.tfstate` | removes the global name collision that forced NAME_OFFSET |
| D5 | membership recomputed from offset arithmetic | persisted `.account` file | mismatched `n` silently orphaned clusters |
| D6 | name guard only | name **and** account guard | nothing stopped destroying against the wrong profile |
| D8 | per-attendee IAM users + keys | none | our VTT self-wires kubectl; removes the fragile secret-once subsystem |
