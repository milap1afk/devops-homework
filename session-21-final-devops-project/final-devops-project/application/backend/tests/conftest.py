import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app import main
from app.config import settings
from app.db import Base, get_db, make_engine


@pytest.fixture
def client(tmp_path):
    """Each test gets its own throwaway SQLite database - never the real PostgreSQL."""
    engine = make_engine(f"sqlite:///{tmp_path}/test.db")
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine, expire_on_commit=False)

    def override_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    main.app.dependency_overrides[get_db] = override_db
    settings.api_key = ""
    yield TestClient(main.app)
    main.app.dependency_overrides.clear()
