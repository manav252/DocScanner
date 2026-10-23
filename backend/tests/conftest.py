"""Tests run against real Postgres + MinIO (docker compose up -d db minio).

A fresh database `docscanner_test` is created and migrated with Alembic for
each session, and a separate bucket `docscanner-test` is emptied.
"""

import asyncio
import json
import os
import uuid
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import Settings
from app.main import create_app
from app.services.storage import Storage

BACKEND = Path(__file__).resolve().parents[1]
FIXTURES = BACKEND.parent / "shared" / "test_fixtures"
PG = os.environ.get("TEST_PG", "docscanner:docscanner@localhost:5432")
TEST_DB = "docscanner_test"


@pytest.fixture(scope="session")
def settings() -> Settings:
    s = Settings(
        database_url=f"postgresql+asyncpg://{PG}/{TEST_DB}",
        s3_endpoint=os.environ.get("TEST_S3", "http://localhost:9000"),
        s3_bucket="docscanner-test",
        jwt_secret="test-secret-that-is-long-enough-for-hs256",
        max_upload_mb=2,
        max_pages_per_document=20,
        max_files_per_upload=5,
    )

    async def recreate() -> None:
        engine = create_async_engine(f"postgresql+asyncpg://{PG}/postgres", isolation_level="AUTOCOMMIT")
        async with engine.connect() as conn:
            await conn.execute(text(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)"))
            await conn.execute(text(f"CREATE DATABASE {TEST_DB}"))
        await engine.dispose()
        storage = Storage(s)
        await storage.ensure_bucket()
        await storage.delete_prefix("")

    asyncio.run(recreate())
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "alembic"))
    cfg.attributes["database_url"] = s.database_url
    command.upgrade(cfg, "head")
    return s


@pytest.fixture
async def client(settings):
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            yield c


async def register(client: AsyncClient, email: str | None = None, password: str = "correct horse") -> dict:
    email = email or f"user-{uuid.uuid4().hex[:10]}@example.com"
    r = await client.post("/auth/register", json={"email": email, "password": password})
    assert r.status_code == 201, r.text
    body = r.json()
    return {
        "email": email,
        "password": password,
        "headers": {"Authorization": f"Bearer {body['access_token']}"},
        **body,
    }


@pytest.fixture
async def user(client):
    return await register(client)


@pytest.fixture(scope="session")
def photo() -> bytes:
    return (FIXTURES / "tilted_paper.jpg").read_bytes()


@pytest.fixture(scope="session")
def expected() -> dict:
    return json.loads((FIXTURES / "expected_corners.json").read_text())


@pytest.fixture(scope="session")
def small_jpeg() -> bytes:
    import cv2
    import numpy as np

    ok, buf = cv2.imencode(".jpg", np.full((40, 30, 3), 200, np.uint8))
    return buf.tobytes()
