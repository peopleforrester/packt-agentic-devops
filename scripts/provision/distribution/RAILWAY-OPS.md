# Railway operations for the Packt workshop

ABOUTME: Which Railway service is which, and the CLI gotchas, so a live-event fix
ABOUTME: lands on the right service instead of a stale sibling. Written after 2026-07-23.

Read this before running any `railway` command against this project. Getting the
service wrong or trusting a CLI exit code cost a live-workshop hour on 2026-07-23.

## The three services in the `ai-enhanced devops` project

| Service | Serves | Role | Deploy with |
|---|---|---|---|
| **packt-provisioning** | `https://packt.ai-enhanced-devops.com/` | LIVE claim/provisioning app (email to cluster). Owns the persistent volume `packt-provisioning-volume`, `DATABASE_PATH=/data/pool.db`. | `railway up --service packt-provisioning --no-gitignore` |
| **packt-router** | `*.packt.ai-enhanced-devops.com` (`studentN`, `admin1`, `admin2`) | Caddy router, hostname to NLB table | `scripts/provision/fleet/routes.sh` |
| **ai-enhanced-devops-website** | nothing live | STALE/failed sibling. Do NOT deploy the claim app here. | do not use |

The tell that you are on the wrong service: `railway ssh -s <svc> -- echo ok`
returns the Railway meta-gateway JSON (account + actions) instead of `ok`.
`packt-provisioning` gives a real container shell; the stale sibling does not.

## CLI gotchas (all verified 2026-07-23)

1. **`railway variables` truncates values in the table view.** To read a full
   `ADMIN_TOKEN`, `RESEND_API_KEY`, etc., use `railway variables --service <svc> --kv`
   or `--json`. A truncated token 403s against `/admin`.

2. **`railway ssh` exec: feed the script over STDIN.**
   `railway ssh -s packt-provisioning -- python3 < script.py`. Inline
   `python3 -c "..."` fails: `railway ssh -- args` re-parses through a remote
   shell, so parens and pipes in the code raise `syntax error near unexpected token`.

3. **`Failed to stream build logs: Failed to retrieve build log` is transient.**
   It is a CLI log-streaming failure, not a deploy failure. The build usually
   succeeds server-side. Verify by hitting the URLs or `railway status`, never by
   the `railway up` exit code. A failed deploy leaves the previous deploy serving
   (zero-downtime), so a redeploy cannot break what already runs.

## The claim pool (packt-provisioning `/data/pool.db`)

The app seeds on EVERY startup but only INSERTs new names (UNIQUE on `name`,
per-row IntegrityError skipped). It never removes or updates rows.

- **Editing `pool.csv` and restarting does NOT shrink the pool.** A stale 250-row
  pool stays 250. To prune, edit the DB directly via `railway ssh` (below) or
  point `DATABASE_PATH` at a fresh path and redeploy with a corrected `pool.csv`.
- **The pool must hold the real banded cluster names**, not sequential `student1-N`.
  Fleet clusters are named in 5 bands (student1-20, 51-70, 101-120, 151-170,
  201-220). A sequential pool hands out names that were never built; the app
  assigns lowest-id-first, so students past the first band get dead URLs.
- Regenerate from the live fleet with `scripts/provision/gen-pool.sh`, or from the
  routed hosts in `scripts/provision/router/routes.map`. Include only clusters
  whose `studentN.packt.ai-enhanced-devops.com` returns HTTP 200.

### Prune / repair in place (surgical, reversible)

Reserve dead unclaimed rows so the claim query skips them, and release students
stuck on dead clusters so re-entering their email reassigns a live one:

```python
# railway ssh -s packt-provisioning -- python3 < fix.py
import sqlite3
live = {...}  # set of live, routed, HTTP-200 cluster names
c = sqlite3.connect('/data/pool.db'); c.isolation_level = None
ph = ','.join('?' * len(live)); lv = list(live)
# 1. release students on dead clusters (they re-claim a live one on re-entry)
c.execute("UPDATE clusters SET claimed_by=NULL, claimed_at=NULL, email_sent=0 "
          "WHERE claimed_by IS NOT NULL AND claimed_by!='__reserved__' "
          f"AND name NOT IN ({ph})", lv)
# 2. reserve every dead unclaimed row so it is never handed out
c.execute(f"UPDATE clusters SET claimed_by='__reserved__' "
          f"WHERE claimed_by IS NULL AND name NOT IN ({ph})", lv)
```

Never touch a row whose cluster is live and claimed. Verify after: every
`claimed_by IS NULL` row is a live cluster, and the next-assignable `terminal_url`
returns 200. `/admin?token=<ADMIN_TOKEN>` shows total/claimed/available;
`/admin/export?token=<ADMIN_TOKEN>` is the CSV of who claimed what.
