"""Kirana ledger API (FastAPI)."""
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Response, status
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import case, func, select, text
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import Entry
from .schemas import Balance, DayTotals, EntryIn, EntryOut, EntryType, Stats, clean_name

app = FastAPI(title="Kirana Ledger API", version=settings.app_version)
Instrumentator(excluded_handlers=["/metrics", "/health", "/ready"]).instrument(app).expose(app)
LEDGER_ENTRIES = Counter("kirana_ledger_entries_total", "Ledger entries recorded", ["type"])
IST = timezone(timedelta(hours=5, minutes=30))   # the shop's clock: "today" means today in India


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
def list_entries(customer: str | None = None, type: EntryType | None = None,
                 q: str | None = Query(default=None, max_length=80),
                 limit: int = Query(default=200, ge=1, le=1000), db: Session = Depends(get_db)):
    """Newest first. Filter by exact customer, by type, or search customer/note with `q`."""
    query = select(Entry).order_by(Entry.created_at.desc(), Entry.id.desc()).limit(limit)
    if customer:
        query = query.where(Entry.customer == clean_name(customer))
    if type:
        query = query.where(Entry.type == type)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(Entry.customer.ilike(like) | Entry.note.ilike(like))
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


def _ist_day(ts: datetime):
    if ts.tzinfo is None:                     # SQLite hands back naive UTC
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(IST).date()


@app.get("/api/stats", response_model=Stats, tags=["ledger"])
def stats(days: int = Query(default=7, ge=1, le=90), db: Session = Depends(get_db)):
    """Dashboard numbers: outstanding credit, today's totals and a per-day trend (IST)."""
    today = datetime.now(IST).date()
    first = today - timedelta(days=days - 1)
    since = datetime.combine(first, datetime.min.time(), IST)
    series = {first + timedelta(days=i): DayTotals(date=first + timedelta(days=i)) for i in range(days)}
    for ts, kind, amount in db.execute(select(Entry.created_at, Entry.type, Entry.amount)
                                       .where(Entry.created_at >= since)).all():
        day = series.get(_ist_day(ts))
        if day is not None:
            setattr(day, kind, _money(getattr(day, kind) + float(amount)))
            day.count += 1

    owed = [float(b) for _, b in db.execute(select(Entry.customer, _signed).group_by(Entry.customer)).all()]
    owed = [_money(b) for b in owed if _money(b) > 0]
    given = _money(db.scalar(select(func.sum(Entry.amount)).where(Entry.type == "udhar")))
    paid = _money(db.scalar(select(func.sum(Entry.amount)).where(Entry.type == "payment")))
    return Stats(
        outstanding=_money(sum(owed)),
        customers_with_dues=len(owed),
        customers_total=db.scalar(select(func.count(func.distinct(Entry.customer)))) or 0,
        entries_total=db.scalar(select(func.count(Entry.id))) or 0,
        collection_rate=round(paid / given * 100, 1) if given else 0.0,
        today=series[today],
        days=list(series.values()),
    )
