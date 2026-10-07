"""Kirana ledger API (FastAPI)."""
from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import case, func, select, text
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import Entry
from .schemas import Balance, EntryIn, EntryOut, clean_name

app = FastAPI(title="Kirana Ledger API", version=settings.app_version)
Instrumentator(excluded_handlers=["/metrics", "/health", "/ready"]).instrument(app).expose(app)
LEDGER_ENTRIES = Counter("kirana_ledger_entries_total", "Ledger entries recorded", ["type"])


def require_api_key(x_api_key: str = Header(default="")):
    if settings.api_key and x_api_key != settings.api_key:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid API key")


def _money(value) -> float:
    return float(round(value or 0, 2))


def _reminder(name: str, total: float) -> str:
    amount = int(total) if float(total).is_integer() else total
    return f"{name} ji, ₹{amount} बाकी हैं."


@app.get("/health", tags=["ops"])
def health():
    """Liveness: the process is up (never touches the database)."""
    return {"status": "ok", "version": settings.app_version, "shop": settings.shop_name}


@app.get("/ready", tags=["ops"])
def ready(response: Response, db: Session = Depends(get_db)):
    """Readiness: the database answers."""
    try:
        db.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception as exc:  # noqa: BLE001 - any DB failure means not ready
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not ready", "error": type(exc).__name__}


@app.get("/api/info", tags=["ledger"])
def info():
    return {"shop": settings.shop_name, "version": settings.app_version}


@app.get("/api/entries", response_model=list[EntryOut], tags=["ledger"])
def list_entries(customer: str | None = None, db: Session = Depends(get_db)):
    query = select(Entry).order_by(Entry.id.desc())
    if customer:
        query = query.where(Entry.customer == clean_name(customer))
    return db.scalars(query).all()


@app.get("/api/entries/{entry_id}", response_model=EntryOut, tags=["ledger"])
def get_entry(entry_id: int, db: Session = Depends(get_db)):
    entry = db.get(Entry, entry_id)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "entry not found")
    return entry


@app.post("/api/entries", response_model=EntryOut, status_code=201, tags=["ledger"],
          dependencies=[Depends(require_api_key)])
def create_entry(data: EntryIn, db: Session = Depends(get_db)):
    entry = Entry(**data.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    LEDGER_ENTRIES.labels(entry.type).inc()
    return entry


@app.put("/api/entries/{entry_id}", response_model=EntryOut, tags=["ledger"],
         dependencies=[Depends(require_api_key)])
def update_entry(entry_id: int, data: EntryIn, db: Session = Depends(get_db)):
    entry = db.get(Entry, entry_id)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "entry not found")
    for field, value in data.model_dump().items():
        setattr(entry, field, value)
    db.commit()
    db.refresh(entry)
    return entry


@app.delete("/api/entries/{entry_id}", status_code=204, tags=["ledger"],
            dependencies=[Depends(require_api_key)])
def delete_entry(entry_id: int, db: Session = Depends(get_db)):
    entry = db.get(Entry, entry_id)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "entry not found")
    db.delete(entry)
    db.commit()
    return Response(status_code=204)


_signed = func.sum(case((Entry.type == "udhar", Entry.amount), (Entry.type == "payment", -Entry.amount), else_=0))


@app.get("/api/customers", response_model=list[Balance], tags=["ledger"])
def balances(db: Session = Depends(get_db)):
    """कौन कितना बाकी: every customer with money outstanding, biggest first."""
    rows = db.execute(select(Entry.customer, _signed.label("bal")).group_by(Entry.customer)).all()
    result = [Balance(customer=c, balance=_money(b), reminder=_reminder(c, _money(b)))
              for c, b in rows if _money(b) > 0]
    return sorted(result, key=lambda r: r.balance, reverse=True)


@app.get("/api/customers/{name}", response_model=Balance, tags=["ledger"])
def customer_balance(name: str, db: Session = Depends(get_db)):
    customer = clean_name(name)
    total = _money(db.scalar(select(_signed).where(Entry.customer == customer)))
    return Balance(customer=customer, balance=total, reminder=_reminder(customer, total))
