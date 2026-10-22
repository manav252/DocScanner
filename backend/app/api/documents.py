"""Documents (metadata in Postgres) and their page images (S3).

Sync protocol used by the app:
  1. upload page files:  PUT /documents/{id}/pages/{page_id}/files/{kind}
  2. upsert metadata:    PUT /documents/{id}  {..., base_version}
       -> 409 + the server copy if base_version is stale (someone else changed it)
  3. pull changes:       GET /documents?since=<cursor>  (includes tombstones)
  4. delete:             DELETE /documents/{id}?base_version=N  (leaves a tombstone)
"""
import uuid
from datetime import UTC, datetime
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Form, HTTPException, Path, Query, Request, Response, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from ..core.config import Settings
from ..core.security import current_user
from ..db import get_session
from ..models import Document, User, change_seq
from ..schemas import Conflict, DocumentIn, DocumentList, DocumentOut, FileKind, Page
from ..services import imaging
from ..services.storage import Storage, doc_prefix, page_key
from .deps import read_body_limited, read_upload_limited, settings, sniff, storage

router = APIRouter(prefix="/documents", tags=["documents"])

DocId = Path(pattern=r"^[A-Za-z0-9_-]{1,64}$")
FILE_KINDS = ("source", "render", "thumb")


def to_out(d: Document) -> DocumentOut:
    return DocumentOut(
        id=d.client_id,
        title=d.title,
        created_at=d.created_at,
        updated_at=d.updated_at,
        version=d.version,
        change_seq=d.change_seq,
        deleted=d.deleted,
        pages=[Page.model_validate(p) for p in d.pages],
    )


async def _find(session: AsyncSession, user: User, doc_id: str, *, lock: bool = False) -> Document | None:
    q = select(Document).where(Document.owner_id == user.id, Document.client_id == doc_id)
    if lock:
        q = q.with_for_update()
    return (await session.execute(q)).scalar_one_or_none()


def _conflict(doc: Document) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content=Conflict(detail="The document changed on the server", document=to_out(doc)).model_dump(mode="json"),
    )


