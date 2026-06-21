# Lab credential distribution

A small Flask app that hands out pre-provisioned EKS cluster credentials to workshop
attendees, one per email, atomically from a pool. Pulled from the KCD Texas 2026
distributor and being customized for the Packt Agentic DevOps workshop.

It pairs directly with the fleet: `fleet.sh up <N>` provisions `packt-student-NNN`
clusters, and their credentials become the rows of `pool.csv` that this app hands out.

## How it works

- Attendee scans a QR at the door, lands on `/`, enters their email.
- `POST /eks-claim` assigns one unclaimed cluster from `pool.csv` atomically and shows
  the AWS credentials plus the setup commands.
- Idempotent by email: re-entering the same email redisplays the existing claim, never
  issues a second cluster.
- Lives only for the ~4-hour workshop, then is torn down.

## Files

- `app.py` — the application (env-configurable, ~570 lines).
- `templates/` — the pages.
- `pool.csv.example` — the pool schema: `name,access_key,secret_key,region`. The live
  `pool.csv` (real credentials) is gitignored and built from the fleet at event time.
- `test_app.py` — the test suite.
- `Procfile` / `railway.json` — deploy config (it ran on Railway for KCD).

## Config (environment)

- `POOL_CSV` (default `./pool.csv`), `DATABASE_PATH` (default `./pool.db`)
- `EKS_POOL_LIMIT` — cap how many CSV rows seed the live pool
- `RESEND_API_KEY` — for the confirmation email (sender address is set in `app.py`)

## Run

```bash
cd scripts/provision/distribution
uv run python -m flask --app app run    # or: uv run python app.py
```

## Customization status (KCD -> Packt)

Pulled in PII-free: the KCD attendee emails (`data/`) and claims DB (`pool.db`) were NOT
copied. Still to rebrand for Packt (a string/content pass, ~37 refs in `app.py` and ~36
across templates): the KCD Texas / KodeKloud / Accenture branding and copy, the sender
email (`workshop@ai-enhanced-devops.com`), and the setup commands shown on the success
page (point them at this platform's spec and the student's claimed cluster).
