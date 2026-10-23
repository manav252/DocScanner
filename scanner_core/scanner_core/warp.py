"""Perspective correction: map the 4 page corners onto a flat rectangle."""

from __future__ import annotations

import cv2
import numpy as np

from .detect import order_corners


def output_size(corners: np.ndarray) -> tuple[int, int]:
    """Width/height of the flattened page: the longer of each pair of opposite edges."""
    tl, tr, br, bl = order_corners(corners)
    w = max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl))
    h = max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr))
    return max(1, int(round(w))), max(1, int(round(h)))


def warp_perspective(image: np.ndarray, corners: np.ndarray, max_side: int | None = None) -> np.ndarray:
    """Flatten the quad ``corners`` (any order) from ``image`` to a rectangle.

    ``max_side`` optionally caps the longest output side (keeps memory bounded on phones).
    """
    src = order_corners(corners)
    w, h = output_size(src)
    if max_side and max(w, h) > max_side:
        s = max_side / max(w, h)
        w, h = max(1, round(w * s)), max(1, round(h * s))
    dst = np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]])
    M = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(image, M, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
