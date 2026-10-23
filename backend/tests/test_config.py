"""Settings used by hosted deployments."""

from app.core.config import Settings


def test_hosted_postgres_urls_get_the_async_driver():
    for url in ("postgres://u:p@host:5432/db", "postgresql://u:p@host:5432/db"):
        assert Settings(database_url=url).database_url == "postgresql+asyncpg://u:p@host:5432/db"
    keep = "postgresql+asyncpg://u:p@host/db"
    assert Settings(database_url=keep).database_url == keep


def test_cors_origins_from_json_env(monkeypatch):
    monkeypatch.setenv("DOCSCANNER_CORS_ORIGINS", '["https://manav252.github.io"]')
    assert Settings().cors_origins == ["https://manav252.github.io"]
