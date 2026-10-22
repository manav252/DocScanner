from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_SECRET = "dev-only-insecure-secret-change-me"


class Settings(BaseSettings):
    """All settings come from DOCSCANNER_* environment variables (or .env)."""

    model_config = SettingsConfigDict(env_prefix="DOCSCANNER_", env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str = "postgresql+asyncpg://docscanner:docscanner@localhost:5432/docscanner"

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

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    def check_production_safety(self) -> None:
        if self.environment == "production" and self.jwt_secret == DEV_SECRET:
            raise RuntimeError("Set DOCSCANNER_JWT_SECRET in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
