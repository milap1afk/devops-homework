import pytest

from app.config import settings
from app.schemas import clean_name


def add(client, customer, amount, type_, **headers):
    return client.post("/api/entries", json={"customer": customer, "amount": amount, "type": type_}, headers=headers)


@pytest.mark.parametrize("raw", ["Ramesh", "Ramesh bhai", "Rameshbhai", "Shri Ramesh ji", "  ramesh  "])
def test_clean_name_strips_honorifics(raw):
    assert clean_name(raw) == "Ramesh"


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_ready(client):
    assert client.get("/ready").json() == {"status": "ready"}


def test_create_and_list_entries(client):
    r = add(client, "Ramesh bhai", 500, "udhar")
    assert r.status_code == 201
    assert r.json()["customer"] == "Ramesh"
    entries = client.get("/api/entries").json()
    assert len(entries) == 1 and entries[0]["amount"] == 500


def test_get_update_delete_entry(client):
    entry_id = add(client, "Sunita", 200, "udhar").json()["id"]
    assert client.get(f"/api/entries/{entry_id}").json()["customer"] == "Sunita"

    r = client.put(f"/api/entries/{entry_id}", json={"customer": "Sunita ji", "amount": 250, "type": "udhar"})
    assert r.status_code == 200 and r.json()["amount"] == 250

    assert client.delete(f"/api/entries/{entry_id}").status_code == 204
    assert client.get(f"/api/entries/{entry_id}").status_code == 404


def test_balance_and_reminder(client):
    add(client, "Ramesh bhai", 500, "udhar")
    add(client, "Rameshbhai", 200, "payment")
    add(client, "Ramesh", 999, "sale")  # cash sale does not change the balance
    body = client.get("/api/customers/Shri Ramesh ji").json()
    assert body["balance"] == 300
    assert body["reminder"] == "Ramesh ji, ₹300 बाकी हैं."


def test_customers_sorted_biggest_first_and_settled_hidden(client):
    add(client, "Asha", 100, "udhar")
    add(client, "Ravi", 900, "udhar")
    add(client, "Meena", 50, "udhar")
    add(client, "Meena", 50, "payment")  # settled -> not listed
    names = [c["customer"] for c in client.get("/api/customers").json()]
    assert names == ["Ravi", "Asha"]


@pytest.mark.parametrize("bad", [
    {"customer": "", "amount": 10, "type": "udhar"},
    {"customer": "Ramesh", "amount": -5, "type": "udhar"},
    {"customer": "Ramesh", "amount": 10, "type": "loan"},
])
def test_rejects_invalid_entries(client, bad):
    assert client.post("/api/entries", json=bad).status_code == 422


def test_unknown_entry_is_404(client):
    assert client.get("/api/entries/999").status_code == 404
    assert client.put("/api/entries/999", json={"customer": "X", "amount": 1, "type": "sale"}).status_code == 404


def test_api_key_protects_writes(client):
    settings.api_key = "s3cret"
    assert add(client, "Ramesh", 10, "udhar").status_code == 401
    assert add(client, "Ramesh", 10, "udhar", **{"X-API-Key": "s3cret"}).status_code == 201
    assert client.get("/api/entries").status_code == 200  # reads stay open


def test_metrics_endpoint(client):
    add(client, "Ramesh", 10, "udhar")
    client.get("/api/entries")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert 'kirana_ledger_entries_total{type="udhar"}' in text
