"""DocScanner API: accounts, cloud sync of scanned documents, server-side scanning."""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker

from .api import auth, documents, process
from .core.config import Settings, get_settings
from .db import make_engine
from .services.storage import Storage


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    settings.check_production_safety()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = make_engine(settings.database_url)
        app.state.engine = engine
        app.state.sessionmaker = async_sessionmaker(engine, expire_on_commit=False)
        app.state.storage = Storage(settings)
        if settings.s3_create_bucket:
            await app.state.storage.ensure_bucket()
        yield
        await engine.dispose()

    app = FastAPI(
        title="DocScanner API",
        version="1.0.0",
        description="Accounts, offline-first sync of scanned documents (metadata in Postgres, images in S3), "
        "PDF export and server-side document detection.",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["X-Document-Found", "X-Document-Corners", "X-Image-Width", "X-Image-Height", "Content-Disposition"],
    )
    app.include_router(auth.router)
    app.include_router(documents.router)
    app.include_router(process.router)

    @app.get("/health", tags=["health"])
    async def health() -> dict:
        db_ok = True
        try:
            async with app.state.engine.connect() as conn:
                await conn.execute(text("select 1"))
        except Exception:  # noqa: BLE001
            db_ok = False
        s3_ok = await app.state.storage.ping()
        return {"status": "ok" if db_ok and s3_ok else "degraded", "database": db_ok, "storage": s3_ok}

    return app


app = create_app()
