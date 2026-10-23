"""Document edge detection.

Pipeline (kept identical across the Python, Dart and web implementations):
    downscale -> grayscale -> blur -> Canny -> dilate -> contours
    -> largest convex 4-point polygon (approxPolyDP) -> order TL, TR, BR, BL
    -> refine each side: strongest-gradient search + robust line fit
If nothing qualifies, a second pass runs on a contrast-equalised (CLAHE) image
to catch low-contrast pages. If that also fails the full image bounds are
returned with ``found=False``.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

# Tunables. Mirror any change in app/lib/imaging/detector_params.dart.
MAX_DIM = 500  # longest side of the working image
MIN_AREA_RATIO = 0.08  # quad must cover at least 8% of the frame
MIN_FILL_RATIO = 0.85  # contour area / quad area: rejects hulls of scattered clutter
MAX_EDGE_DEVIATION = 0.025  # 90th pct distance of contour to quad edges, as fraction of quad diagonal
MIN_ANGLE, MAX_ANGLE = 35.0, 145.0  # interior angle sanity range (degrees)
APPROX_EPSILONS = (0.02, 0.03, 0.04)


@dataclass(frozen=True)
class Detection:
    corners: np.ndarray  # float32 (4, 2) in source-image pixels, ordered TL, TR, BR, BL
    found: bool
    score: float = 0.0  # area ratio of the detected quad (0 when not found)


def order_corners(pts: np.ndarray) -> np.ndarray:
    """Order 4 points as TL, TR, BR, BL (clockwise on screen, y pointing down)."""
    pts = np.asarray(pts, np.float32).reshape(4, 2)
    c = pts.mean(axis=0)
    ang = np.arctan2(pts[:, 1] - c[1], pts[:, 0] - c[0])
    pts = pts[np.argsort(ang)]  # clockwise on screen, starting anywhere
    start = int(np.argmin(pts.sum(axis=1)))  # top-left = smallest x + y
    return np.roll(pts, -start, axis=0)


def full_bounds(w: int, h: int) -> np.ndarray:
    return np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]])


def auto_canny(gray: np.ndarray, sigma: float = 0.33) -> np.ndarray:
    v = float(np.median(gray))
    lo, hi = int(max(0, (1 - sigma) * v)), int(min(255, (1 + sigma) * v))
    # Keep a sensible floor so flat images do not explode into noise edges.
    return cv2.Canny(gray, max(lo, 10), max(hi, 30))


def _interior_angles(q: np.ndarray) -> np.ndarray:
    out = []
    for i in range(4):
        a, b, c = q[i - 1], q[i], q[(i + 1) % 4]
        v1, v2 = a - b, c - b
        cos = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
        out.append(np.degrees(np.arccos(np.clip(cos, -1, 1))))
    return np.array(out)


def _edge_deviation(contour: np.ndarray, quad: np.ndarray) -> float:
    """90th percentile distance from contour points to the nearest quad edge."""
    p = contour.reshape(-1, 2).astype(np.float32)
    d = np.full(len(p), np.inf, np.float32)
    for i in range(4):
        a, b = quad[i], quad[(i + 1) % 4]
        ab = b - a
        t = np.clip(((p - a) @ ab) / (ab @ ab + 1e-6), 0, 1)
        d = np.minimum(d, np.linalg.norm(p - (a + t[:, None] * ab), axis=1))
    return float(np.percentile(d, 90))


def _line_intersection(p1, p2, p3, p4):
    d = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0])
    if abs(d) < 1e-6:
        return None
    a = p1[0] * p2[1] - p1[1] * p2[0]
    b = p3[0] * p4[1] - p3[1] * p4[0]
    return np.float32(
        [(a * (p3[0] - p4[0]) - (p1[0] - p2[0]) * b) / d, (a * (p3[1] - p4[1]) - (p1[1] - p2[1]) * b) / d]
    )


def _quad_from_long_sides(poly: np.ndarray) -> np.ndarray | None:
    """Recover a quad from a 5-8 vertex polygon whose corner(s) were clipped
    (e.g. by a pen or finger lying across the page): keep the 4 longest sides
    and intersect neighbouring ones."""
    p = poly.reshape(-1, 2).astype(np.float32)
    n = len(p)
    if not 5 <= n <= 8:
        return None
    lengths = [np.linalg.norm(p[(i + 1) % n] - p[i]) for i in range(n)]
    keep = sorted(sorted(range(n), key=lambda i: -lengths[i])[:4])
    pts = []
    for k in range(4):
        i, j = keep[k], keep[(k + 1) % 4]
        x = _line_intersection(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n])
        if x is None:
            return None
        pts.append(x)
    return np.array(pts, np.float32)


def _best_quad(edges: np.ndarray) -> tuple[np.ndarray, float] | None:
    h, w = edges.shape
    img_area = float(w * h)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:12]
    best, best_area = None, 0.0
    for c in contours:
        c_area = cv2.contourArea(c)
        if c_area < MIN_AREA_RATIO * img_area * MIN_FILL_RATIO:
            break  # sorted: nothing further can qualify
        peri = cv2.arcLength(c, True)
        candidates = []
        for eps in APPROX_EPSILONS:
            approx = cv2.approxPolyDP(c, eps * peri, True)
            if len(approx) == 4 and cv2.isContourConvex(approx):
                candidates.append(approx.reshape(4, 2).astype(np.float32))
                break
        clipped = _quad_from_long_sides(cv2.approxPolyDP(c, APPROX_EPSILONS[0] * peri, True))
        if clipped is not None:
            candidates.append(clipped)
        for q in candidates:
            q = _validate(c, c_area, q, img_area)
            if q is not None and cv2.contourArea(q) > best_area:
                best, best_area = q, cv2.contourArea(q)
    return None if best is None else (best, best_area / img_area)


def _validate(c, c_area, q, img_area):
    """Return the ordered quad if it passes every sanity check, else None."""
    q = order_corners(q)
    if not cv2.isContourConvex(q.reshape(-1, 1, 2)):
        return None
    q_area = cv2.contourArea(q)
    if q_area < MIN_AREA_RATIO * img_area or c_area / q_area < MIN_FILL_RATIO:
        return None
    ang = _interior_angles(q)
    if ang.min() < MIN_ANGLE or ang.max() > MAX_ANGLE:
        return None
    diag = float(np.linalg.norm(q[2] - q[0]))
    if _edge_deviation(c, q) > MAX_EDGE_DEVIATION * diag:
        return None
    return q


def refine_corners(quad: np.ndarray, gray: np.ndarray, bands=(10, 5, 3), min_grad: float = 20.0) -> np.ndarray:
    """Sharpen a rough quad to sub-pixel accuracy.

    For each side, sample points along it (skipping 10% at each end), search
    along the side's normal within +-band px for the strongest gradient across
    the side, and robustly fit a line (Huber) through those peaks. Neighbouring
    lines are intersected to give the new corners. Taking the *strongest* edge
    makes it ignore weaker parallel structure (wood grain, shadows, text). A
    side with too few peaks keeps its current line; corners that would jump
    further than 3*band are kept as they were.
    """
    g = cv2.GaussianBlur(gray, (5, 5), 0).astype(np.float32)
    gx, gy = cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3), cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3)
    h, w = g.shape
    q = quad.astype(np.float32).copy()
    for band in bands:
        lines = []
        offs = np.arange(-band, band + 1, dtype=np.float32)
        for i in range(4):
            a, b = q[i], q[(i + 1) % 4]
            ab = b - a
            length = float(np.linalg.norm(ab))
            n = np.float32([-ab[1], ab[0]]) / (length + 1e-6)
            ts = np.linspace(0.1, 0.9, max(12, int(length / 3)), dtype=np.float32)
            base = a + ts[:, None] * ab  # (S, 2)
            cand = base[:, None, :] + offs[None, :, None] * n  # (S, K, 2)
            xi = np.clip(np.rint(cand[..., 0]).astype(int), 0, w - 1)
            yi = np.clip(np.rint(cand[..., 1]).astype(int), 0, h - 1)
            resp = np.abs(gx[yi, xi] * n[0] + gy[yi, xi] * n[1])  # gradient across the side
            k = resp.argmax(axis=1)
            ok = (resp[np.arange(len(k)), k] > min_grad) & (k > 0) & (k < len(offs) - 1)
            peaks = cand[np.arange(len(k)), k][ok]
            if len(peaks) >= 0.4 * len(ts):
                vx, vy, x0, y0 = cv2.fitLine(peaks, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
                lines.append((np.float32([x0, y0]), np.float32([x0 + vx, y0 + vy])))
            else:
                lines.append((a, b))
        new = []
        for i in range(4):
            x = _line_intersection(*lines[i - 1], *lines[i])
            new.append(q[i] if x is None or np.linalg.norm(x - q[i]) > 3 * band else x)
        q = np.array(new, np.float32)
    return q


def edge_map(gray_small: np.ndarray, equalize: bool = False) -> np.ndarray:
    g = gray_small
    if equalize:
        g = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(g)
    g = cv2.GaussianBlur(g, (5, 5), 0)
    # Pass 2 uses fixed low thresholds: median-based thresholds are far too
    # high for a white page on a white table (median ~220).
    e = cv2.Canny(g, 12, 36) if equalize else auto_canny(g)
    return cv2.dilate(e, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)


def detect_document(image: np.ndarray, max_dim: int = MAX_DIM) -> Detection:
    """Detect the page in a BGR or grayscale image. Corners are in source pixels."""
    if image is None or image.size == 0:
        raise ValueError("empty image")
    h, w = image.shape[:2]
    scale = min(1.0, max_dim / max(h, w))
    small = (
        cv2.resize(image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA) if scale < 1 else image
    )
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY) if small.ndim == 3 else small
    # Pad by a few pixels so a page touching the border still forms a closed contour.
    pad = 4
    gray = cv2.copyMakeBorder(gray, pad, pad, pad, pad, cv2.BORDER_REPLICATE)
    for equalize in (False, True):
        res = _best_quad(edge_map(gray, equalize))
        if res is not None:
            q, ratio = res
            q = refine_corners(q, gray)
            q = (q - pad + 0.5) / scale - 0.5  # pixel-centre aware mapping back to source
            q[:, 0] = np.clip(q[:, 0], 0, w - 1)
            q[:, 1] = np.clip(q[:, 1], 0, h - 1)
            return Detection(q.astype(np.float32), True, ratio)
    return Detection(full_bounds(w, h), False, 0.0)
