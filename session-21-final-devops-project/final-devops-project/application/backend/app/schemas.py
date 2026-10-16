import re
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

EntryType = Literal["udhar", "payment", "sale"]
_HONORIFIC = re.compile(r"^(shri|smt)\s+|\s*(bhai|ji|behen|bhaiya)$", re.IGNORECASE)


def clean_name(name: str) -> str:
    """'Shri Ramesh ji' / 'Rameshbhai' / 'ramesh bhai' -> 'Ramesh' (one customer, many spellings)."""
    name = re.sub(r"(?i)bhai$", "", name.strip())
    previous = None
    while previous != name:
        previous = name
        name = _HONORIFIC.sub("", name).strip()
    return name.title()


class EntryIn(BaseModel):
    customer: str = Field(min_length=1, max_length=80)
    amount: float = Field(gt=0, le=10_000_000)
    type: EntryType
    note: str = Field(default="", max_length=200)

    @field_validator("customer")
    @classmethod
    def normalise(cls, v: str) -> str:
        cleaned = clean_name(v)
        if not cleaned:
            raise ValueError("customer name is empty")
        return cleaned


class EntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    customer: str
    amount: float
    type: EntryType
    note: str
    created_at: datetime


class Balance(BaseModel):
    customer: str
    balance: float
    reminder: str


class DayTotals(BaseModel):
    date: date
    udhar: float = 0
    payment: float = 0
    sale: float = 0
    count: int = 0


class Stats(BaseModel):
    outstanding: float          # credit still owed to the shop
    customers_with_dues: int
    customers_total: int
    entries_total: int
    collection_rate: float      # % of all credit given that has been paid back
    today: DayTotals
    days: list[DayTotals]       # oldest first, one per day (IST)
