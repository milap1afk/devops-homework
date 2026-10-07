"""Kirana ledger API - final DevOps project.

Stateless web tier: entries are stored in PostgreSQL (DATABASE_URL=postgresql://...) or, for
local runs and unit tests, SQLite (DATABASE_URL=sqlite:///path or unset -> in-memory).
"""
import os
import re
import sqlite3
import time

from flask import Flask, Response, g, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

HONORIFICS = re.compile(r"^(shri|smt)\s+|\s*(bhai|ji|behen|bhaiya)$", re.IGNORECASE)
VALID_TYPES = {"udhar", "payment", "sale"}

REQUESTS = Counter("kirana_http_requests_total", "HTTP requests", ["method", "endpoint", "status"])
LATENCY = Histogram("kirana_http_request_duration_seconds", "Request latency", ["endpoint"])
ENTRIES = Counter("kirana_ledger_entries_total", "Ledger entries recorded", ["type"])


def clean_name(name: str) -> str:
    """'Shri Ramesh ji' / 'Rameshbhai' / 'ramesh bhai' -> 'Ramesh'."""
    name = re.sub(r"(?i)bhai$", "", name.strip())
    previous = None
    while previous != name:
        previous = name
        name = HONORIFICS.sub("", name).strip()
    return name.title()


class Store:
    """Tiny storage layer over sqlite3 or psycopg (same SQL, different placeholder)."""

    def __init__(self, url: str):
        self.url = url
        self.pg = url.startswith("postgresql://")
        self.ph = "%s" if self.pg else "?"
        self._memory = None
        with self.connect() as conn:
            cur = conn.cursor()
            cur.execute(
                "CREATE TABLE IF NOT EXISTS entries ("
                + ("id SERIAL PRIMARY KEY, " if self.pg else "id INTEGER PRIMARY KEY AUTOINCREMENT, ")
                + "customer TEXT NOT NULL, amount REAL NOT NULL, type TEXT NOT NULL)"
            )
            conn.commit()

    def connect(self):
        if self.pg:
            import psycopg  # imported lazily so unit tests need no PostgreSQL driver

            return psycopg.connect(self.url, connect_timeout=3)
        path = self.url.removeprefix("sqlite:///") if self.url else ":memory:"
        if path == ":memory:":  # keep one shared in-memory DB for the process
            if self._memory is None:
                self._memory = sqlite3.connect(":memory:", check_same_thread=False)
            return _NoClose(self._memory)
        return sqlite3.connect(path)

    def add(self, customer, amount, entry_type):
        with self.connect() as conn:
            conn.cursor().execute(
                f"INSERT INTO entries (customer, amount, type) VALUES ({self.ph}, {self.ph}, {self.ph})",
                (customer, amount, entry_type),
            )
            conn.commit()

    def all(self):
        with self.connect() as conn:
            cur = conn.cursor()
            cur.execute("SELECT customer, amount, type FROM entries ORDER BY id")
            return [{"customer": c, "amount": a, "type": t} for c, a, t in cur.fetchall()]

    def balance(self, customer):
        with self.connect() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT COALESCE(SUM(CASE type WHEN 'udhar' THEN amount WHEN 'payment' THEN -amount ELSE 0 END), 0)"
                f" FROM entries WHERE customer = {self.ph}",
                (customer,),
            )
            return cur.fetchone()[0]

    def ping(self):
        with self.connect() as conn:
            conn.cursor().execute("SELECT 1")


class _NoClose:
    """Context-manager wrapper so the shared in-memory SQLite connection is not closed."""

    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self.conn

    def __exit__(self, *exc):
        return False

    def cursor(self):
        return self.conn.cursor()

    def commit(self):
        self.conn.commit()


def create_app(database_url=None) -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False
    app.config["API_KEY"] = os.environ.get("API_KEY", "")
    app.config["STORE"] = Store(database_url if database_url is not None else os.environ.get("DATABASE_URL", ""))
    shop = os.environ.get("SHOP_NAME", "Kirana Store")

    @app.before_request
    def start_timer():
        g.start = time.perf_counter()

    @app.after_request
    def record_metrics(response):
        endpoint = request.url_rule.rule if request.url_rule else "unknown"
        if endpoint != "/metrics":
            REQUESTS.labels(request.method, endpoint, response.status_code).inc()
            LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        return response

    @app.get("/health")
    def health():  # liveness: the process is up
        return {"status": "ok", "version": os.environ.get("APP_VERSION", "dev"), "shop": shop}

    @app.get("/ready")
    def ready():  # readiness: the database is reachable
        try:
            app.config["STORE"].ping()
            return {"status": "ready"}
        except Exception as exc:  # noqa: BLE001 - report any DB failure as not ready
            return {"status": "not ready", "error": type(exc).__name__}, 503

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    @app.get("/entries")
    def list_entries():
        return app.config["STORE"].all()

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
        app.config["STORE"].add(customer, amount, entry_type)
        ENTRIES.labels(entry_type).inc()
        return {"customer": customer, "amount": amount, "type": entry_type}, 201

    @app.get("/balance/<customer>")
    def balance(customer):
        name = clean_name(customer)
        total = app.config["STORE"].balance(name)
        total = int(total) if float(total).is_integer() else total
        return {"customer": name, "balance": total, "reminder": f"{name} ji, ₹{total} बाकी हैं."}

    return app
