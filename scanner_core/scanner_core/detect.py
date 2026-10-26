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

# Tunables. Mirror any change in shared/detector_params.json (checked by the Dart and JS ports).
MAX_DIM = 500  # longest side of the working image
MIN_AREA_RATIO = 0.04  # quad must cover at least 4% of the frame (an ID card held at arm's length)
MIN_FILL_RATIO = 0.85  # contour area / quad area: rejects hulls of scattered clutter
MAX_EDGE_DEVIATION = 0.025  # 90th pct distance of contour to quad edges, as fraction of quad diagonal
MIN_ANGLE, MAX_ANGLE = 35.0, 145.0  # interior angle sanity range (degrees)
APPROX_EPSILONS = (0.02, 0.03, 0.04)
MAX_BOW = 0.12  # a side may bow (book page) by up to 12% of its length
CURVED_BOW = 0.02  # above this a side counts as curved
MIN_SUPPORT = 0.6  # each side needs an edge across it along >= 60% of its length
STEP_OFFSET = 3.0  # px either side of a side where inside/outside brightness is compared
STEP_MIN = 10.0  # brightness step (0-255) that counts as a border
MIN_LINE_SUPPORT = 0.5  # quads built from straight lines: up to half a side may be hidden (fingers)
LINE_COUNT = 8  # longest distinct straight edges combined into quads
HOUGH_THRESHOLD, HOUGH_MIN_LENGTH, HOUGH_MAX_GAP = (
    40,
    0.12,
    8,
)  # straight edges: votes, min length (of the long side), gap
CONFIDENT_SCORE = 0.35  # a pass result this good ends the search; weaker ones let later passes try


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


def _extreme_points(c: np.ndarray) -> np.ndarray:
    """Corners as the outline's most top-left, top-right, bottom-right and
    bottom-left points: still right when the sides bow (curved book pages)."""
    p = c.reshape(-1, 2).astype(np.float32)
    s, d = p[:, 0] + p[:, 1], p[:, 0] - p[:, 1]
    return np.float32([p[s.argmin()], p[d.argmax()], p[s.argmax()], p[d.argmin()]])


def _side_fits(c: np.ndarray, q: np.ndarray):
    """Fit each side of quad q to the outline points nearest to it, as a
    parabola d(t) = a*t*(1-t) across the side (straight sides: a = 0; d is
    measured along the side's left normal). Returns per side (a in px, 90th
    percentile residual in px)."""
    p = c.reshape(-1, 2).astype(np.float32)
    # Densify: CHAIN_APPROX_SIMPLE keeps only vertices.
    dense = []
    for i in range(len(p)):
        a, b = p[i], p[(i + 1) % len(p)]
        k = max(1, int(np.linalg.norm(b - a) / 2))
        dense.append(a + np.linspace(0, 1, k, endpoint=False)[:, None] * (b - a))
    p = np.concatenate(dense)
    dist = np.empty((4, len(p)), np.float32)
    frames = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        ab = b - a
        L = float(np.linalg.norm(ab)) + 1e-6
        u, n = ab / L, np.float32([-ab[1], ab[0]]) / L
        t = ((p - a) @ u) / L
        d = (p - a) @ n
        dist[i] = np.where((t >= 0) & (t <= 1), np.abs(d), np.inf)
        frames.append((t, d, L))
    side = dist.argmin(axis=0)
    out = []
    for i in range(4):
        t, d, L = frames[i]
        m = (side == i) & np.isfinite(dist[i])
        if m.sum() < 6:
            out.append((0.0, 0.0))
            continue
        basis, dm = t[m] * (1 - t[m]), d[m]
        straight = float(np.percentile(np.abs(dm), 90))
        mid = basis > 0.1  # the bow, robustly: the median over the side's middle
        if mid.sum() < 4:
            out.append((0.0, straight))
            continue
        a = float(np.median(dm[mid] / basis[mid]))
        bowed = float(np.percentile(np.abs(dm - a * basis), 90))
        # Straight unless the curve fits clearly better.
        out.append((0.0, straight) if straight <= 1.25 * bowed else (a, bowed))
    return out


