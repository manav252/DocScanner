"""One-call scan used by the backend /process endpoint."""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .detect import detect_document, order_corners
from .filters import Filter, apply_filter, rotate
from .warp import warp_perspective


@dataclass
class ScanResult:
    corners: np.ndarray  # TL, TR, BR, BL in source pixels
    found: bool
    image: np.ndarray  # flattened + filtered page


def decode_image(data: bytes) -> np.ndarray:
    """Decode JPEG/PNG/WebP bytes into BGR (honours EXIF orientation)."""
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("could not decode image")
    return img


def encode_image(image: np.ndarray, fmt: str = "jpg", quality: int = 90) -> bytes:
    params = [cv2.IMWRITE_JPEG_QUALITY, quality] if fmt in ("jpg", "jpeg") else []
    ok, buf = cv2.imencode(f".{fmt}", image, params)
    if not ok:
        raise ValueError(f"could not encode as {fmt}")
    return buf.tobytes()


def scan(
    image: np.ndarray,
    corners: np.ndarray | None = None,
    filter: Filter | str = Filter.MAGIC_COLOR,
    quarter_turns: int = 0,
    max_side: int = 3000,
) -> ScanResult:
    if corners is None:
        det = detect_document(image)
        corners, found = det.corners, det.found
    else:
        corners, found = order_corners(corners), True
    page = warp_perspective(image, corners, max_side=max_side)
    page = rotate(apply_filter(page, filter), quarter_turns)
    return ScanResult(corners, found, page)
