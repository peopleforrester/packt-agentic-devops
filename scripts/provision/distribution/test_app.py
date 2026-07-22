# ABOUTME: Pytest suite for the Agentic DevOps with Claude credential distribution app.
# ABOUTME: Covers the EKS claim path (incl. back-compat /claim), admin, export, and healthz.

import csv

import pytest

import app as app_module


def _write_pool_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["name", "access_key", "secret_key", "region"])
        for row in rows:
            writer.writerow(row)


def _write_pool_csv_with_terminal(path, rows):
    # Five-column pool: the optional terminal_url wires a cluster to its VTT.
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["name", "access_key", "secret_key", "region", "terminal_url"])
        for row in rows:
            writer.writerow(row)


def _make_client(tmp_path, monkeypatch, csv_path):
    monkeypatch.setenv("ADMIN_TOKEN", "test-admin-token")
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    flask_app = app_module.create_app(
        database_path=str(tmp_path / "pool.db"),
        pool_csv=str(csv_path),
        resend_api_key="",
    )
    flask_app.config["TESTING"] = True
    return flask_app.test_client()


@pytest.fixture
def client(tmp_path, monkeypatch):
    db_path = tmp_path / "pool.db"
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv(
        csv_path,
        [
            ("test-cluster-01", "AKIATESTKEY01", "secret01", "us-west-2"),
            ("test-cluster-02", "AKIATESTKEY02", "secret02", "us-west-2"),
            ("test-cluster-03", "AKIATESTKEY03", "secret03", "us-west-2"),
        ],
    )
    monkeypatch.setenv("ADMIN_TOKEN", "test-admin-token")
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    flask_app = app_module.create_app(
        database_path=str(db_path),
        pool_csv=str(csv_path),
        resend_api_key="",
    )
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        yield c


# ---------- existing surface ---------------------------------------------------

