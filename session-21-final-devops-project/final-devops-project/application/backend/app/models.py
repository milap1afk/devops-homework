from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class Entry(Base):
    """One line in the shop's ledger: udhar (credit given), payment (credit paid back) or sale (cash)."""

    __tablename__ = "entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    customer: Mapped[str] = mapped_column(String(80), index=True)
    amount: Mapped[float] = mapped_column(Numeric(10, 2))
    type: Mapped[str] = mapped_column(String(10))
    note: Mapped[str] = mapped_column(String(200), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
