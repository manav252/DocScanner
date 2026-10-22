# DocScanner backend (FastAPI + Postgres + MinIO)

Accounts, cloud backup/sync of scanned documents, PDF export, PDF/photo upload,
and server-side scanning for slow devices. Document metadata lives in Postgres;
page images live in S3-compatible storage (MinIO locally).

## Run

```bash
cp .env.example .env            # change DOCSCANNER_JWT_SECRET for anything non-local
docker compose up -d --build    # api :8000, postgres :5432, minio :9000 (console :9001)
curl localhost:8000/health
python scripts/seed_demo.py     # optional: demo@example.com + a sample PDF
```

- OpenAPI docs: http://localhost:8000/docs (ReDoc at `/redoc`)
- Migrations run automatically on start (`alembic upgrade head`).
- MinIO: the official images were discontinued in 2025, so Compose pins
  `bitnamilegacy/minio:2025.7.23` (frozen, no further updates). Any S3-compatible
  store works: set `DOCSCANNER_S3_ENDPOINT` / keys / bucket.

### Settings (`DOCSCANNER_*` environment variables)

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://docscanner:docscanner@localhost:5432/docscanner` | |
| `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET` | MinIO on localhost | bucket created on start |
| `JWT_SECRET` | dev value | **required** when `ENVIRONMENT=production` |
| `ACCESS_TOKEN_MINUTES` / `REFRESH_TOKEN_DAYS` | 60 / 30 | |
| `MAX_UPLOAD_MB` | 20 | per file |
| `MAX_PAGES_PER_DOCUMENT` / `MAX_FILES_PER_UPLOAD` | 500 / 50 | |
| `CORS_ORIGINS` | `["http://localhost:8090", ...]` | add the web app's origin |

## API

| | |
|---|---|
| `POST /auth/register`, `POST /auth/login` | email + password (Argon2id) → access + refresh JWT |
| `POST /auth/refresh`, `GET /auth/me` | |
| `GET /documents?since=<cursor>&limit=` | list; with `since`, every change after the cursor incl. deletions |
| `GET /documents/{id}` | |
| `PUT /documents/{id}` | create/update metadata; `base_version` must match or **409** with the server copy |
| `DELETE /documents/{id}?base_version=` | tombstone (synced to other devices), images deleted |
| `PUT/GET /documents/{id}/pages/{page_id}/files/{source\|render\|thumb}` | page images (raw JPEG/PNG/WebP body) |
| `GET /documents/{id}/pdf` | PDF built from the rendered pages |
| `POST /documents/upload` | multipart PDFs/photos → new document (PDF pages rasterised, photos auto-cropped + Magic Color) |
| `POST /process` | photo → detected corners (`detect_only=true`) or the flattened, filtered page as JPEG |

Validation: pydantic schemas (ids, corners, crop rectangle, filters, page limits),
uploads checked by magic bytes (not the client's content type), size limits (413),
per-user isolation (every query and S3 key is scoped to the user).

### Sync model

The app is offline-first: the device library is the source of truth for the UI.
When signed in, the app pushes local changes (page files first, then metadata
with `base_version`) and pulls `GET /documents?since=cursor`. A 409 means another
device changed the document; the edit with the newer `updated_at` wins. Deletions
are tombstones so they reach every device.

## Tests

Against real Postgres + MinIO (a separate `docscanner_test` database and bucket):

```bash
docker compose up -d db minio
python -m venv .venv && .venv/bin/pip install -r requirements-dev.txt -e ../scanner_core
.venv/bin/python -m pytest -q
```

The app's end-to-end sync test runs two simulated devices against the live API:

```bash
cd ../app && DOCSCANNER_E2E_API=http://localhost:8000 tool/host_test.sh test/integration
```

## Production notes

- Put the API behind HTTPS (phones and browsers need it outside localhost); set
  `DOCSCANNER_ENVIRONMENT=production` and a long random `DOCSCANNER_JWT_SECRET`.
- Refresh tokens are stateless JWTs (no server-side revocation list yet).
- No rate limiting yet on `/auth/*` and `/process`; add it at the proxy.
