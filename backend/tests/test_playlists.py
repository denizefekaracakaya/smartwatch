API = "/api/v1/playlists"


def _titles(body):
    return [t["title"] for t in body["tracks"]]


def test_playlist_crud(client, users, catalog):
    h = users.create()["headers"]
    r = client.post(API, headers=h, json={"name": "  Yolculuk  ", "description": "Araba için"})
    assert r.status_code == 201
    pid = r.json()["id"]
    assert r.json()["name"] == "Yolculuk" and r.json()["tracks"] == []

    r = client.patch(f"{API}/{pid}", headers=h, json={"name": "Uzun Yol"})
    assert r.json()["name"] == "Uzun Yol" and r.json()["description"] == "Araba için"
    r = client.patch(f"{API}/{pid}", headers=h, json={"description": None})
    assert r.json()["description"] is None
    assert client.patch(f"{API}/{pid}", headers=h, json={"name": None}).status_code == 422
    assert client.patch(f"{API}/{pid}", headers=h, json={"name": "   "}).status_code == 422

    listing = client.get(API, headers=h).json()
    assert [(p["name"], p["track_count"]) for p in listing] == [("Uzun Yol", 0)]

    assert client.delete(f"{API}/{pid}", headers=h).status_code == 204
    assert client.get(f"{API}/{pid}", headers=h).status_code == 404


def test_add_remove_reorder(client, users, catalog):
    h = users.create()["headers"]
    pid = client.post(API, headers=h, json={"name": "Mix"}).json()["id"]
    a, b, c = catalog["Yaz Rüzgarı"], catalog["Neon Kalpler"], catalog["Midnight Train"]

    for tid in (a, b):
        assert client.post(f"{API}/{pid}/tracks", headers=h, json={"track_id": tid}).status_code == 201
    r = client.post(f"{API}/{pid}/tracks", headers=h, json={"track_id": c, "position": 0})
    assert _titles(r.json()) == ["Midnight Train", "Yaz Rüzgarı", "Neon Kalpler"]

    dup = client.post(f"{API}/{pid}/tracks", headers=h, json={"track_id": a})
    assert dup.status_code == 409 and dup.json()["code"] == "already_in_playlist"
    assert client.post(f"{API}/{pid}/tracks", headers=h, json={"track_id": 99999}).status_code == 404

    r = client.put(f"{API}/{pid}/tracks", headers=h, json={"track_ids": [b, a, c]})
    assert _titles(r.json()) == ["Neon Kalpler", "Yaz Rüzgarı", "Midnight Train"]
    assert client.put(f"{API}/{pid}/tracks", headers=h, json={"track_ids": [a, b]}).status_code == 422
    assert client.put(f"{API}/{pid}/tracks", headers=h, json={"track_ids": [a, a, b]}).status_code == 422

    r = client.delete(f"{API}/{pid}/tracks/{a}", headers=h)
    assert _titles(r.json()) == ["Neon Kalpler", "Midnight Train"]
    assert client.delete(f"{API}/{pid}/tracks/{a}", headers=h).status_code == 404

    # order persists across reads and the summary count is right
    assert _titles(client.get(f"{API}/{pid}", headers=h).json()) == ["Neon Kalpler", "Midnight Train"]
    assert client.get(API, headers=h).json()[0]["track_count"] == 2


def test_playlists_are_isolated_between_users(client, users, catalog):
    alice = users.create()["headers"]
    bob = users.create()["headers"]
    pid = client.post(API, headers=alice, json={"name": "Alice only"}).json()["id"]
    tid = catalog["Yaz Rüzgarı"]

    assert client.get(API, headers=bob).json() == []
    assert client.get(f"{API}/{pid}", headers=bob).status_code == 404
    assert client.patch(f"{API}/{pid}", headers=bob, json={"name": "hacked"}).status_code == 404
    assert client.post(f"{API}/{pid}/tracks", headers=bob, json={"track_id": tid}).status_code == 404
    assert client.put(f"{API}/{pid}/tracks", headers=bob, json={"track_ids": []}).status_code == 404
    assert client.delete(f"{API}/{pid}", headers=bob).status_code == 404
    assert client.get(f"{API}/{pid}", headers=alice).json()["name"] == "Alice only"


def test_playlists_require_auth(client):
    assert client.get(API).status_code == 401
    assert client.post(API, json={"name": "x"}).status_code == 401


def test_deleting_account_deletes_playlists(client, users, app):
    from sqlalchemy import func, select

    from app.models import Playlist
    from tests.conftest import PASSWORD

    u = users.create()
    client.post(API, headers=u["headers"], json={"name": "gone"})
    client.request("DELETE", "/api/v1/auth/me", headers=u["headers"], json={"password": PASSWORD})
    with app.state.db.session_factory() as db:
        assert db.scalar(select(func.count(Playlist.id))) == 0
