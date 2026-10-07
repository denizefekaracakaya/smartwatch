from types import SimpleNamespace

import anthropic
import httpx2
import pytest

API = "/api/v1/assistant/search"


def tool_use(id_, name, input_):
    return SimpleNamespace(type="tool_use", id=id_, name=name, input=input_)


def reply(*blocks, stop_reason="tool_use"):
    return SimpleNamespace(content=list(blocks), stop_reason=stop_reason)


class FakeClaude:
    """Mimics ``client.beta.messages.create`` with a scripted list of responses."""

    def __init__(self, script):
        self.script = list(script)
        self.calls = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    def _create(self, **kwargs):
        self.calls.append(kwargs)
        item = self.script.pop(0)
        if isinstance(item, Exception):
            raise item
        return item(kwargs) if callable(item) else item


def test_fallback_without_api_key(client, app, users, catalog):
    app.state.assistant_client = None  # what create_app sets up when ANTHROPIC_API_KEY is absent
    h = users.create()["headers"]
    r = client.post(API, headers=h, json={"query": "yaz ruzgari"})
    assert r.status_code == 200
    body = r.json()
    assert body["ai_used"] is False
    assert body["matches"][0]["track"]["title"] == "Yaz Rüzgarı"


@pytest.fixture
def fake():
    return FakeClaude([])


@pytest.fixture
def assistant_client(fake):
    return fake


def test_tool_loop_returns_only_catalog_tracks(client, users, catalog, fake):
    h = users.create()["headers"]
    real_id = catalog["Yaz Rüzgarı"]

    def second_turn(kwargs):
        # the tool result for the search must have been sent back with the matching id
        results = kwargs["messages"][-1]["content"]
        assert results[0]["type"] == "tool_result" and str(real_id) in results[0]["content"]
        return reply(
            tool_use(
                "t2",
                "submit_results",
                {
                    "matches": [
                        {"track_id": real_id, "reason": "Bodrum'da geçen yaz şarkısı"},
                        {"track_id": 424242, "reason": "hallucinated"},
                        {"track_id": real_id, "reason": "duplicate"},
                    ],
                    "message": "Sanırım aradığınız bu!",
                },
            )
        )

    fake.script = [
        reply(tool_use("t1", "search_catalog", {"query": "yaz bodrum gel yanıma", "kind": "song"})),
        second_turn,
    ]
    r = client.post(API, headers=h, json={"query": "bodrumda geçen yaz şarkısı, nakaratta gel yanıma diyor"})
    body = r.json()
    assert r.status_code == 200, body
    assert body["ai_used"] is True
    assert [m["track"]["id"] for m in body["matches"]] == [real_id]
    assert body["matches"][0]["reason"] == "Bodrum'da geçen yaz şarkısı"
    assert body["message"] == "Sanırım aradığınız bu!"

    first = fake.calls[0]
    assert first["model"] == "claude-opus-5-5"
    assert first["fallbacks"] == "default" and first["betas"] == ["server-side-fallback-2026-07-01"]
    assert "<request>" in first["messages"][0]["content"]


def test_ids_not_returned_by_search_are_rejected(client, users, catalog, fake):
    h = users.create()["headers"]
    other = catalog["Neon Kalpler"]  # exists in DB but was never returned by a search in this session
    fake.script = [
        reply(
            tool_use("t1", "submit_results", {"matches": [{"track_id": other, "reason": "x"}], "message": ""})
        )
    ]
    body = client.post(API, headers=h, json={"query": "something"}).json()
    assert body["ai_used"] is True and body["matches"] == []
    assert body["message"] == "Eşleşme bulunamadı."


def test_invalid_tool_input_is_reported_as_error(client, users, catalog, fake):
    h = users.create()["headers"]

    def check(kwargs):
        result = kwargs["messages"][-1]["content"][0]
        assert result["is_error"] is True
        return reply(tool_use("t2", "submit_results", {"matches": [], "message": "Bulamadım"}))

    fake.script = [reply(tool_use("t1", "search_catalog", {"kind": "song"})), check]
    body = client.post(API, headers=h, json={"query": "abc def"}).json()
    assert body["ai_used"] is True and body["message"] == "Bulamadım"


@pytest.mark.parametrize(
    "failure",
    [
        anthropic.APITimeoutError(request=httpx2.Request("POST", "https://api.anthropic.com/v1/messages")),
        reply(stop_reason="refusal"),
        reply(SimpleNamespace(type="text", text="I think it's X"), stop_reason="end_turn"),
    ],
)
def test_failures_fall_back_to_fuzzy_search(client, users, catalog, fake, failure):
    h = users.create()["headers"]
    fake.script = [failure]
    body = client.post(API, headers=h, json={"query": "neon kalpler"}).json()
    assert body["ai_used"] is False
    assert body["matches"][0]["track"]["title"] == "Neon Kalpler"


def test_iteration_cap(client, users, catalog, fake, settings):
    h = users.create()["headers"]
    fake.script = [
        reply(tool_use(f"t{i}", "search_catalog", {"query": "x", "kind": "any"}))
        for i in range(settings.assistant_max_iterations)
    ]
    body = client.post(API, headers=h, json={"query": "neon kalpler"}).json()
    assert body["ai_used"] is False
    assert len(fake.calls) == settings.assistant_max_iterations


def test_assistant_validation_and_auth(client, users):
    assert client.post(API, json={"query": "abc"}).status_code == 401
    h = users.create()["headers"]
    assert client.post(API, headers=h, json={"query": "x" * 501}).status_code == 422
    assert client.post(API, headers=h, json={"query": " "}).status_code == 422
