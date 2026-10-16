"""Demo data: a believable week in a kirana shop.  `python -m app.seed` (skips if the ledger is not empty)."""
import random
from datetime import datetime, timedelta

from sqlalchemy import func, select

from .db import SessionLocal
from .main import IST
from .models import Entry

CUSTOMERS = ["Ramesh", "Sunita", "Ravi", "Asha", "Meena", "Imran", "Lakshmi", "Gurpreet", "Joseph", "Kavita"]
NOTES = ["atta + daal", "monthly ration", "doodh, bread", "sugar 5 kg", "tel + masala", "chawal 10 kg",
         "biscuits for school", "soap, detergent", "", "", ""]


def demo_entries(now: datetime, seed: int = 21) -> list[Entry]:
    """~6 entries a day for a week. Payments only come from customers who owe, and never exceed what they owe."""
    rng = random.Random(seed)
    owed = dict.fromkeys(CUSTOMERS, 0)
    entries = []
    for days_ago in range(6, -1, -1):
        day = now - timedelta(days=days_ago)
        times = sorted(day.replace(hour=rng.randint(8, 20), minute=rng.randint(0, 59), second=0, microsecond=0)
                       for _ in range(rng.randint(5, 8)))
        for when in times:
            if when > now:
                when = now - timedelta(minutes=rng.randint(1, 30))
            kind = rng.choices(["udhar", "payment", "sale"], weights=[5, 3, 4])[0]
            debtors = [c for c, b in owed.items() if b > 0]
            if kind == "payment" and not debtors:
                kind = "udhar"
            if kind == "payment":
                customer = rng.choice(debtors)
                amount = min(owed[customer], rng.choice([100, 200, 300, 500]))
            else:
                customer = rng.choice(CUSTOMERS)
                amount = rng.choice([60, 80, 120, 150, 200, 250, 300, 450, 500, 750, 1200])
            if kind != "sale":
                owed[customer] += amount if kind == "udhar" else -amount
            entries.append(Entry(customer=customer, amount=amount, type=kind,
                                 note="" if kind == "payment" else rng.choice(NOTES), created_at=when))
    return entries


def main() -> None:
    with SessionLocal() as db:
        if db.scalar(select(func.count(Entry.id))):
            print("ledger already has entries - not seeding")
            return
        rows = demo_entries(datetime.now(IST))   # shop hours 8:00-20:00 India time
        db.add_all(rows)
        db.commit()
        print(f"seeded {len(rows)} demo entries")


if __name__ == "__main__":
    main()
