from functools import lru_cache

from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_SECRET = "dev-only-insecure-secret-change-me"


class Settings(BaseSettings):
    """All settings come from DOCSCANNER_* environment variables (or .env)."""

    model_config = SettingsConfigDict(env_prefix="DOCSCANNER_", env_file=".env", extra="ignore")

    environment: str = "development"
    # DOCSCANNER_DATABASE_URL, or plain DATABASE_URL as Neon/Render/Railway name it.
    database_url: str = Field(
        "postgresql+asyncpg://docscanner:docscanner@localhost:5432/docscanner",
        validation_alias=AliasChoices("DOCSCANNER_DATABASE_URL", "DATABASE_URL"),
    )

    s3_endpoint: str = "http://localhost:9000"
    s3_access_key: str = "docscanner"
    s3_secret_key: str = "docscanner-secret"
    s3_bucket: str = "docscanner"
    s3_region: str = "us-east-1"
    s3_create_bucket: bool = True

    jwt_secret: str = DEV_SECRET
    access_token_minutes: int = 60
    refresh_token_days: int = 30

    max_upload_mb: int = Field(20, ge=1, le=200)
    max_pages_per_document: int = Field(500, ge=1)
    max_files_per_upload: int = Field(50, ge=1)
    cors_origins: list[str] = ["http://localhost:8090", "http://127.0.0.1:8090", "http://localhost:8080"]

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        # Hosting providers (Render, Railway, Heroku) give postgres:// URLs; we need the asyncpg driver.
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                v = "postgresql+asyncpg://" + v[len(prefix) :]
        # Neon adds ?sslmode=require&channel_binding=require (libpq options); asyncpg
        # takes ssl=require instead and does not know channel_binding.
        parts = urlsplit(v)
        query = []
        for k, val in parse_qsl(parts.query):
            if k == "sslmode":
                query.append(("ssl", val))
            elif k != "channel_binding":
                query.append((k, val))
        return urlunsplit(parts._replace(query=urlencode(query)))

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    def check_production_safety(self) -> None:
        if self.environment == "production" and self.jwt_secret == DEV_SECRET:
            raise RuntimeError("Set DOCSCANNER_JWT_SECRET in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
