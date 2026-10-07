"""Kirana ledger API: a tiny udhar (credit) ledger used as the CI/CD demo app."""
import os
import re

from flask import Flask, jsonify, request

HONORIFICS = re.compile(r"^(shri|smt)\s+|\s*(bhai|ji|behen|bhaiya)$", re.IGNORECASE)
VALID_TYPES = {"udhar", "payment", "sale"}


def clean_name(name: str) -> str:
    """'Shri Ramesh ji' / 'Rameshbhai' / 'ramesh bhai' -> 'Ramesh'."""
    name = name.strip()
    name = re.sub(r"(?i)bhai$", "", name)  # Rameshbhai -> Ramesh
    previous = None
    while previous != name:
        previous = name
        name = HONORIFICS.sub("", name).strip()
    return name.title()


def create_app() -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False  # return "बाकी" as UTF-8, not \u escapes
    app.config["ENTRIES"] = []
    app.config["API_KEY"] = os.environ.get("API_KEY", "")

    @app.get("/health")
    def health():
        return {"status": "ok", "version": os.environ.get("APP_VERSION", "dev")}

    @app.get("/entries")
    def list_entries():
        return jsonify(app.config["ENTRIES"])

    @app.post("/entries")
    def add_entry():
        if app.config["API_KEY"] and request.headers.get("X-API-Key") != app.config["API_KEY"]:
            return {"error": "invalid API key"}, 401
        data = request.get_json(silent=True) or {}
        customer = clean_name(str(data.get("customer", "")))
        amount = data.get("amount")
        entry_type = data.get("type")
        if not customer or not isinstance(amount, (int, float)) or amount <= 0 or entry_type not in VALID_TYPES:
            return {"error": "need customer, positive amount, type in udhar|payment|sale"}, 400
        entry = {"customer": customer, "amount": amount, "type": entry_type}
        app.config["ENTRIES"].append(entry)
        return entry, 201

    @app.get("/balance/<customer>")
    def balance(customer):
        name = clean_name(customer)
        total = 0
        for e in app.config["ENTRIES"]:
            if e["customer"] == name:
                total += e["amount"] if e["type"] == "udhar" else -e["amount"] if e["type"] == "payment" else 0
        return {"customer": name, "balance": total, "reminder": f"{name} ji, ₹{total} बाकी हैं."}

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=8000)
