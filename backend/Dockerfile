# Build context: the repository root (docscanner/), so scanner_core can be installed.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /srv

COPY backend/requirements.txt backend/requirements.txt
RUN pip install -r backend/requirements.txt

COPY scanner_core /srv/scanner_core
RUN pip install /srv/scanner_core

COPY backend /srv/backend
WORKDIR /srv/backend
RUN useradd --system --uid 10001 app && chown -R app /srv/backend
USER app

EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --retries=5 CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --workers ${WEB_CONCURRENCY:-2}"]
