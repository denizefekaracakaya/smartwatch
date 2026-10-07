from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.models import AuthToken, TokenPurpose, User
from tests.conftest import PASSWORD, last_reset_code, last_verification_token

API = "/api/v1/auth"


def _db(app):
    return app.state.db.session_factory()


# ---------- registration & hashing ----------
def test_register_stores_argon2_hash_and_sends_verification(client, app, mailer):
    r = client.post(
        f"{API}/register", json={"email": " Ada@Example.COM ", "password": PASSWORD, "display_name": "Ada"}
    )
    assert r.status_code == 201
    body = r.json()
    assert body["email"] == "ada@example.com"
    assert body["email_verified"] is False
    assert "password" not in str(body)

    with _db(app) as db:
        user = db.scalar(select(User))
        assert user.password_hash.startswith("$argon2id$")
        assert PASSWORD not in user.password_hash
        token = db.scalar(select(AuthToken).where(AuthToken.purpose == TokenPurpose.EMAIL_VERIFY))
        raw = last_verification_token(mailer)
        assert token.token_hash != raw and len(token.token_hash) == 64  # only the digest is stored

    assert mailer.outbox[-1].to == "ada@example.com"


def test_register_duplicate_email(client, users):
    users.create("dup@example.com")
    r = client.post(
        f"{API}/register", json={"email": "DUP@example.com", "password": PASSWORD, "display_name": "x"}
    )
    assert r.status_code == 409
    assert r.json()["code"] == "email_taken"


def test_register_rejects_weak_password_and_bad_email(client):
    for password in ["short1", "onlyletterslong", "1234567890123"]:
        r = client.post(
            f"{API}/register", json={"email": "a@example.com", "password": password, "display_name": "A"}
        )
        assert r.status_code == 422, password
        assert r.json()["code"] == "validation_error"
    r = client.post(
        f"{API}/register", json={"email": "not-an-email", "password": PASSWORD, "display_name": "A"}
    )
    assert r.status_code == 422


# ---------- verification ----------
def test_login_requires_verified_email(client, users):
    users.create("new@example.com", verified=False)
    r = client.post(f"{API}/login", json={"email": "new@example.com", "password": PASSWORD})
    assert r.status_code == 403
    assert r.json()["code"] == "email_not_verified"


def test_verification_token_single_use(client, users, mailer):
    users.create("v@example.com", verified=False)
    token = last_verification_token(mailer)
    assert client.post(f"{API}/verify-email", json={"token": token}).json()["email_verified"] is True
    r = client.post(f"{API}/verify-email", json={"token": token})
    assert r.status_code == 400 and r.json()["code"] == "invalid_token"


def test_verification_link_page_requires_explicit_confirmation(client, users, mailer):
    users.create("link@example.com", verified=False)
    token = last_verification_token(mailer)
    # GET (what link-prefetching mail scanners do) must not consume the token
    page = client.get(f"{API}/verify-email", params={"token": token})
    assert page.status_code == 200 and "<form method='post'" in page.text and token in page.text
    page = client.get(f"{API}/verify-email", params={"token": token})
    assert page.status_code == 200
    assert (
        client.post(f"{API}/login", json={"email": "link@example.com", "password": PASSWORD}).status_code
        == 403
    )

    r = client.post(f"{API}/verify-email/confirm", data={"token": token})
    assert r.status_code == 200 and "doğrulandı" in r.text
    r = client.post(f"{API}/verify-email/confirm", data={"token": token})
    assert r.status_code == 400
    assert (
        client.post(f"{API}/login", json={"email": "link@example.com", "password": PASSWORD}).status_code
        == 200
    )


def test_verification_link_escapes_token(client):
    r = client.get(f"{API}/verify-email", params={"token": "x'><script>alert(1)</script>"})
    assert "<script>" not in r.text
    assert client.post(f"{API}/verify-email/confirm", data={}).status_code == 422


def test_expired_verification_token(client, app, users, mailer):
    users.create("exp@example.com", verified=False)
    token = last_verification_token(mailer)
    with _db(app) as db:
        for t in db.scalars(select(AuthToken)):
            t.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        db.commit()
    assert client.post(f"{API}/verify-email", json={"token": token}).status_code == 400