@router.get("", response_model=DocumentList)
async def list_documents(
    since: int | None = Query(None, ge=0, description="Cursor from a previous call; returns changes after it, including deletions"),
    limit: int = Query(200, ge=1, le=500),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> DocumentList:
    q = select(Document).where(Document.owner_id == user.id)
    q = q.where(Document.deleted.is_(False)) if since is None else q.where(Document.change_seq > since)
    rows = list((await session.execute(q.order_by(Document.change_seq).limit(limit + 1))).scalars())
    has_more = len(rows) > limit
    rows = rows[:limit]
    if rows and has_more:
        cursor = rows[-1].change_seq
    else:
        # Everything up to the latest change (tombstones included) has been seen.
        latest = await session.scalar(select(func.max(Document.change_seq)).where(Document.owner_id == user.id))
        cursor = max(latest or 0, since or 0)
    return DocumentList(documents=[to_out(d) for d in rows], cursor=cursor, has_more=has_more)


@router.get("/{doc_id}", response_model=DocumentOut)
async def get_document(
    doc_id: str = DocId, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> DocumentOut:
    doc = await _find(session, user, doc_id)
    if doc is None or doc.deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Document not found")
    return to_out(doc)


@router.put(
    "/{doc_id}",
    response_model=DocumentOut,
    responses={409: {"model": Conflict, "description": "base_version is stale; the body holds the server copy"}},
)
async def put_document(
    body: DocumentIn,
    doc_id: str = DocId,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
    store: Storage = Depends(storage),
    cfg: Settings = Depends(settings),
):
    if len(body.pages) > cfg.max_pages_per_document:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Too many pages (max {cfg.max_pages_per_document})")
    doc = await _find(session, user, doc_id, lock=True)
    if doc is not None and body.base_version != doc.version:
        return _conflict(doc)

    # Every page must have its images uploaded first, so other devices can always download them.
    present = await store.keys(doc_prefix(str(user.id), doc_id))
    missing = [
        f"{p.id}/{k}" for p in body.pages for k in FILE_KINDS if page_key(str(user.id), doc_id, p.id, k) not in present
    ]
    if missing:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, {"message": "Upload page files first", "missing": missing}
        )

    pages = [p.model_dump(mode="json") for p in body.pages]
    if doc is None:
        doc = Document(
            owner_id=user.id,
            client_id=doc_id,
            title=body.title,
            created_at=body.created_at,
            updated_at=body.updated_at,
            pages=pages,
            version=1,
        )
        session.add(doc)
        stale_keys: list[str] = []
    else:
        keep = {p.id for p in body.pages}
        stale_keys = sorted(
            k for k in present if k.split("/pages/")[1].split("/")[0] not in keep
        )
        doc.title, doc.updated_at, doc.pages = body.title, body.updated_at, pages
        doc.deleted = False
        doc.version += 1
        doc.change_seq = change_seq.next_value()
    try:
        await session.commit()
    except IntegrityError:
        # Created concurrently by another request.
        await session.rollback()
        current = await _find(session, user, doc_id)
        if current is None:
            raise
        return _conflict(current)
    await session.refresh(doc)
    if stale_keys:
        await store.delete_keys(stale_keys)
    return to_out(doc)


@router.delete("/{doc_id}", status_code=status.HTTP_204_NO_CONTENT, responses={409: {"model": Conflict}})
async def delete_document(
    doc_id: str = DocId,
    base_version: int | None = Query(None, ge=0, description="If given, only delete when the server is at this version"),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
    store: Storage = Depends(storage),
):
    doc = await _find(session, user, doc_id, lock=True)
    if doc is None or doc.deleted:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if base_version is not None and base_version != doc.version:
        return _conflict(doc)
    doc.deleted, doc.pages = True, []
    doc.version += 1
    doc.updated_at = datetime.now(UTC)
    doc.change_seq = change_seq.next_value()
    await session.commit()
    await store.delete_prefix(doc_prefix(str(user.id), doc_id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/{doc_id}/pages/{page_id}/files/{kind}", status_code=status.HTTP_204_NO_CONTENT)
async def put_page_file(
    request: Request,
    kind: FileKind,
    doc_id: str = DocId,
    page_id: str = Path(pattern=r"^[A-Za-z0-9_-]{1,64}$"),
    user: User = Depends(current_user),
    store: Storage = Depends(storage),
    cfg: Settings = Depends(settings),
):
    """Upload a page image (raw JPEG/PNG/WebP body). Upload before PUT /documents/{id}."""
    data = await read_body_limited(request, cfg.max_upload_bytes, cfg.max_upload_mb)
    ctype = sniff(data)
    if ctype not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Page files must be JPEG, PNG or WebP images")
    await store.put(page_key(str(user.id), doc_id, page_id, kind), data, ctype)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{doc_id}/pages/{page_id}/files/{kind}", response_class=Response)
async def get_page_file(
    kind: FileKind,
    doc_id: str = DocId,
    page_id: str = Path(pattern=r"^[A-Za-z0-9_-]{1,64}$"),
    user: User = Depends(current_user),
    store: Storage = Depends(storage),
):
    obj = await store.get(page_key(str(user.id), doc_id, page_id, kind))
    if obj is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    data, ctype = obj
    return Response(data, media_type=ctype, headers={"Cache-Control": "private, max-age=60"})


@router.get("/{doc_id}/pdf", response_class=Response, responses={200: {"content": {"application/pdf": {}}}})
async def download_pdf(
    doc_id: str = DocId,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
    store: Storage = Depends(storage),
):
    doc = await _find(session, user, doc_id)
    if doc is None or doc.deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Document not found")
    if not doc.pages:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Document has no pages")
    images = []
    for p in doc.pages:
        obj = await store.get(page_key(str(user.id), doc_id, p["id"], "render"))
        if obj is None:
            raise HTTPException(status.HTTP_409_CONFLICT, f"Page {p['id']} has no image yet")
        images.append(obj[0])
    pdf = await run_in_threadpool(imaging.build_pdf, images, doc.title)
    filename = quote(f"{doc.title}.pdf")
    return Response(pdf, media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename*=UTF-8''{filename}"})


@router.post("/upload", response_model=DocumentOut, status_code=status.HTTP_201_CREATED)
async def upload_files(
    files: list[UploadFile] = File(..., description="PDFs and/or images; every PDF page becomes a page"),
    title: str | None = Form(None, max_length=200),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
    store: Storage = Depends(storage),
    cfg: Settings = Depends(settings),
) -> DocumentOut:
    """Create a document from uploaded PDFs/photos (photos get the page detected and Magic Color)."""
    if len(files) > cfg.max_files_per_upload:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Too many files (max {cfg.max_files_per_upload})")
    doc_id = uuid.uuid4().hex
    owner = str(user.id)
    pages: list[dict] = []
    for f in files:
        data = await read_upload_limited(f, cfg.max_upload_bytes, cfg.max_upload_mb)
        ctype = sniff(data)
        if ctype == "application/pdf":
            try:
                rendered = await run_in_threadpool(
                    imaging.rasterize_pdf, data, 150, cfg.max_pages_per_document - len(pages)
                )
            except Exception as e:  # noqa: BLE001 - pdfium raises various errors for broken files
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Could not read {f.filename}: {e}") from e
            items = [(img, None) for img in rendered]
        elif ctype in ("image/jpeg", "image/png", "image/webp"):
            items = [(data, "magic_color")]
        else:
            raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, f"{f.filename}: only PDF, JPEG, PNG or WebP")
        for source, filt in items:
            if len(pages) >= cfg.max_pages_per_document:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Too many pages")
            page_id = uuid.uuid4().hex
            if filt is None:  # PDF page: already flat
                w, h = await run_in_threadpool(imaging.image_size, source)
                corners, render, edits = [[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], source, {"filter": "original"}
            else:
                try:
                    det = await run_in_threadpool(imaging.process, source, detect_only=True)
                except ValueError as e:
                    raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"{f.filename}: {e}") from e
                w, h, corners = det.width, det.height, det.corners
                edits = {"filter": filt if det.found else "original"}
                out = await run_in_threadpool(
                    imaging.process, source, corners=corners, filter=edits["filter"], max_side=3200
                )
                render = out.jpeg
            thumb = await run_in_threadpool(imaging.thumbnail, render)
            rw, rh = await run_in_threadpool(imaging.image_size, render)
            for kind, blob in (("source", source), ("render", render), ("thumb", thumb)):
                await store.put(page_key(owner, doc_id, page_id, kind), blob, sniff(blob) or "image/jpeg")
            pages.append(
                Page(
                    id=page_id,
                    source_width=w,
                    source_height=h,
                    corners=corners,
                    edits=edits,
                    revision=1,
                    render_width=rw,
                    render_height=rh,
                ).model_dump(mode="json")
            )
    if not pages:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Nothing to import")
    now = datetime.now(UTC)
    first = files[0].filename or "Upload"
    doc = Document(
        owner_id=user.id,
        client_id=doc_id,
        title=title or (first.rsplit(".", 1)[0] if len(files) == 1 else f"Upload {now:%Y-%m-%d %H:%M}"),
        created_at=now,
        updated_at=now,
        pages=pages,
        version=1,
    )
    session.add(doc)
    await session.commit()
    await session.refresh(doc)
    return to_out(doc)
