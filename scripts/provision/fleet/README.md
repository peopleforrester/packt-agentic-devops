# Fleet provisioning

Stamps out student clusters at scale from one parameterized module against one shared VPC.

## Layout

- `../lab-vpc/` — the shared lab VPC (one `/16`, `/18` private subnets, one shared NAT).
  Provisioned once. Sized for prefix delegation (each node consumes ~112 IPs).
- `../cluster/` — one student cluster (1x t3.2xlarge + prefix delegation + maxPods 110,
  the validated shape). Takes `vpc_id` and `private_subnet_ids` as inputs, so it has no
  VPC of its own. Instantiated once per student, each with its own state.
- `fleet.sh` — the driver. Per-cluster state under `states/`, logs under `logs/`,
  concurrency capped by `MAX_PARALLEL` (default 8).

## Usage

```bash
# 1. Provision the shared VPC once.
cd ../lab-vpc && terraform init && terraform apply

# 2. Bring up N student clusters (parallel, capped).
cd ../fleet
./fleet.sh up 60                 # packt-student-001 .. -060
./fleet.sh up packt-student-007  # or specific names

# 3. Watch.
./fleet.sh status

# 4. Tear down.
./fleet.sh down all              # or: ./fleet.sh down 60  /  down <names>

# 5. When the event is over, destroy the shared VPC.
cd ../lab-vpc && terraform destroy
```

## Notes

- Each cluster has an isolated state file (`states/<name>.tfstate`), so one cluster's
  failure or teardown never touches another. Blast radius is one student.
- Every resource is tagged `Workshop=packt` plus `Student=<name>`; verify and clean up by
  tag, never by guessing (the account is shared with watchitburn).
- Design ceiling is ~60 concurrent clusters on the `/18` subnets. For more concurrent,
  widen the lab-vpc subnets (`/17`) and raise `MAX_PARALLEL` and AWS API limits.
- Cluster names must be unique and stable per student (they key the state and the EKS
  cluster name / log group).
