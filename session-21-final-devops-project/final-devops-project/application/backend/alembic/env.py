from alembic import context
from sqlalchemy import text

from app.config import settings
from app.db import Base, make_engine
from app import models  # noqa: F401  (register tables on Base.metadata)

target_metadata = Base.metadata


def run_migrations_online():
    engine = make_engine(settings.database_url)
    with engine.connect() as connection:
        if connection.dialect.name == "postgresql":
            # several Pods may start at once: only one runs migrations at a time
            connection.execute(text("SELECT pg_advisory_lock(727274)"))
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
        if connection.dialect.name == "postgresql":
            connection.execute(text("SELECT pg_advisory_unlock(727274)"))
            connection.commit()


run_migrations_online()
