"""Flattening: map the 4 page corners onto a flat rectangle.

A page whose top or bottom edge bows (an open book, a bent sheet) is
flattened with a grid warp that follows those edges; otherwise a single
perspective warp is used.
"""

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


CURVE_MIN_BOW = 0.015  # a side bowing less than this (fraction of its length) counts as straight
CURVE_MAX_BOW = 0.15  # tracing further than this from the straight side gives up
CURVE_SAMPLES = 48  # points traced along each side
CURVE_WORK_SIDE = 1000  # edges are traced on a copy at most this big
CURVE_MIN_STEP = 12.0  # brightness step (0-255) across the edge that counts as found


def _curve_basis(t: np.ndarray) -> np.ndarray:
    """d(t) = t(1-t)(c0 + c1 t): zero at both corners, one bend (c0) and a lean (c1)."""
    return np.stack([t * (1 - t), t * t * (1 - t)], axis=1)


def _edge_steps(gray: np.ndarray, pts: np.ndarray, outward: np.ndarray) -> np.ndarray:
    """Brightness step from inside to outside the page at each point (signed)."""
    h, w = gray.shape

    def at(p):
        x = np.clip(np.rint(p[..., 0]).astype(int), 0, w - 1)
        y = np.clip(np.rint(p[..., 1]).astype(int), 0, h - 1)
        return gray[y, x].astype(np.float32)

    return at(pts - 2 * outward) - at(pts + 2 * outward)


def side_curve(gray: np.ndarray, a: np.ndarray, b: np.ndarray, outward: np.ndarray) -> np.ndarray:
    """Trace the page edge between corners a and b (in gray's pixels) and fit
    d(t) = t(1-t)(c0 + c1 t): its offset from the straight side along the
    outward normal. Returns (c0, c1); zeros when the side is straight or its
    edge cannot be traced.

    The edge is followed from corner a towards b, each step searching only near
    the previous offset, for the largest brightness step of the same polarity
    as at the corners (paper brighter than the table, or darker), so it does
    not jump to text, a pen or the table. The curve is kept only when it is a
    clearly better edge than the straight side.
    """
    L = float(np.linalg.norm(b - a))
    if L < 20:
        return np.zeros(2)
    max_off = CURVE_MAX_BOW * L
    window = max(3.0, 0.02 * L)
    ts = np.linspace(0.04, 0.96, CURVE_SAMPLES)
    chord = a[None, :] + ts[:, None] * (b - a)[None, :]
    straight = _edge_steps(gray, chord, outward)
    # Polarity from near the corners, where the edge is close to the straight
    # side (a bowed side already leaves it a little: search a small window).
    near = np.arange(-window, window + 1)
    ends = [
        _edge_steps(gray, base[None, :] + near[:, None] * outward[None, :], outward)
        for base in np.concatenate([chord[:4], chord[-4:]])
    ]
    sign = 1.0 if np.median([e[np.abs(e).argmax()] for e in ends]) >= 0 else -1.0
    prev, found_t, found_d = 0.0, [], []
    for t, base in zip(ts, chord):
        offs = np.arange(max(-max_off, prev - window), min(max_off, prev + window) + 1)
        step = sign * _edge_steps(gray, base[None, :] + offs[:, None] * outward[None, :], outward)
        k = int(step.argmax())
        if step[k] >= CURVE_MIN_STEP:
            prev = float(offs[k])
            found_t.append(t)
            found_d.append(prev)
    if len(found_t) < 0.7 * len(ts):
        return np.zeros(2)
    t, d = np.array(found_t), np.array(found_d)
    keep = np.ones(len(t), bool)
    c = np.zeros(2)
    for _ in range(3):  # least squares, dropping outliers (text, a finger)
        c, *_ = np.linalg.lstsq(_curve_basis(t[keep]), d[keep], rcond=None)
        res = np.abs(d - _curve_basis(t) @ c)
        keep = res <= max(2.0, 2.5 * float(np.median(res[keep])))
    # Keep the curve only if the edge follows it clearly better than the chord.
    curved = chord + (_curve_basis(ts) @ c)[:, None] * outward[None, :]
    on_curve = float((sign * _edge_steps(gray, curved, outward) >= CURVE_MIN_STEP).mean())
    on_chord = float((sign * straight >= CURVE_MIN_STEP).mean())
    if on_curve < 0.8 or on_curve < on_chord + 0.15:
        return np.zeros(2)
    return c


