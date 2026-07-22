# ABOUTME: Flask app that distributes pre-provisioned EKS cluster credentials to the Packt
# ABOUTME: Agentic DevOps with Claude workshop attendees. Idempotent claim by email; Resend optional.

import csv
import json
import os
import re
import secrets
import sqlite3
from contextlib import closing
from pathlib import Path

import requests
from flask import Flask, abort, g, redirect, render_template, request, url_for

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")

RESEND_ENDPOINT = "https://api.resend.com/emails"
RESEND_FROM = "Agentic DevOps with Claude <workshop@ai-enhanced-devops.com>"
RESEND_SUBJECT_EKS = "Agentic DevOps with Claude — Your EKS Cluster Credentials"
RESEND_SUBJECT_TERMINAL = "Agentic DevOps with Claude — Your Lab Terminal"
RESEND_TIMEOUT_SECONDS = 5


def _resolve_admin_token() -> str:
    token = os.environ.get("ADMIN_TOKEN")
    if token:
        return token
    generated = secrets.token_urlsafe(32)
    print(f"[startup] ADMIN_TOKEN not set; using generated token: {generated}", flush=True)
    return generated


def _build_commands_block(cluster_name, region):
    return (
        f"aws configure                                  # paste keys above; region {region}\n"
        f"aws eks update-kubeconfig --name {cluster_name} --region {region}\n"
        "kubectl get nodes                              # expect 1 Ready  (single t3.2xlarge)\n"
        "git clone https://github.com/peopleforrester/packt-agentic-devops.git\n"
        "cd packt-agentic-devops\n"
        "claude"
    )


def _build_email_text(cluster_name, region, access_key, secret_key, root_url):
    # Sections are separated by blank lines and each credential sits on its own
    # line with no leading whitespace or label so triple-click selects just the
    # value in any reasonable mail client.
    bar = "=" * 56
    rule = "-" * 56
    cmds = _build_commands_block(cluster_name, region)
    return (
        f"{bar}\n"
        "Agentic DevOps with Claude -- Your Cluster Credentials\n"
        f"{bar}\n\n"
        f"Cluster: {cluster_name}\n"
        f"Region:  {region}\n\n"
        f"{rule}\n"
        "AWS Access Key\n"
        f"{rule}\n"
        f"{access_key}\n\n"
        f"{rule}\n"
        "AWS Secret Key\n"
        f"{rule}\n"
        f"{secret_key}\n\n"
        f"{rule}\n"
        "Setup commands\n"
        f"{rule}\n"
        f"{cmds}\n\n"
        "When Claude starts, point it at spec/WORKSHOP-SPEC.md and follow the\n"
        "phased build. Claude creates the platform namespaces as it builds --\n"
        "do not pre-create anything.\n\n"
        "If `kubectl get nodes` shows no Ready node, raise your hand during the\n"
        "setup window for a spare cluster.\n\n"
        f"Lost this email? Re-enter your email at {root_url} to redisplay your\n"
        "credentials.\n\n"
        "Sponsored by Packt Publishing.\n"
    )


