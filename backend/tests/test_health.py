def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert r.headers["X-Content-Type-Options"] == "nosniff"


def test_unknown_route_uses_error_format(client):
    r = client.get("/api/v1/nope")
    assert r.status_code == 404
    assert r.json()["code"] == "not_found"


def test_production_refuses_insecure_settings():
    import pytest

    from app.config import Settings

    with pytest.raises(ValueError):
        Settings(environment="production", _env_file=None)
    with pytest.raises(ValueError):
        Settings(environment="production", secret_key="x" * 40, public_base_url="http://a", _env_file=None)
    Settings(environment="production", secret_key="x" * 40, public_base_url="https://a", _env_file=None)