def _edge_support(q: np.ndarray, bows, img: np.ndarray) -> list[float]:
    """Share of each side (following its bow) where the image steps from
    inside to outside the quad, in the same direction as along most of that
    side (paper brighter than the table, or darker). A page border does that
    all along; texture, stripes and the photo's own frame do not."""
    h, w = img.shape
    centre = q.mean(axis=0)
    out = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        ab = b - a
        L = float(np.linalg.norm(ab)) + 1e-6
        left = np.float32([-ab[1], ab[0]]) / L
        ts = np.linspace(0.1, 0.9, 24, dtype=np.float32)
        base = a + ts[:, None] * ab + (bows[i] * ts * (1 - ts))[:, None] * left  # follows the bow
        n = -left if left @ (centre - a) > 0 else left  # pointing outwards
        diffs = []
        for o in (-1.0, 0.0, 1.0):  # the border may sit a pixel either side
            pin, pout = base + (o - STEP_OFFSET) * n, base + (o + STEP_OFFSET) * n
            vi = img[
                np.clip(np.rint(pin[:, 1]).astype(int), 0, h - 1), np.clip(np.rint(pin[:, 0]).astype(int), 0, w - 1)
            ]
            vo = img[
                np.clip(np.rint(pout[:, 1]).astype(int), 0, h - 1), np.clip(np.rint(pout[:, 0]).astype(int), 0, w - 1)
            ]
            diffs.append(vi.astype(np.float32) - vo.astype(np.float32))
        d = np.array(diffs)
        d = d[np.abs(d).argmax(axis=0), np.arange(d.shape[1])]
        sign = 1.0 if np.median(d) >= 0 else -1.0
        out.append(float((d * sign > STEP_MIN).mean()))
    return out


def _line_quads(edges: np.ndarray, img_area: float) -> list[np.ndarray]:
    """Quads made of 4 long straight edges (2 roughly opposite pairs), each
    extended to the others: finds a page whose corners are hidden (fingers,
    other papers) or whose outline merges with clutter."""
    h, w = edges.shape
    segs = cv2.HoughLinesP(
        edges, 1, np.pi / 180, HOUGH_THRESHOLD, minLineLength=HOUGH_MIN_LENGTH * max(h, w), maxLineGap=HOUGH_MAX_GAP
    )
    if segs is None:
        return []
    segs = segs.reshape(-1, 4).astype(np.float32)
    segs = segs[np.argsort(-np.hypot(segs[:, 2] - segs[:, 0], segs[:, 3] - segs[:, 1]))]
    lines: list[tuple[np.ndarray, np.ndarray, float]] = []  # (point, unit direction, angle)
    for x1, y1, x2, y2 in segs:
        d = np.float32([x2 - x1, y2 - y1])
        d /= np.linalg.norm(d) + 1e-6
        ang = float(np.degrees(np.arctan2(d[1], d[0]))) % 180
        p = np.float32([x1, y1])
        # Skip near-duplicates (same direction, within 6 px).
        if any(
            min(abs(ang - a), 180 - abs(ang - a)) < 8 and abs(float(dd[0] * (p - pp)[1] - dd[1] * (p - pp)[0])) < 6
            for pp, dd, a in lines
        ):
            continue
        lines.append((p, d, ang))
        if len(lines) == LINE_COUNT:
            break
    # Two families: roughly horizontal and roughly vertical (within 45 deg).
    horiz = [ln for ln in lines if ln[2] < 45 or ln[2] >= 135]
    vert = [ln for ln in lines if 45 <= ln[2] < 135]
    quads = []
    for i in range(len(horiz)):
        for j in range(i + 1, len(horiz)):
            for k in range(len(vert)):
                for m in range(k + 1, len(vert)):
                    pts = []
                    for a, b in ((horiz[i], vert[k]), (vert[k], horiz[j]), (horiz[j], vert[m]), (vert[m], horiz[i])):
                        x = _line_intersection(a[0], a[0] + a[1], b[0], b[0] + b[1])
                        if x is None:
                            break
                        pts.append(x)
                    if len(pts) == 4:
                        q = np.float32(pts)
                        if (
                            (q[:, 0] > -0.02 * w).all()
                            and (q[:, 0] < 1.02 * w).all()
                            and (q[:, 1] > -0.02 * h).all()
                            and (q[:, 1] < 1.02 * h).all()
                        ):
                            quads.append(q)
    return quads


def _best_quad(edges: np.ndarray, img: np.ndarray) -> tuple[np.ndarray, float, bool, float] | None:
    """Best page outline: every candidate quad that passes the sanity checks is
    scored by size, edge support and squareness; the highest score wins (not
    simply the largest shape). Candidates come from the outlines in the edge
    map and from long straight edges. Returns (quad, area ratio, curved, score)."""
    h, w = edges.shape
    img_area = float(w * h)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:12]
    best, best_score = None, 0.0

    def consider(r):
        nonlocal best, best_score
        if r is not None and r[1] > best_score:
            best, best_score = (r[0], cv2.contourArea(r[0]) / img_area, r[2], r[1]), r[1]

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
        candidates.append(_extreme_points(c))
        for q in candidates:
            consider(_validate(c, c_area, q, img_area, img))
    for q in _line_quads(edges, img_area):  # straight edges: recovers hidden corners
        consider(_validate(None, 0, q, img_area, img))
    return best


