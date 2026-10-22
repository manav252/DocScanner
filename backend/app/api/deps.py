from fastapi import HTTPException, Request, status

from ..core.config import Settings
from ..services.storage import Storage

MAGIC = {
    "image/jpeg": [b"\xff\xd8\xff"],
    "image/png": [b"\x89PNG\r\n\x1a\n"],
    "application/pdf": [b"%PDF-"],
}


def settings(request: Request) -> Settings:
    return request.app.state.settings


def storage(request: Request) -> Storage:
    return request.app.state.storage


def sniff(data: bytes) -> str | None:
    """Content type from magic bytes (never trust the client's header)."""
    for ctype, sigs in MAGIC.items():
        if any(data.startswith(s) for s in sigs):
            return ctype
    if len(data) > 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def too_large(limit_mb: int) -> HTTPException:
    return HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, f"File too large (max {limit_mb} MB)")


async def read_body_limited(request: Request, limit: int, limit_mb: int) -> bytes:
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > limit:
        raise too_large(limit_mb)
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > limit:
            raise too_large(limit_mb)
        chunks.append(chunk)
    return b"".join(chunks)


async def read_upload_limited(file, limit: int, limit_mb: int) -> bytes:
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise too_large(limit_mb)
    return data
