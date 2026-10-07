import pytest

from app import clean_name, create_app


@pytest.fixture
def client(tmp_path):
    app = create_app(f"sqlite:///{tmp_path}/test.db")
    app.config["API_KEY"] = ""
    return app.test_client()


@pytest.mark.parametrize("raw", ["Ramesh", "Ramesh bhai", "Rameshbhai", "Shri Ramesh ji", "  ramesh  "])
def test_clean_name_strips_honorifics(raw):
    assert clean_name(raw) == "Ramesh"


def test_health_and_ready(client):
    assert client.get("/health").get_json()["status"] == "ok"
    assert client.get("/ready").status_code == 200


def test_ledger_flow_and_balance(client):
    client.post("/entries", json={"customer": "Ramesh bhai", "amount": 500, "type": "udhar"})
    client.post("/entries", json={"customer": "Rameshbhai", "amount": 200, "type": "payment"})
    client.post("/entries", json={"customer": "Sunita", "amount": 100, "type": "sale"})
    body = client.get("/balance/Shri Ramesh ji").get_json()
    assert body["balance"] == 300
    assert body["reminder"] == "Ramesh ji, ₹300 बाकी हैं."
    assert len(client.get("/entries").get_json()) == 3


def test_data_persists_across_app_instances(tmp_path):
    url = f"sqlite:///{tmp_path}/ledger.db"
    create_app(url).test_client().post("/entries", json={"customer": "Asha", "amount": 50, "type": "udhar"})
    assert create_app(url).test_client().get("/balance/Asha").get_json()["balance"] == 50


@pytest.mark.parametrize("bad", [
    {"customer": "", "amount": 10, "type": "udhar"},
    {"customer": "Ramesh", "amount": -5, "type": "udhar"},
    {"customer": "Ramesh", "amount": 10, "type": "loan"},
])
def test_rejects_bad_entries(client, bad):
    assert client.post("/entries", json=bad).status_code == 400


def test_api_key_enforced(tmp_path):
    app = create_app(f"sqlite:///{tmp_path}/k.db")
    app.config["API_KEY"] = "s3cret"
    c = app.test_client()
    entry = {"customer": "Ramesh", "amount": 10, "type": "udhar"}
    assert c.post("/entries", json=entry).status_code == 401
    assert c.post("/entries", json=entry, headers={"X-API-Key": "s3cret"}).status_code == 201


def test_metrics_exposed(client):
    client.get("/health")
    text = client.get("/metrics").get_data(as_text=True)
    assert "kirana_http_requests_total" in text
    assert "kirana_http_request_duration_seconds_bucket" in text
