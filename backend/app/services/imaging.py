"""Server-side image work, built on scanner_core (the same pipeline the app runs)."""

from __future__ import annotations

import io
from dataclasses import dataclass

import cv2
import img2pdf
import numpy as np
import pypdfium2 as pdfium

from scanner_core import (
    Filter,
    apply_filter,
    crop,
    decode_image,
    detect_document,
    encode_image,
    order_corners,
    rotate,
    warp_perspective,
)

THUMB_SIDE = 360
A4_WIDTH_PT = img2pdf.mm_to_pt(210)


@dataclass
class ProcessedImage:
    found: bool
    corners: list[list[float]]
    width: int
    height: int
    jpeg: bytes | None = None


def _downscale(img: np.ndarray, max_side: int | None) -> np.ndarray:
    if not max_side or max(img.shape[:2]) <= max_side:
        return img
    s = max_side / max(img.shape[:2])
    return cv2.resize(img, (round(img.shape[1] * s), round(img.shape[0] * s)), interpolation=cv2.INTER_AREA)


def process(
    data: bytes,
    *,
    corners: list[list[float]] | None = None,
    warp: bool = True,
    filter: str = "magic_color",
    turns: int = 0,
    crop_rect: list[float] | None = None,
    max_side: int | None = 3000,
    detect_only: bool = False,
    quality: int = 90,
) -> ProcessedImage:
    """detect (unless corners given) -> warp -> filter -> rotate -> crop, like the app's engine."""
    img = decode_image(data)
    h, w = img.shape[:2]
    if corners is not None:
        quad, found = order_corners(np.float32(corners)), True
    elif warp or detect_only:
        det = detect_document(img)
        quad, found = det.corners, det.found
    else:
        quad, found = np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]]), False
    result = ProcessedImage(found, [[round(float(x), 2), round(float(y), 2)] for x, y in quad], w, h)
    if detect_only:
        return result
    page = warp_perspective(img, quad, max_side=max_side) if warp else _downscale(img, max_side)
    page = rotate(apply_filter(page, Filter(filter)), turns)
    if crop_rect is not None and crop_rect != [0, 0, 1, 1]:
        page = crop(page, *crop_rect)
    result.jpeg = encode_image(page, "jpg", quality)
    result.height, result.width = page.shape[:2]
    return result


def thumbnail(jpeg_or_png: bytes) -> bytes:
    return encode_image(_downscale(decode_image(jpeg_or_png), THUMB_SIDE), "jpg", 80)


def image_size(data: bytes) -> tuple[int, int]:
    img = decode_image(data)
    return img.shape[1], img.shape[0]


def rasterize_pdf(data: bytes, dpi: int = 150, max_pages: int = 500) -> list[bytes]:
    """Each PDF page as a JPEG."""
    pdf = pdfium.PdfDocument(data)
    try:
        if len(pdf) > max_pages:
            raise ValueError(f"PDF has {len(pdf)} pages (max {max_pages})")
        out = []
        for page in pdf:
            pil = page.render(scale=dpi / 72).to_pil().convert("RGB")
            buf = io.BytesIO()
            pil.save(buf, format="JPEG", quality=88)
            out.append(buf.getvalue())
        return out
    finally:
        pdf.close()


def build_pdf(jpegs: list[bytes], title: str) -> bytes:
    """PDF with one image per page, A4 width, page height following the image (lossless JPEG embedding)."""
    layout = img2pdf.get_layout_fun((A4_WIDTH_PT, None))
    return img2pdf.convert(jpegs, layout_fun=layout, title=title, producer="DocScanner")