def _build_email_html(cluster_name, region, access_key, secret_key, root_url):
    # Inline styles only — most mail clients strip <style> blocks. System font
    # stack so the message renders without web fonts. Each credential and the
    # commands list lives in its own <pre> so triple-click in Gmail / Outlook
    # web / Apple Mail selects exactly that value.
    cmds = _build_commands_block(cluster_name, region)
    mono_block = (
        "margin:6px 0 0; padding:12px 14px; background:#0D0D0D; color:#FFFFFF;"
        " font-family:Consolas,\"SFMono-Regular\",Menlo,monospace; font-size:13px;"
        " border-radius:6px; white-space:pre; overflow-x:auto; line-height:1.55;"
    )
    label_style = "margin-top:18px; font-size:13px; color:#191919; font-weight:600; letter-spacing:.02em;"
    return f"""<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F5F4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#333333;line-height:1.5;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F5F5F4;">
    <tr><td align="center" style="padding:24px 12px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;background:#FFFFFF;border-radius:10px;border:1px solid #e2e4ee;">
        <tr><td style="background:#191919;color:#FFFFFF;padding:18px 24px;border-radius:10px 10px 0 0;border-bottom:3px solid #FA7040;">
          <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;opacity:.75;">Agentic DevOps with Claude</div>
          <div style="font-size:20px;font-weight:700;margin-top:2px;">Your Cluster Credentials</div>
        </td></tr>
        <tr><td style="padding:24px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#EDF0F2;border-radius:8px;">
            <tr><td style="padding:16px 18px;">
              <div style="font-size:11px;color:#191919;letter-spacing:.08em;text-transform:uppercase;opacity:.75;font-weight:700;">Your cluster</div>
              <div style="font-size:22px;color:#191919;font-weight:700;margin-top:4px;">{cluster_name}</div>
              <div style="font-size:14px;color:#191919;margin-top:4px;">Region: <strong>{region}</strong></div>
            </td></tr>
          </table>

          <div style="{label_style}">AWS access key</div>
          <pre style="{mono_block}">{access_key}</pre>

          <div style="{label_style}">AWS secret key</div>
          <pre style="{mono_block}">{secret_key}</pre>

          <div style="{label_style}">Setup commands</div>
          <pre style="{mono_block}">{cmds}</pre>

          <div style="margin-top:22px;padding:12px 14px;border-left:3px solid #FA7040;background:#FEF1EA;color:#191919;font-size:14px;font-style:italic;border-radius:0 6px 6px 0;">
            <strong style="font-style:normal;">When Claude starts,</strong> point it at <code style="font-style:normal;font-family:Consolas,monospace;">spec/WORKSHOP-SPEC.md</code> and follow the phased build. Claude creates the platform namespaces as it builds &mdash; do not pre-create anything.
          </div>

          <p style="margin:18px 0 0;color:#333333;font-size:13px;">
            If <code style="font-family:Consolas,monospace;">kubectl get nodes</code> shows no Ready node, raise your hand during the setup window for a spare cluster.
          </p>
        </td></tr>
        <tr><td style="padding:14px 24px 22px;border-top:1px solid #e2e4ee;color:#6B6B6B;font-size:12px;text-align:center;font-style:italic;">
          Lost this email? Re-enter your email at <a href="{root_url}" style="color:#FA7040;text-decoration:none;">the homepage</a> to redisplay your credentials.
          <div style="margin-top:8px;font-style:normal;color:#6B6B6B;">Sponsored by <strong style="color:#191919;">Packt Publishing</strong></div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""


def _build_terminal_email_text(cluster_name, region, terminal_url, access_key, secret_key, root_url):
    # The VTT path: the student opens a browser terminal that is already signed
    # in to their cluster, so kubectl and Claude Code just work. AWS keys are
    # included below only when the cluster carries them, for anyone who prefers
    # to drive the cluster from their own machine.
    bar = "=" * 56
    rule = "-" * 56
    parts = [
        f"{bar}\n",
        "Agentic DevOps with Claude -- Your Lab Terminal\n",
        f"{bar}\n\n",
        f"Cluster: {cluster_name}\n",
        f"Region:  {region}\n\n",
        f"{rule}\n",
        "Open your terminal\n",
        f"{rule}\n",
        f"{terminal_url}\n\n",
        "Your browser terminal is already signed in to your cluster. kubectl is\n",
        "wired, Claude Code is installed, and the workshop repo is cloned at\n",
        "~/workshop. Open the link above, then run:\n\n",
        "  claude\n\n",
        "When Claude starts, point it at spec/WORKSHOP-SPEC.md and follow the\n",
        "phased build. Claude creates the platform namespaces as it builds --\n",
        "do not pre-create anything.\n\n",
    ]
    if access_key and secret_key:
        cmds = _build_commands_block(cluster_name, region)
        parts += [
            f"{rule}\n",
            "Prefer your own machine? AWS access key\n",
            f"{rule}\n",
            f"{access_key}\n\n",
            f"{rule}\n",
            "AWS secret key\n",
            f"{rule}\n",
            f"{secret_key}\n\n",
            f"{rule}\n",
            "Local setup commands\n",
            f"{rule}\n",
            f"{cmds}\n\n",
        ]
    parts += [
        f"Lost this email? Re-enter your email at {root_url} to redisplay your\n",
        "terminal link.\n\n",
        "Sponsored by Packt Publishing.\n",
    ]
    return "".join(parts)


def _build_terminal_email_html(cluster_name, region, terminal_url, access_key, secret_key, root_url):
    mono_block = (
        "margin:6px 0 0; padding:12px 14px; background:#0D0D0D; color:#FFFFFF;"
        " font-family:Consolas,\"SFMono-Regular\",Menlo,monospace; font-size:13px;"
        " border-radius:6px; white-space:pre; overflow-x:auto; line-height:1.55;"
    )
    label_style = "margin-top:18px; font-size:13px; color:#191919; font-weight:600; letter-spacing:.02em;"
    keys_section = ""
    if access_key and secret_key:
        cmds = _build_commands_block(cluster_name, region)
        keys_section = f"""
          <div style="{label_style}">Prefer your own machine? AWS access key</div>
          <pre style="{mono_block}">{access_key}</pre>

          <div style="{label_style}">AWS secret key</div>
          <pre style="{mono_block}">{secret_key}</pre>

          <div style="{label_style}">Local setup commands</div>
          <pre style="{mono_block}">{cmds}</pre>