def test_resend_verification_invalidates_old_link_and_does_not_enumerate(client, users, mailer):
    users.create("re@example.com", verified=False)
    old = last_verification_token(mailer)
    r = client.post(f"{API}/resend-verification", json={"email": "re@example.com"})
    assert r.status_code == 202
    new = last_verification_token(mailer)
    assert new != old
    assert client.post(f"{API}/verify-email", json={"token": old}).status_code == 400
    assert client.post(f"{API}/verify-email", json={"token": new}).status_code == 200

    sent = len(mailer.outbox)
    r2 = client.post(f"{API}/resend-verification", json={"email": "ghost@example.com"})
    assert r2.status_code == 202 and r2.json() == r.json()
    assert len(mailer.outbox) == sent


# ---------- login & sessions ----------
def test_login_wrong_password_and_unknown_user_look_identical(client, users):
    users.create("l@example.com")
    a = client.post(f"{API}/login", json={"email": "l@example.com", "password": "WrongPass123"})
    b = client.post(f"{API}/login", json={"email": "nobody@example.com", "password": "WrongPass123"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_me_requires_valid_access_token(client, users):
    u = users.create()
    assert client.get(f"{API}/me", headers=u["headers"]).json()["email"] == u["email"]
    assert client.get(f"{API}/me").status_code == 401
    assert client.get(f"{API}/me", headers={"Authorization": "Bearer garbage"}).status_code == 401
    # a refresh token is not an access token
    bad = {"Authorization": f"Bearer {u['tokens']['refresh_token']}"}
    assert client.get(f"{API}/me", headers=bad).status_code == 401


def test_refresh_rotation_and_reuse_detection(client, users):
    u = users.create()
    first = u["tokens"]["refresh_token"]
    r = client.post(f"{API}/refresh", json={"refresh_token": first})
    assert r.status_code == 200
    second = r.json()["refresh_token"]
    assert second != first

    # Reusing the rotated token is treated as theft: the whole family is revoked.
    assert client.post(f"{API}/refresh", json={"refresh_token": first}).status_code == 401
    assert client.post(f"{API}/refresh", json={"refresh_token": second}).status_code == 401


def test_logout_revokes_refresh_token(client, users):
    u = users.create()
    rt = u["tokens"]["refresh_token"]
    assert client.post(f"{API}/logout", json={"refresh_token": rt}).status_code == 204
    assert client.post(f"{API}/refresh", json={"refresh_token": rt}).status_code == 401


def test_expired_refresh_token(client, app, users):
    u = users.create()
    with _db(app) as db:
        for t in db.scalars(select(AuthToken).where(AuthToken.purpose == TokenPurpose.REFRESH)):
            t.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        db.commit()
    assert (
        client.post(f"{API}/refresh", json={"refresh_token": u["tokens"]["refresh_token"]}).status_code == 401
    )


# ---------- password reset ----------
def test_password_reset_flow(client, users, mailer):
    u = users.create("reset@example.com")
    assert client.post(f"{API}/forgot-password", json={"email": "reset@example.com"}).status_code == 202
    code = last_reset_code(mailer)
    r = client.post(
        f"{API}/reset-password",
        json={"email": "reset@example.com", "code": code, "new_password": "BrandNewPass9"},
    )
    assert r.status_code == 204
    # old sessions are revoked, old password no longer works, new one does
    assert (
        client.post(f"{API}/refresh", json={"refresh_token": u["tokens"]["refresh_token"]}).status_code == 401
    )
    assert (
        client.post(f"{API}/login", json={"email": "reset@example.com", "password": PASSWORD}).status_code
        == 401
    )
    assert (
        client.post(
            f"{API}/login", json={"email": "reset@example.com", "password": "BrandNewPass9"}
        ).status_code
        == 200
    )
    # code is single use
    r = client.post(
        f"{API}/reset-password",
        json={"email": "reset@example.com", "code": code, "new_password": "Another1Pass"},
    )
    assert r.status_code == 400


def test_password_reset_attempt_cap(client, users, mailer):
    users.create("cap@example.com")
    client.post(f"{API}/forgot-password", json={"email": "cap@example.com"})
    code = last_reset_code(mailer)
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(5):
        r = client.post(
            f"{API}/reset-password",
            json={"email": "cap@example.com", "code": wrong, "new_password": "BrandNewPass9"},
        )
        assert r.status_code == 400
    # after 5 failures even the correct code is dead
    r = client.post(
        f"{API}/reset-password",
        json={"email": "cap@example.com", "code": code, "new_password": "BrandNewPass9"},
    )
    assert r.status_code == 400


def test_forgot_password_does_not_enumerate(client, mailer):
    r = client.post(f"{API}/forgot-password", json={"email": "ghost@example.com"})
    assert r.status_code == 202
    assert mailer.outbox == []


def test_reset_code_stored_as_keyed_digest(client, app, users, mailer):
    users.create("hash@example.com")
    client.post(f"{API}/forgot-password", json={"email": "hash@example.com"})
    code = last_reset_code(mailer)
    with _db(app) as db:
        token = db.scalar(select(AuthToken).where(AuthToken.purpose == TokenPurpose.PASSWORD_RESET))
        assert code not in token.token_hash


# ---------- account management ----------
def test_change_password_revokes_other_sessions(client, users):
    u = users.create()
    r = client.post(
        f"{API}/me/change-password",
        headers=u["headers"],
        json={"current_password": PASSWORD, "new_password": "Changed1234x"},
    )
    assert r.status_code == 200
    assert (
        client.post(f"{API}/refresh", json={"refresh_token": u["tokens"]["refresh_token"]}).status_code == 401
    )
    assert client.post(f"{API}/refresh", json={"refresh_token": r.json()["refresh_token"]}).status_code == 200

    r = client.post(
        f"{API}/me/change-password",
        headers=u["headers"],
        json={"current_password": "wrong-pass", "new_password": "Changed1234y"},
    )
    assert r.status_code == 401


def test_update_profile_and_delete_account(client, users):
    u = users.create()
    r = client.patch(f"{API}/me", headers=u["headers"], json={"display_name": "  New Name "})
    assert r.json()["display_name"] == "New Name"
    r = client.request("DELETE", f"{API}/me", headers=u["headers"], json={"password": "nope"})
    assert r.status_code == 401
    r = client.request("DELETE", f"{API}/me", headers=u["headers"], json={"password": PASSWORD})
    assert r.status_code == 204
    assert client.get(f"{API}/me", headers=u["headers"]).status_code == 401


# ---------- rate limiting ----------
def test_login_rate_limited(client, users):
    users.create("rl@example.com")
    codes = [
        client.post(f"{API}/login", json={"email": "rl@example.com", "password": "WrongPass123"}).status_code
        for _ in range(12)
    ]
    assert codes[:9] == [401] * 9  # one login already used by the factory
    assert 429 in codes
    r = client.post(f"{API}/login", json={"email": "rl@example.com", "password": "WrongPass123"})
    assert r.json()["code"] == "rate_limited" and "Retry-After" in r.headers


# ---------- access-token invalidation ----------
def test_password_change_invalidates_outstanding_access_and_stream_tokens(client, users, catalog):
    u = users.create()
    tid = catalog["Yaz Rüzgarı"]
    stream = client.get(f"/api/v1/tracks/{tid}/stream-url", headers=u["headers"]).json()["url"]
    stream = stream.replace("http://testserver", "")
    assert client.get(stream, headers={"Range": "bytes=0-9"}).status_code == 206

    r = client.post(
        f"{API}/me/change-password",
        headers=u["headers"],
        json={"current_password": PASSWORD, "new_password": "Changed1234x"},
    )
    assert r.status_code == 200
    assert client.get(f"{API}/me", headers=u["headers"]).status_code == 401
    assert client.get(stream, headers={"Range": "bytes=0-9"}).status_code == 401
    fresh = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get(f"{API}/me", headers=fresh).status_code == 200


def test_password_reset_invalidates_outstanding_access_tokens(client, users, mailer):
    u = users.create("epoch@example.com")
    client.post(f"{API}/forgot-password", json={"email": "epoch@example.com"})
    r = client.post(
        f"{API}/reset-password",
        json={"email": "epoch@example.com", "code": last_reset_code(mailer), "new_password": "BrandNewPass9"},
    )
    assert r.status_code == 204
    assert client.get(f"{API}/me", headers=u["headers"]).status_code == 401


def test_verification_confirm_rejects_oversized_body(client):
    r = client.post(f"{API}/verify-email/confirm", data={"token": "x" * 2000})
    assert r.status_code == 413