def test_healthz(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.data == b"ok"


def test_claim_happy_path(client):
    # POST /claim is preserved as a back-compat alias for POST /eks-claim.
    res = client.post("/claim", data={"email": "alice@example.com"})
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert "test-cluster-01" in body
    assert "AKIATESTKEY01" in body
    assert "secret01" in body
    assert "us-west-2" in body
    assert "aws eks update-kubeconfig --name test-cluster-01" in body


def test_reclaim_same_email_returns_same_cluster(client):
    first = client.post("/eks-claim", data={"email": "alice@example.com"})
    second = client.post("/eks-claim", data={"email": "alice@example.com"})
    third = client.post("/eks-claim", data={"email": "ALICE@example.com"})
    for r in (first, second, third):
        assert r.status_code == 200
        assert "test-cluster-01" in r.get_data(as_text=True)
    assert "AKIATESTKEY01" in second.get_data(as_text=True)
    assert "test-cluster-02" not in second.get_data(as_text=True)


def test_second_email_gets_different_cluster(client):
    a = client.post("/eks-claim", data={"email": "alice@example.com"})
    b = client.post("/eks-claim", data={"email": "bob@example.com"})
    assert "test-cluster-01" in a.get_data(as_text=True)
    assert "test-cluster-02" in b.get_data(as_text=True)
    assert "AKIATESTKEY02" in b.get_data(as_text=True)


def test_eks_pool_exhausted_renders_exhausted_page(client):
    for i in range(3):
        assert client.post("/eks-claim", data={"email": f"user{i}@example.com"}).status_code == 200
    overflow = client.post("/eks-claim", data={"email": "late@example.com"})
    assert overflow.status_code == 200
    body = overflow.get_data(as_text=True)
    assert "All clusters claimed" in body
    assert "the workshop host" in body  # parameterized host name (WORKSHOP_HOST default)
    # Existing claimant can still re-display even when pool is exhausted.
    reclaim = client.post("/eks-claim", data={"email": "user0@example.com"})
    assert reclaim.status_code == 200
    assert "test-cluster-01" in reclaim.get_data(as_text=True)


def test_admin_auth(client):
    assert client.get("/admin").status_code == 403
    assert client.get("/admin?token=wrong").status_code == 403
    ok = client.get("/admin?token=test-admin-token")
    assert ok.status_code == 200
    body = ok.get_data(as_text=True)
    assert "Total" in body
    assert "Claimed" in body


# ---------- new two-path surface ----------------------------------------------

def test_root_is_the_eks_form(client):
    # The picker page was merged into the form. `/` should serve the form
    # itself — email input + submit button — with zero intermediate clicks.
    res = client.get("/")
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert 'name="email"' in body                     # form input present
    assert 'action="/eks-claim"' in body              # posts directly to claim endpoint
    assert "Claim my cluster" in body                 # CTA copy
    # The KodeKloud browser path is gone entirely; nothing should reference it.
    assert "KodeKloud" not in body
    assert 'href="/browser"' not in body


def test_eks_form_url_redirects_to_root(client):
    # Back-compat: any QR codes or shared links to /eks still land users in
    # the right place via a 302 to /.
    res = client.get("/eks")
    assert res.status_code == 302
    assert res.headers["Location"].endswith("/")


def test_browser_path_is_gone(client):
    # The KodeKloud browser path was removed: Packt issues EKS clusters only, and a
    # reachable /browser sent anyone with a direct link toward a course that is not
    # provisioned for these attendees. Both routes must 404, not merely be unlinked.
    assert client.get("/browser").status_code == 404
    assert client.post("/browser-claim", data={"email": "kk@example.com"}).status_code == 404


def test_no_kodekloud_reference_survives_on_any_page(client):
    client.post("/eks-claim", data={"email": "ed@example.com"})
    for res in (
        client.get("/"),
        client.post("/eks-claim", data={"email": "ed@example.com"}),
        client.get("/admin?token=test-admin-token"),
        client.get("/admin/export?token=test-admin-token"),
    ):
        assert "kodekloud" not in res.get_data(as_text=True).lower()


# ---------- VTT terminal_url wiring -------------------------------------------

def test_claim_with_terminal_url_shows_terminal_link(tmp_path, monkeypatch):
    # A cluster with a terminal_url leads the success page with the VTT link
    # while still handing over the AWS keys for anyone who wants the local path.
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv_with_terminal(
        csv_path,
        [
            ("adwc-dev", "AKIATESTKEY01", "secret01", "us-west-2",
             "http://example-elb.us-west-2.elb.amazonaws.com/terminal/"),
        ],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    res = client.post("/eks-claim", data={"email": "alice@example.com"})
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert "http://example-elb.us-west-2.elb.amazonaws.com/terminal/" in body
    assert "adwc-dev" in body
    # Keys still available for the local path.
    assert "AKIATESTKEY01" in body


def test_terminal_only_cluster_needs_no_keys(tmp_path, monkeypatch):
    # A VTT-only cluster (empty AWS keys) claims cleanly: the terminal link is
    # the whole path, and no local aws-configure commands are shown.
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv_with_terminal(
        csv_path,
        [
            ("adwc-dev", "", "", "us-west-2",
             "http://example-elb.us-west-2.elb.amazonaws.com/terminal/"),
        ],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    res = client.post("/eks-claim", data={"email": "bob@example.com"})
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert "http://example-elb.us-west-2.elb.amazonaws.com/terminal/" in body
    # No local-path setup command when there are no keys to configure.
    assert "aws eks update-kubeconfig" not in body


def test_pool_without_terminal_url_is_unchanged(tmp_path, monkeypatch):
    # Backward compatibility: a four-column pool (no terminal_url) still renders
    # the keys-and-commands page exactly as before.
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv(csv_path, [("test-cluster-01", "AKIATESTKEY01", "secret01", "us-west-2")])
    client = _make_client(tmp_path, monkeypatch, csv_path)
    res = client.post("/eks-claim", data={"email": "carol@example.com"})
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert "aws eks update-kubeconfig --name test-cluster-01" in body
    assert "/terminal/" not in body


# --- Pool convergence across a progressive rollout -------------------------------------------
# The fleet grows in stages (5 -> 54 -> 250) and the database lives on a persistent volume, so
# every restart re-reads a pool.csv that has MORE clusters than the last one. Seeding only when
# the table was empty meant the app kept serving the first stage's clusters forever: 54 built,
# 5 offered. Seeding must therefore be additive, and it must not disturb existing claims.

def test_growing_pool_adds_new_clusters_on_restart(tmp_path, monkeypatch):
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv_with_terminal(
        csv_path,
        [["student1", "", "", "us-west-2", "https://student1.example.com/"]],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    assert client.get("/admin?token=test-admin-token").status_code == 200

    # The fleet grows; the same database is reused, as it is on a Railway volume.
    _write_pool_csv_with_terminal(
        csv_path,
        [
            ["student1", "", "", "us-west-2", "https://student1.example.com/"],
            ["student2", "", "", "us-west-2", "https://student2.example.com/"],
            ["student3", "", "", "us-west-2", "https://student3.example.com/"],
        ],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    body = client.get("/admin?token=test-admin-token").get_data(as_text=True)
    assert ">3<" in body, "restart with a larger pool.csv must add the new clusters"


def test_reseeding_never_releases_an_existing_claim(tmp_path, monkeypatch):
    # The reason seeding was one-shot: a naive re-seed resets claimed_by, so a returning
    # attendee is handed a different cluster and two people can land on the same one.
    csv_path = tmp_path / "pool.csv"
    _write_pool_csv_with_terminal(
        csv_path,
        [["student1", "", "", "us-west-2", "https://student1.example.com/"]],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    first = client.post("/eks-claim", data={"email": "attendee@example.com"})
    assert first.status_code == 200

    _write_pool_csv_with_terminal(
        csv_path,
        [
            ["student1", "", "", "us-west-2", "https://student1.example.com/"],
            ["student2", "", "", "us-west-2", "https://student2.example.com/"],
        ],
    )
    client = _make_client(tmp_path, monkeypatch, csv_path)
    export = client.get("/admin/export?token=test-admin-token").get_data(as_text=True)
    assert "attendee@example.com,student1" in export, "the existing claim must survive a re-seed"