"""
    return f"""<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F5F4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#333333;line-height:1.5;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F5F5F4;">
    <tr><td align="center" style="padding:24px 12px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;background:#FFFFFF;border-radius:10px;border:1px solid #e2e4ee;">
        <tr><td style="background:#191919;color:#FFFFFF;padding:18px 24px;border-radius:10px 10px 0 0;border-bottom:3px solid #FA7040;">
          <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;opacity:.75;">Agentic DevOps with Claude</div>
          <div style="font-size:20px;font-weight:700;margin-top:2px;">Your Lab Terminal</div>
        </td></tr>
        <tr><td style="padding:24px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#EDF0F2;border-radius:8px;">
            <tr><td style="padding:16px 18px;">
              <div style="font-size:11px;color:#191919;letter-spacing:.08em;text-transform:uppercase;opacity:.75;font-weight:700;">Your cluster</div>
              <div style="font-size:22px;color:#191919;font-weight:700;margin-top:4px;">{cluster_name}</div>
              <div style="font-size:14px;color:#191919;margin-top:4px;">Region: <strong>{region}</strong></div>
            </td></tr>
          </table>

          <a href="{terminal_url}" style="display:inline-block;margin-top:20px;background:#FA7040;color:#FFFFFF;text-decoration:none;font-weight:700;font-size:15px;padding:12px 22px;border-radius:6px;">Open your terminal &rarr;</a>

          <p style="margin:18px 0 0;color:#333333;font-size:14px;">
            Your browser terminal is already signed in to your cluster. kubectl is wired, Claude Code is installed, and the workshop repo is cloned at <code style="font-family:Consolas,monospace;">~/workshop</code>. Open it, then run <code style="font-family:Consolas,monospace;">claude</code>.
          </p>

          <div style="margin-top:22px;padding:12px 14px;border-left:3px solid #FA7040;background:#FEF1EA;color:#191919;font-size:14px;font-style:italic;border-radius:0 6px 6px 0;">
            <strong style="font-style:normal;">When Claude starts,</strong> point it at <code style="font-style:normal;font-family:Consolas,monospace;">spec/WORKSHOP-SPEC.md</code> and follow the phased build. Claude creates the platform namespaces as it builds &mdash; do not pre-create anything.
          </div>
{keys_section}
        </td></tr>
        <tr><td style="padding:14px 24px 22px;border-top:1px solid #e2e4ee;color:#6B6B6B;font-size:12px;text-align:center;font-style:italic;">
          Lost this email? Re-enter your email at <a href="{root_url}" style="color:#FA7040;text-decoration:none;">the homepage</a> to redisplay your terminal link.
          <div style="margin-top:8px;font-style:normal;color:#6B6B6B;">Sponsored by <strong style="color:#191919;">Packt Publishing</strong></div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""


