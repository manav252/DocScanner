"""Server-side scanning: a fallback for devices too slow to run OpenCV themselves."""
import json

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from starlette.concurrency import run_in_threadpool

from ..core.config import Settings
from ..core.security import current_user
from ..models import User
from ..schemas import FilterName, ProcessResult
from ..services import imaging
from .deps import read_upload_limited, settings, sniff

router = APIRouter(tags=["processing"])


def _json_list(raw: str | None, name: str, shape: tuple[int, ...]) -> list | None:
    if raw is None or raw == "":
        return None
    try:
        v = json.loads(raw)
        if len(shape) == 2:
            ok = len(v) == shape[0] and all(len(p) == shape[1] and all(isinstance(x, (int, float)) for x in p) for p in v)
        else:
            ok = len(v) == shape[0] and all(isinstance(x, (int, float)) for x in v)
        if not ok:
            raise ValueError
        return v
    except (ValueError, TypeError) as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"{name} must be a JSON array of shape {shape}") from e


@router.post(
    "/process",
    responses={
        200: {
            "content": {"image/jpeg": {}, "application/json": {"schema": ProcessResult.model_json_schema()}},
            "description": "JPEG of the processed page (corners in X-Document-Corners), or JSON when detect_only=true",
        }
    },
)
async def process_image(
    file: UploadFile = File(..., description="JPEG/PNG/WebP photo"),
    corners: str | None = Form(None, description="JSON [[x,y] x4]; detected automatically when omitted"),
    # Booleans default to false: browsers/FastAPI treat a missing form field as an unchecked box.
    flat: bool = Form(False, description="true: the image is already flat; skip detection and warping"),
    filter: FilterName = Form("magic_color"),
    rotate: int = Form(0, ge=0, le=3, description="Clockwise quarter turns"),
    crop: str | None = Form(None, description="JSON [left, top, width, height] in 0..1, applied after rotation"),
    detect_only: bool = Form(False, description="Only return the detected corners as JSON"),
    max_side: int = Form(3000, ge=100, le=8000),
    quality: int = Form(90, ge=30, le=100),
    _: User = Depends(current_user),
    cfg: Settings = Depends(settings),
):
    """Detect the page and return a flattened, enhanced image (the same OpenCV pipeline the app runs)."""
    data = await read_upload_limited(file, cfg.max_upload_bytes, cfg.max_upload_mb)
    if sniff(data) not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Upload a JPEG, PNG or WebP image")
    quad = _json_list(corners, "corners", (4, 2))
    crop_rect = _json_list(crop, "crop", (4,))
    if crop_rect is not None:
        l, t, w, h = crop_rect
        if not (0 <= l < 1 and 0 <= t < 1 and 0 < w <= 1.0001 - l and 0 < h <= 1.0001 - t):
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "crop must lie inside [0, 1]")
    try:
        r = await run_in_threadpool(
            imaging.process,
            data,
            corners=quad,
            warp=not flat,
            filter=filter,
            turns=rotate,
            crop_rect=crop_rect,
            max_side=max_side,
            detect_only=detect_only,
            quality=quality,
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e
    if detect_only:
        return ProcessResult(found=r.found, corners=r.corners, width=r.width, height=r.height)
    return Response(
        r.jpeg,
        media_type="image/jpeg",
        headers={
            "X-Document-Found": "true" if r.found else "false",
            "X-Document-Corners": json.dumps(r.corners),
            "X-Image-Width": str(r.width),
            "X-Image-Height": str(r.height),
        },
    )
