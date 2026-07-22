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

## Hosting

Deploys on Railway with a custom domain under **ai-enhanced-devops.com** (a subdomain such
as `lab.ai-enhanced-devops.com`), set as the Railway custom domain at deploy time. Do NOT
use agenticburn.com — that is a different workshop. The confirmation email already sends
from `workshop@ai-enhanced-devops.com`. (Note: ai-enhanced-devops.com autorenew is off,
expires 2027-04-18 — valid through the July 2026 event.)

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
copied. Rebranded to Packt: all KCD Texas / Accenture branding removed, the workshop name
is "Agentic DevOps with Claude", the setup commands point at `packt-agentic-devops` and
`spec/WORKSHOP-SPEC.md`, and the node-count copy is corrected to a single node (`expect 1
Ready`, this platform runs one t3.2xlarge per student). Tests updated and green.

The KodeKloud "browser path" was removed on 2026-07-22. Packt issues EKS clusters only,
and while the path was off-menu it still answered 200 in production, so anyone with a
direct link could claim on it and be emailed toward a course that is not provisioned for
these attendees. Gone: the `/browser` and `/browser-claim` routes, the two email builders,
`browser.html` and `browser_success.html`, the `browser_claims` table, the admin browser
stats and recent-claims table, the cross-path notes on both success pages, and the browser
rows in the admin CSV export. Tests assert both routes now return 404 and that no page
mentions KodeKloud. The `path` column in the export is kept so an old export and a new one
still line up column-for-column.

The `browser_claims` table is no longer created or read. An existing `pool.db` from before
this change still carries the table; it is inert and can be dropped whenever convenient.

The sender email (`workshop@ai-enhanced-devops.com`) is configurable.