def _send_resend_email(api_key, to_email, subject, text_body, html_body):
    payload = {
        "from": RESEND_FROM,
        "to": [to_email],
        "subject": subject,
        "text": text_body,
        "html": html_body,
    }
    try:
        resp = requests.post(
            RESEND_ENDPOINT,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            data=json.dumps(payload),
            timeout=RESEND_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        print(f"[email] send to {to_email} failed: {exc}", flush=True)
        return False
    if 200 <= resp.status_code < 300:
        print(f"[email] sent to {to_email} (status {resp.status_code})", flush=True)
        return True
    print(
        f"[email] send to {to_email} returned {resp.status_code}: {resp.text[:200]}",
        flush=True,
    )
    return False


def create_app(database_path=None, pool_csv=None, resend_api_key=None, eks_pool_limit=None):
    app = Flask(__name__)
    app.config["DATABASE_PATH"] = database_path or os.environ.get("DATABASE_PATH", "./pool.db")
    app.config["POOL_CSV"] = pool_csv or os.environ.get("POOL_CSV", "./pool.csv")
    app.config["ADMIN_TOKEN"] = _resolve_admin_token()
    app.config["RESEND_API_KEY"] = (
        resend_api_key if resend_api_key is not None else os.environ.get("RESEND_API_KEY", "")
    )
    # EKS_POOL_LIMIT caps how many rows of pool.csv get seeded into the live
    # clusters table. The CSV file is left untouched — rows beyond the limit
    # stay on disk but never make it into the active pool. Useful when the CSV
    # holds spare/reserve rows that shouldn't be claimable.
    if eks_pool_limit is None:
        raw = os.environ.get("EKS_POOL_LIMIT", "").strip()
        eks_pool_limit = int(raw) if raw.isdigit() and int(raw) > 0 else None
    app.config["EKS_POOL_LIMIT"] = eks_pool_limit
    # WORKSHOP_HOST appears on the pool-exhausted page ("Ask <host>"). Defaults
    # to a generic phrase so the copy works for any workshop without code edits.
    app.config["WORKSHOP_HOST"] = os.environ.get("WORKSHOP_HOST_NAME", "the workshop host")

    def get_db():
        db = getattr(g, "_db", None)
        if db is None:
            db = sqlite3.connect(app.config["DATABASE_PATH"], isolation_level=None)
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA foreign_keys=ON")
            g._db = db
        return db

    @app.teardown_appcontext
    def close_db(_exc):
        db = getattr(g, "_db", None)
        if db is not None:
            db.close()

    def init_schema(conn):
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS clusters (
                id            INTEGER PRIMARY KEY,
                name          TEXT UNIQUE NOT NULL,
                access_key    TEXT NOT NULL DEFAULT '',
                secret_key    TEXT NOT NULL DEFAULT '',
                region        TEXT NOT NULL,
                terminal_url  TEXT NOT NULL DEFAULT '',
                claimed_by    TEXT,
                claimed_at    TEXT,
                email_sent    INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        # In case the table existed from an earlier schema without these columns.
        cols = {r[1] for r in conn.execute("PRAGMA table_info(clusters)").fetchall()}
        if "email_sent" not in cols:
            conn.execute("ALTER TABLE clusters ADD COLUMN email_sent INTEGER NOT NULL DEFAULT 0")
        if "terminal_url" not in cols:
            conn.execute("ALTER TABLE clusters ADD COLUMN terminal_url TEXT NOT NULL DEFAULT ''")

    def seed_from_csv(conn, csv_path):
        if not Path(csv_path).exists():
            return 0
        with open(csv_path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            # terminal_url is optional: a four-column pool (name, access_key,
            # secret_key, region) still seeds, with an empty terminal_url.
            rows = [
                (
                    r["name"].strip(),
                    (r.get("access_key") or "").strip(),
                    (r.get("secret_key") or "").strip(),
                    (r.get("region") or "").strip(),
                    (r.get("terminal_url") or "").strip(),
                )
                for r in reader
                if r.get("name")
            ]
        limit = app.config.get("EKS_POOL_LIMIT")
        rows_to_seed = rows[:limit] if limit else rows
        inserted = 0
        for name, access_key, secret_key, region, terminal_url in rows_to_seed:
            if not access_key and not terminal_url:
                # A row must offer at least one path in: AWS keys (local) or a
                # terminal URL (VTT). One with neither is unusable; skip it loudly.
                print(f"[startup] pool row '{name}' has no keys and no terminal_url; skipped", flush=True)
                continue
            try:
                conn.execute(
                    "INSERT INTO clusters (name, access_key, secret_key, region, terminal_url) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (name, access_key, secret_key, region, terminal_url),
                )
                inserted += 1
            except sqlite3.IntegrityError:
                continue
        if limit and len(rows) > limit:
            print(
                f"[startup] pool.csv has {len(rows)} rows; EKS_POOL_LIMIT={limit} so "
                f"rows {limit + 1}-{len(rows)} are left in the file but not seeded",
                flush=True,
            )
        return inserted

    def bootstrap():
        with closing(sqlite3.connect(app.config["DATABASE_PATH"], isolation_level=None)) as conn:
            init_schema(conn)
            (count,) = conn.execute("SELECT COUNT(*) FROM clusters").fetchone()
            if count == 0:
                added = seed_from_csv(conn, app.config["POOL_CSV"])
                print(f"[startup] seeded {added} clusters from {app.config['POOL_CSV']}", flush=True)
            else:
                print(f"[startup] clusters table already has {count} rows; skipping seed", flush=True)
        if app.config["RESEND_API_KEY"]:
            print("[startup] RESEND_API_KEY set — credential emails enabled", flush=True)
        else:
            print("[startup] RESEND_API_KEY not set — email delivery skipped", flush=True)

    bootstrap()

    @app.get("/healthz")
    def healthz():
        return "ok", 200

    @app.get("/")
    def index():
        # The root page is the EKS claim form. The old picker was a one-option
        # interstitial that just added a click; merging it into the form here
        # cuts the time-to-credentials by one interaction per attendee.
        return render_template("index.html")

    @app.get("/eks")
    def eks_form():
        # Back-compat for any QR codes / shared links pointing at /eks.
        return redirect(url_for("index"))

    @app.post("/eks-claim")
    def eks_claim():
        email = (request.form.get("email") or "").strip().lower()
        if not email or not EMAIL_RE.match(email):
            return render_template("index.html", error="Please enter a valid email address."), 400

        conn = get_db()
        cluster = None
        is_new_claim = False
        try:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute(
                "SELECT id, name, access_key, secret_key, region, terminal_url, email_sent "
                "FROM clusters WHERE claimed_by = ? LIMIT 1",
                (email,),
            ).fetchone()
            if existing is not None:
                conn.execute("COMMIT")
                cluster = existing
            else:
                row = conn.execute(
                    "SELECT id, name, access_key, secret_key, region, terminal_url "
                    "FROM clusters WHERE claimed_by IS NULL ORDER BY id LIMIT 1"
                ).fetchone()
                if row is None:
                    # Pool exhausted for a brand-new email. EKS is the only path
                    # now, so render the exhausted fallback and let the attendee
                    # ask for a spare during the setup window.
                    conn.execute("ROLLBACK")
                    return render_template(
                        "exhausted.html",
                        workshop_host=app.config["WORKSHOP_HOST"],
                    ), 200
                conn.execute(
                    "UPDATE clusters SET claimed_by = ?, "
                    "claimed_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = ?",
                    (email, row["id"]),
                )
                conn.execute("COMMIT")
                cluster = row
                is_new_claim = True
        except sqlite3.Error:
            conn.execute("ROLLBACK")
            raise

        # Email delivery happens outside the write transaction so we don't hold
        # the SQLite write lock during a network call. Failures are logged but
        # never block the in-browser display, and re-claims by the same email
        # never trigger a second send.
        terminal_url = cluster["terminal_url"] if "terminal_url" in cluster.keys() else ""
        if is_new_claim and app.config["RESEND_API_KEY"]:
            root = request.url_root.rstrip("/")
            if terminal_url:
                subject = RESEND_SUBJECT_TERMINAL
                text = _build_terminal_email_text(
                    cluster["name"], cluster["region"], terminal_url,
                    cluster["access_key"], cluster["secret_key"], root,
                )
                html = _build_terminal_email_html(
                    cluster["name"], cluster["region"], terminal_url,
                    cluster["access_key"], cluster["secret_key"], root,
                )
            else:
                subject = RESEND_SUBJECT_EKS
                text = _build_email_text(
                    cluster["name"], cluster["region"],
                    cluster["access_key"], cluster["secret_key"], root,
                )
                html = _build_email_html(
                    cluster["name"], cluster["region"],
                    cluster["access_key"], cluster["secret_key"], root,
                )
            if _send_resend_email(app.config["RESEND_API_KEY"], email, subject, text, html):
                conn.execute("UPDATE clusters SET email_sent = 1 WHERE id = ?", (cluster["id"],))

        return render_template(
            "success.html",
            email=email,
            cluster_name=cluster["name"],
            region=cluster["region"],
            access_key=cluster["access_key"],
            secret_key=cluster["secret_key"],
            terminal_url=terminal_url,
            root_url=request.url_root.rstrip("/"),
        )

    @app.post("/claim")
    def claim_back_compat():
        # Back-compat: any external caller or test still hitting POST /claim
        # is forwarded into the canonical EKS-claim handler.
        return eks_claim()

    @app.get("/admin/export")
    def admin_export():
        token = request.args.get("token", "")
        if not token or not secrets.compare_digest(token, app.config["ADMIN_TOKEN"]):
            abort(403)
        conn = get_db()
        eks_rows = conn.execute(
            "SELECT name, region, claimed_by, claimed_at FROM clusters "
            "WHERE claimed_by IS NOT NULL ORDER BY claimed_at"
        ).fetchall()
        # The leading "path" column is retained so an export opened alongside an
        # older one still lines up column-for-column in a spreadsheet.
        lines = ["path,email,cluster_name,region,claimed_at"]
        for r in eks_rows:
            lines.append(f"eks,{r['claimed_by']},{r['name']},{r['region']},{r['claimed_at']}")
        body = "\n".join(lines) + "\n"
        return body, 200, {"Content-Type": "text/csv; charset=utf-8"}

    @app.get("/admin")
    def admin():
        token = request.args.get("token", "")
        if not token or not secrets.compare_digest(token, app.config["ADMIN_TOKEN"]):
            abort(403)
        conn = get_db()
        (eks_total,) = conn.execute("SELECT COUNT(*) FROM clusters").fetchone()
        (eks_claimed,) = conn.execute(
            "SELECT COUNT(*) FROM clusters WHERE claimed_by IS NOT NULL"
        ).fetchone()
        eks_recent = conn.execute(
            "SELECT name, region, claimed_by, claimed_at FROM clusters "
            "WHERE claimed_by IS NOT NULL ORDER BY claimed_at DESC LIMIT 10"
        ).fetchall()
        return render_template(
            "admin.html",
            total=eks_total,
            claimed=eks_claimed,
            available=eks_total - eks_claimed,
            recent=eks_recent,
        )

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")), debug=False)