def _validate(c, c_area, q, img_area, img):
    """(ordered quad, score, curved) if q passes every sanity check, else None.
    c is the outline q came from (None for a quad made of straight lines: then
    only its sides' edge support is checked, and parts of a side may be hidden)."""
    q = order_corners(q)
    if not cv2.isContourConvex(q.reshape(-1, 1, 2)):
        return None
    q_area = cv2.contourArea(q)
    if q_area < MIN_AREA_RATIO * img_area or (c is not None and c_area / q_area < MIN_FILL_RATIO):
        return None
    ang = _interior_angles(q)
    if ang.min() < MIN_ANGLE or ang.max() > MAX_ANGLE:
        return None
    if c is None:
        bows = [0.0] * 4
        min_support = MIN_LINE_SUPPORT
        fit = 0.5  # no outline to compare with
    else:
        diag = float(np.linalg.norm(q[2] - q[0]))
        fits = _side_fits(c, q)
        bows = [a for a, _ in fits]
        fit = max(r for _, r in fits) / (MAX_EDGE_DEVIATION * diag)  # 0 = perfect, 1 = at the limit
        sides = [float(np.linalg.norm(q[(i + 1) % 4] - q[i])) for i in range(4)]
        bow_ratio = max(abs(a) / 4 / L for a, L in zip(bows, sides))
        if max(r for _, r in fits) > MAX_EDGE_DEVIATION * diag or bow_ratio > MAX_BOW:
            return None
        min_support = MIN_SUPPORT
    # Along the fitted bow or the straight side, whichever has the border (a
    # bow fitted to a straight side's noisy outline can miss it).
    support = [max(x, y) for x, y in zip(_edge_support(q, bows, img), _edge_support(q, [0.0] * 4, img))]
    if min(support) < min_support:
        return None
    squareness = 1 - float(np.abs(ang - 90).mean()) / 90
    # Tie-break between near-identical quads: the one hugging its outline wins.
    score = float(np.sqrt(q_area / img_area)) * float(np.mean(support)) * squareness * (1 - 0.1 * fit)
    curved = c is not None and bow_ratio > CURVED_BOW
    return q, score, curved


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


def normalize_lighting(gray: np.ndarray) -> np.ndarray:
    """Even out shadows and uneven light: divide by a heavily blurred copy (the
    lighting), then boost local contrast with CLAHE."""
    k = max(3, (max(gray.shape) // 8) | 1)
    bg = cv2.GaussianBlur(gray, (k, k), 0).astype(np.float32) + 1
    flat = np.clip(gray.astype(np.float32) / bg * 180, 0, 255).astype(np.uint8)
    return cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(flat)


def edge_map(channel: np.ndarray, low: bool = False) -> np.ndarray:
    """Canny (thresholds from the median, or fixed low ones for flat images),
    then close small gaps so a page border forms one closed outline."""
    g = cv2.GaussianBlur(channel, (5, 5), 0)
    # Median-based thresholds are far too high for a white page on a white
    # table (median ~220), hence the fixed low ones for the second pass.
    e = cv2.Canny(g, 12, 36) if low else auto_canny(g)
    return cv2.dilate(e, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)


def detect_document(image: np.ndarray, max_dim: int = MAX_DIM) -> Detection:
    """Detect the page in a BGR or grayscale image. Corners are in source pixels.

    Passes, until one finds a page confidently (else the best of all): (1) grayscale; (2) lighting normalised +
    CLAHE, for shadows and white-on-white; (3) colour saturation, for a page on
    a coloured background of the same brightness.
    """
    if image is None or image.size == 0:
        raise ValueError("empty image")
    h, w = image.shape[:2]
    scale = min(1.0, max_dim / max(h, w))
    small = (
        cv2.resize(image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA) if scale < 1 else image
    )
    # Pad by a few pixels so a page touching the border still forms a closed contour.
    pad = 4
    small = cv2.copyMakeBorder(small, pad, pad, pad, pad, cv2.BORDER_REPLICATE)
    color = small.ndim == 3
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY) if color else small
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    passes = [
        (gray, False),
        (lambda: clahe.apply(gray), True),
        (lambda: normalize_lighting(gray), True),
    ]
    if color:
        passes.append((lambda: cv2.cvtColor(small, cv2.COLOR_BGR2HSV)[..., 1], False))
    best = None
    for channel, low in passes:
        channel = channel() if callable(channel) else channel  # built only when needed
        # Edge support is measured on the same channel the pass searched.
        res = _best_quad(edge_map(channel, low), cv2.GaussianBlur(channel, (5, 5), 0))
        if res is not None and (best is None or res[3] > best[3]):
            best = res
        if best is not None and best[3] >= CONFIDENT_SCORE:
            break  # a clear page: skip the remaining passes
    if best is not None:
        q, ratio, curved, _ = best
        if not curved:  # refining fits straight lines: wrong for a bowed side
            q = refine_corners(q, gray)
        q = (q - pad + 0.5) / scale - 0.5  # pixel-centre aware mapping back to source
        q[:, 0] = np.clip(q[:, 0], 0, w - 1)
        q[:, 1] = np.clip(q[:, 1], 0, h - 1)
        return Detection(q.astype(np.float32), True, ratio)
    return Detection(full_bounds(w, h), False, 0.0)
