import pytest

from app import clean_name, create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["API_KEY"] = ""
    return app.test_client()


@pytest.mark.parametrize("raw", ["Ramesh", "Ramesh bhai", "Rameshbhai", "Shri Ramesh ji", "  ramesh  "])
def test_clean_name_strips_honorifics(raw):
    assert clean_name(raw) == "Ramesh"


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_add_and_balance(client):
    client.post("/entries", json={"customer": "Ramesh bhai", "amount": 500, "type": "udhar"})
    client.post("/entries", json={"customer": "Rameshbhai", "amount": 200, "type": "payment"})
    client.post("/entries", json={"customer": "Sunita", "amount": 100, "type": "sale"})
    r = client.get("/balance/Shri Ramesh ji")
    body = r.get_json()
    assert body["balance"] == 300
    assert body["reminder"] == "Ramesh ji, ₹300 बाकी हैं."


@pytest.mark.parametrize("bad", [
    {"customer": "", "amount": 10, "type": "udhar"},
    {"customer": "Ramesh", "amount": -5, "type": "udhar"},
    {"customer": "Ramesh", "amount": 10, "type": "loan"},
])
def test_rejects_bad_entries(client, bad):
    assert client.post("/entries", json=bad).status_code == 400


def test_api_key_required_when_set():
    app = create_app()
    app.config["API_KEY"] = "s3cret"
    c = app.test_client()
    entry = {"customer": "Ramesh", "amount": 10, "type": "udhar"}
    assert c.post("/entries", json=entry).status_code == 401
    assert c.post("/entries", json=entry, headers={"X-API-Key": "s3cret"}).status_code == 201