def page_curves(image: np.ndarray, corners: np.ndarray) -> tuple[np.ndarray, np.ndarray] | None:
    """Fitted (c0, c1) of the top and bottom edges in image pixels, or None
    when both are straight (the plain perspective warp is right)."""
    q = order_corners(corners).astype(np.float64)
    h, w = image.shape[:2]
    s = min(1.0, CURVE_WORK_SIDE / max(h, w))
    small = cv2.resize(image, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA) if s < 1 else image
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY) if small.ndim == 3 else small
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    qs = q * s
    centre = qs.mean(axis=0)
    curves = []
    for a, b in ((qs[0], qs[1]), (qs[3], qs[2])):  # top: TL->TR, bottom: BL->BR
        ab = b - a
        n = np.array([-ab[1], ab[0]]) / (np.linalg.norm(ab) + 1e-9)
        if n @ (centre - a) > 0:
            n = -n
        c = side_curve(gray, a, b, n) / s
        curves.append(c)
    t = np.linspace(0, 1, 101)
    bows = [
        float(np.abs(_curve_basis(t) @ c).max()) / float(np.linalg.norm(q[j] - q[i]))
        for c, (i, j) in zip(curves, ((0, 1), (3, 2)))
    ]
    if max(bows) < CURVE_MIN_BOW:
        return None
    return curves[0], curves[1]


def warp_page(image: np.ndarray, corners: np.ndarray, max_side: int | None = None) -> np.ndarray:
    """Flatten the page: a grid warp following bowed top/bottom edges, or the
    plain perspective warp when they are straight."""
    curves = page_curves(image, corners)
    if curves is None:
        return warp_perspective(image, corners, max_side)
    src = order_corners(corners).astype(np.float64)
    w, h = output_size(src)
    if max_side and max(w, h) > max_side:
        s = max_side / max(w, h)
        w, h = max(1, round(w * s)), max(1, round(h * s))
    dst = np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]])
    M = cv2.getPerspectiveTransform(dst, src.astype(np.float32))  # output -> photo
    # The map on a coarse grid (every 8 px), then resized: smooth and cheap.
    # Resizing aligns pixel centres, so grid point j stands for output pixel
    # 8j + 3.5.
    step = 8
    gw, gh = w // step + 2, h // step + 2
    u = np.arange(gw) * step + (step - 1) / 2
    v = np.arange(gh) * step + (step - 1) / 2
    uu, vv = np.meshgrid(u, v)
    pts = cv2.perspectiveTransform(np.stack([uu, vv], -1).reshape(-1, 1, 2).astype(np.float32), M).reshape(gh, gw, 2)
    pts = pts.astype(np.float64)
    centre = src.mean(axis=0)
    offset = np.zeros_like(pts)
    for c, (a, b), row in zip(curves, ((src[0], src[1]), (src[3], src[2])), (0.0, float(h - 1))):
        ab = b - a
        L2 = float(ab @ ab)
        n = np.array([-ab[1], ab[0]]) / np.sqrt(L2)
        if n @ (centre - a) > 0:
            n = -n
        # Where each output column meets this side, as a fraction along the side.
        edge = cv2.perspectiveTransform(np.stack([u, np.full_like(u, row)], -1).reshape(-1, 1, 2).astype(np.float32), M)
        t = np.clip(((edge.reshape(-1, 2) - a) @ ab) / L2, 0, 1)
        d = _curve_basis(t) @ c  # px, outwards
        weight = (1 - vv / (h - 1)) if row == 0 else vv / (h - 1)
        offset += weight[..., None] * d[None, :, None] * n[None, None, :]
    pts += offset
    map_x = cv2.resize(pts[..., 0].astype(np.float32), (gw * step, gh * step), interpolation=cv2.INTER_LINEAR)[:h, :w]
    map_y = cv2.resize(pts[..., 1].astype(np.float32), (gw * step, gh * step), interpolation=cv2.INTER_LINEAR)[:h, :w]
    return cv2.remap(image, map_x, map_y, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
