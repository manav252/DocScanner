"""Enhancement filters applied to a flattened page, plus rotate and crop."""
from __future__ import annotations

from enum import Enum

import cv2
import numpy as np


class Filter(str, Enum):
    ORIGINAL = "original"
    GRAYSCALE = "grayscale"
    BW = "bw"
    MAGIC_COLOR = "magic_color"


def _background(channel: np.ndarray) -> np.ndarray:
    """Estimate the paper/illumination level per pixel (text removed), at low res for speed."""
    h, w = channel.shape
    s = min(1.0, 400 / max(h, w))
    small = cv2.resize(channel, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
    # Small kernels follow hard shadow edges closely (big ones leave a grey band).
    k = max(3, (min(small.shape) // 40) | 1)
    bg = cv2.dilate(small, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))  # erase dark ink
    bg = cv2.medianBlur(bg, k * 2 + 1)
    bg = cv2.GaussianBlur(bg, (0, 0), k / 4)
    return cv2.resize(bg, (w, h), interpolation=cv2.INTER_LINEAR)


def remove_shadows(image: np.ndarray) -> np.ndarray:
    """Divide each channel by its estimated background so the paper becomes evenly white."""
    chans = cv2.split(image) if image.ndim == 3 else [image]
    out = []
    for c in chans:
        bg = _background(c).astype(np.float32)
        out.append(np.clip(c.astype(np.float32) / np.maximum(bg, 1) * 255, 0, 255).astype(np.uint8))
    return cv2.merge(out) if len(out) > 1 else out[0]


def grayscale(image: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image.copy()


def black_and_white(image: np.ndarray) -> np.ndarray:
    gray = remove_shadows(grayscale(image))
    block = max(15, (min(gray.shape) // 30) | 1)
    out = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, block, 15)
    # The outermost pixels often hold a sliver of desk/page edge: clear them.
    m = max(2, round(0.004 * min(out.shape)))
    out[:m, :] = out[-m:, :] = 255
    out[:, :m] = out[:, -m:] = 255
    return out


def magic_color(image: np.ndarray) -> np.ndarray:
    """Shadow removal + local contrast + a little saturation, like CamScanner's 'Magic Color'."""
    if image.ndim == 2:
        image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    flat = remove_shadows(image)
    lab = cv2.cvtColor(flat, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=1.5, tileGridSize=(8, 8)).apply(l)
    # push near-white paper to pure white and deepen ink
    l = cv2.LUT(l, np.clip((np.arange(256) - 20) * 255 / 215, 0, 255).astype(np.uint8))
    out = cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)
    hsv = cv2.cvtColor(out, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.25, 0, 255)
    return cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)


def apply_filter(image: np.ndarray, f: Filter | str) -> np.ndarray:
    f = Filter(f)
    if f is Filter.ORIGINAL:
        return image.copy()
    if f is Filter.GRAYSCALE:
        return grayscale(image)
    if f is Filter.BW:
        return black_and_white(image)
    return magic_color(image)


def rotate(image: np.ndarray, quarter_turns: int) -> np.ndarray:
    """Rotate clockwise by 90 degrees * quarter_turns."""
    k = quarter_turns % 4
    codes = {1: cv2.ROTATE_90_CLOCKWISE, 2: cv2.ROTATE_180, 3: cv2.ROTATE_90_COUNTERCLOCKWISE}
    return image.copy() if k == 0 else cv2.rotate(image, codes[k])


def crop(image: np.ndarray, x: float, y: float, w: float, h: float) -> np.ndarray:
    """Crop with a rectangle given in normalised [0, 1] coordinates."""
    if not (0 <= x < 1 and 0 <= y < 1 and 0 < w <= 1 - x + 1e-9 and 0 < h <= 1 - y + 1e-9):
        raise ValueError("crop rectangle must lie inside [0, 1]")
    H, W = image.shape[:2]
    x0, y0 = int(round(x * W)), int(round(y * H))
    x1, y1 = max(x0 + 1, int(round((x + w) * W))), max(y0 + 1, int(round((y + h) * H)))
    return image[y0:y1, x0:x1].copy()
