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
MIN_LINE_SUPPORT = 0.75  # quads built from straight lines: up to a quarter of a side may be hidden (fingers)
LINE_COUNT = 8  # longest distinct straight edges combined into quads
LINE_MIN_LENGTH = 0.12  # straight edges at least this long (fraction of the image's long side)
LINE_EPSILON = 0.005  # outline simplification for straight edges (fraction of its perimeter)
CONFIDENT_SCORE = 0.35  # a pass result this good ends the search; weaker ones let later passes try
PAD = 4  # working image padding (replicated border) so a page touching the edge still closes
FRAME_MARGIN = 0.012  # a side this close (fraction of the long side) to the photo's border lies on it
MAX_FRAME_SIDES = 2  # more sides on the photo's border: that is the photo itself, not a page
MAX_AREA = 0.95  # a quad covering more of the photo than this is the photo itself
FRAME_SIDE_FACTOR = 0.8  # score factor per side lying on the photo's border
TEXTURE_MORPH = 0.02  # texture pass: closing kernel (fraction of the long side) wiping out text and ruled lines
PAPER_SAT_MAX = 60  # paper mask: colourless (HSV saturation below this) ...
PAPER_MORPH = 0.02  # ... morphology kernel (fraction of the long side) removing checks, text and gaps
GLARE_PERCENTILE = 99.0  # lighting pass: highlights (flash glare) clipped at this brightness percentile
HOUGH_LINES = 8  # lines pass: strongest lines kept per direction (roughly horizontal, roughly vertical)
HOUGH_TILT = 20  # ... within this many degrees of horizontal / vertical
HOUGH_VOTES = 0.06  # ... with at least this many edge pixels (fraction of the long side)
DOC_RATIOS = (1.586, 1.414, 1.294)  # ID-1 card (Aadhaar, PAN, licence), ISO A sizes and passport page, US Letter
RATIO_TOL = 0.05  # a lines-pass outline within 5 % of one of these proportions ...
RATIO_BONUS = 1.15  # ... scores this much higher
TRACK_MARGIN = 1.25  # live frames: a new outline replaces the tracked one only if this much better
TRACK_FULL_EVERY = 5  # ... and every this many frames all passes run anyway (in the scanner, not here)


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


def _line_quads(segs: np.ndarray, w: int, h: int) -> list[np.ndarray]:
    """Quads made of 4 long straight edges ([segs]: x1, y1, x2, y2), two roughly
    opposite pairs, each extended to the others: finds a page whose corners are
    hidden (fingers, other papers) or whose outline merges with clutter."""
    if len(segs) == 0:
        return []
    segs = segs[np.argsort(-np.hypot(segs[:, 2] - segs[:, 0], segs[:, 3] - segs[:, 1]), kind="stable")]
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
    # Straight edges: the long sides of the 12 largest outlines, simplified. Pairs of them
    # recover corners hidden by fingers or merged with clutter. (Not
    # HoughLinesP: it is randomised and differs between OpenCV versions.)
    segs = []
    min_len = LINE_MIN_LENGTH * max(h, w)
    for c in contours:
        if cv2.arcLength(c, True) < 2 * min_len:
            continue
        p = cv2.approxPolyDP(c, LINE_EPSILON * cv2.arcLength(c, True), True).reshape(-1, 2).astype(np.float32)
        for k in range(len(p)):
            a, b = p[k], p[(k + 1) % len(p)]
            if np.linalg.norm(b - a) >= min_len:
                segs.append([a[0], a[1], b[0], b[1]])
    for q in _line_quads(np.float32(segs).reshape(-1, 4), w, h):
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
    # Never the photo itself (a checked cloth or the padding forms its border).
    on_frame = _on_frame(q, img.shape[1], img.shape[0])
    frame_sides = sum(on_frame)
    if q_area > MAX_AREA * img_area or frame_sides > MAX_FRAME_SIDES:
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
    # A side along the photo's border is less likely a page edge than the
    # photo's own border meeting cloth: prefer outlines inside the photo.
    score *= FRAME_SIDE_FACTOR**frame_sides
    curved = c is not None and bow_ratio > CURVED_BOW
    return q, score, curved


def _known_ratio(q: np.ndarray) -> bool:
    """Are q's proportions (mean of opposite sides) those of an ID card or a
    standard paper size? Perspective changes them a little, hence the tolerance."""
    s = [float(np.linalg.norm(q[(i + 1) % 4] - q[i])) for i in range(4)]
    a, b = s[0] + s[2], s[1] + s[3]
    if a < 1e-6 or b < 1e-6:
        return False
    r = max(a, b) / min(a, b)
    return any(abs(r / k - 1) < RATIO_TOL for k in DOC_RATIOS)


def _hough_peaks(mask: np.ndarray, centre: int, thr: int) -> list[tuple[float, float]]:
    """Straight lines (rho, theta) through the pixels of [mask], theta within
    HOUGH_TILT degrees of [centre]: a vote count over whole degrees and pixels,
    strongest first, each suppressing its neighbours (+-5 degrees, +-8 px).
    Written out (not cv2.HoughLines, missing from opencv.js) so that every
    port finds the same lines."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    degs = np.arange(centre - HOUGH_TILT, centre + HOUGH_TILT + 1)
    th = degs * (np.pi / 180)
    r_max = int(np.hypot(w, h)) + 1
    acc = np.zeros((len(th), 2 * r_max + 1), np.int32)
    for k in range(len(th)):
        rho = np.floor(xs * np.cos(th[k]) + ys * np.sin(th[k]) + 0.5).astype(np.int64) + r_max
        acc[k] = np.bincount(rho, minlength=2 * r_max + 1)
    out = []
    while len(out) < HOUGH_LINES:
        i = int(acc.argmax())  # first maximum in row-major order
        k, r = divmod(i, acc.shape[1])
        if acc[k, r] < thr:
            break
        out.append((float(r - r_max), float(th[k])))
        acc[max(0, k - 5) : k + 6, max(0, r - 8) : r + 9] = 0
    return out


def _hough_quad(g: np.ndarray) -> tuple[np.ndarray, float, bool, float] | None:
    """Lines pass, for a page or card on busy cloth whose outline merges with
    the pattern: the strongest roughly horizontal and roughly vertical lines
    (each voted for only by edge pixels whose gradient points across it, so a
    diagonal or zigzag pattern does not count), every two of each combined
    into a quad and checked like any straight-line quad."""
    h, w = g.shape
    e = cv2.Canny(g, 12, 36) > 0
    gx = np.abs(cv2.Sobel(g, cv2.CV_16S, 1, 0).astype(np.int32))
    gy = np.abs(cv2.Sobel(g, cv2.CV_16S, 0, 1).astype(np.int32))
    thr = int(HOUGH_VOTES * max(w, h))
    horiz = _hough_peaks(e & (gy > 2 * gx), 90, thr)
    vert = _hough_peaks(e & (gx > 2 * gy), 0, thr)
    img_area = float(w * h)
    best, best_score = None, 0.0
    for i in range(len(horiz)):
        for j in range(i + 1, len(horiz)):
            for k in range(len(vert)):
                for m in range(k + 1, len(vert)):
                    pts = [
                        _hough_cross(horiz[i], vert[k]),
                        _hough_cross(horiz[i], vert[m]),
                        _hough_cross(horiz[j], vert[m]),
                        _hough_cross(horiz[j], vert[k]),
                    ]
                    if any(p is None for p in pts):
                        continue
                    q = np.float32(pts)
                    if (
                        (q[:, 0] < -0.02 * w).any()
                        or (q[:, 0] > 1.02 * w).any()
                        or (q[:, 1] < -0.02 * h).any()
                        or (q[:, 1] > 1.02 * h).any()
                    ):
                        continue
                    r = _validate(None, 0, q, img_area, g)
                    if r is None:
                        continue
                    # Lines make many rectangles (a card's printed boxes, too):
                    # prefer one shaped like a card or a sheet of paper.
                    score = r[1] * (RATIO_BONUS if _known_ratio(r[0]) else 1.0)
                    if score > best_score:
                        best, best_score = (r[0], cv2.contourArea(r[0]) / img_area, False, score), score
    return best


def _hough_cross(l1: tuple[float, float], l2: tuple[float, float]) -> tuple[float, float] | None:
    (r1, t1), (r2, t2) = l1, l2
    c1, s1, c2, s2 = np.cos(t1), np.sin(t1), np.cos(t2), np.sin(t2)
    det = c1 * s2 - s1 * c2
    if abs(det) < 1e-6:
        return None
    return ((r1 * s2 - s1 * r2) / det, (c1 * r2 - r1 * c2) / det)


def _on_frame(q: np.ndarray, w: int, h: int) -> list[bool]:
    """For each side of q: does it lie along the photo's border (both ends
    within FRAME_MARGIN of the same edge of the unpadded photo)?"""
    m = FRAME_MARGIN * max(w, h)
    lo, hx, hy = PAD + m, w - 1 - PAD - m, h - 1 - PAD - m
    out = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        out.append(
            bool((a[0] <= lo and b[0] <= lo) or (a[0] >= hx and b[0] >= hx) or (a[1] <= lo and b[1] <= lo) or (a[1] >= hy and b[1] >= hy))
        )
    return out


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
    # Sample positions in float64, as the Dart and JS ports compute them.
    q = quad.astype(np.float64).copy()
    for band in bands:
        lines = []
        offs = np.arange(-band, band + 1, dtype=np.float64)
        for i in range(4):
            a, b = q[i], q[(i + 1) % 4]
            ab = b - a
            length = float(np.linalg.norm(ab))
            n = np.array([-ab[1], ab[0]]) / (length + 1e-6)
            ts = np.linspace(0.1, 0.9, max(12, int(length / 3)))
            base = a + ts[:, None] * ab  # (S, 2)
            # The border's direction: is the page brighter or darker than what
            # is outside it here? Only edges stepping the same way count, so an
            # inner box (a card's photo) or a shadow cannot capture the side.
            centre = q.mean(axis=0)
            out_sign = 1.0 if float(n @ (a + b) / 2 - n @ centre) > 0 else -1.0  # n * out_sign points outwards
            pin = np.clip(np.rint(base - STEP_OFFSET * out_sign * n).astype(int), 0, [w - 1, h - 1])
            pout = np.clip(np.rint(base + STEP_OFFSET * out_sign * n).astype(int), 0, [w - 1, h - 1])
            step = float(np.median(g[pin[:, 1], pin[:, 0]] - g[pout[:, 1], pout[:, 0]]))
            want = -out_sign if step >= 0 else out_sign  # sign of the gradient along n at the border
            cand = base[:, None, :] + offs[None, :, None] * n  # (S, K, 2)
            xi = np.clip(np.rint(cand[..., 0]).astype(int), 0, w - 1)
            yi = np.clip(np.rint(cand[..., 1]).astype(int), 0, h - 1)
            resp = np.maximum(0.0, want * (gx[yi, xi] * n[0] + gy[yi, xi] * n[1]))  # gradient across the side, right way
            k = resp.argmax(axis=1)
            ok = (resp[np.arange(len(k)), k] > min_grad) & (k > 0) & (k < len(offs) - 1)
            peaks = cand[np.arange(len(k)), k][ok]
            if len(peaks) >= 0.4 * len(ts):
                vx, vy, x0, y0 = cv2.fitLine(peaks.astype(np.float32), cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
                lines.append((np.array([x0, y0], np.float64), np.array([x0 + vx, y0 + vy], np.float64)))
            else:
                lines.append((a, b))
        new = []
        for i in range(4):
            x = _line_intersection(*lines[i - 1], *lines[i])
            new.append(q[i] if x is None or np.linalg.norm(x - q[i]) > 3 * band else x)
        q = np.array(new, np.float64)
    return q


def _flatten(channel: np.ndarray) -> np.ndarray:
    """Divide by a heavily blurred copy (the lighting): shadows and light
    falloff even out, local differences stay."""
    # Two box blurs (about a Gaussian with sigma = long side / 50): fast at any
    # size, and computed identically by every OpenCV version (Python, web, Dart).
    k = max(3, (max(channel.shape) // 20) | 1)
    bg = cv2.blur(cv2.blur(channel, (k, k)), (k, k))
    return np.clip(channel.astype(np.float32) / (bg.astype(np.float32) + 1) * 180, 0, 255).astype(np.uint8)


def _clip_glare(gray: np.ndarray) -> np.ndarray:
    """Flash glare: brightness above the GLARE_PERCENTILE-th percentile is cut
    to it, so a burnt-out highlight does not outshine the page edge."""
    top = np.uint8(np.percentile(gray, GLARE_PERCENTILE))
    return np.minimum(gray, top)


def normalize_lighting(gray: np.ndarray) -> np.ndarray:
    """Even out shadows, uneven light and glare: clip highlights, divide by a
    heavily blurred copy (the lighting), then boost local contrast with CLAHE."""
    return cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(_flatten(_clip_glare(gray)))


def suppress_texture(gray: np.ndarray) -> np.ndarray:
    """Page outline without what is on or under the page: a closing with a
    square kernel (fast) of TEXTURE_MORPH of the long side fills in dark strokes (handwriting,
    ruled lines, print) and a median blur flattens cloth weave."""
    k = max(3, int(TEXTURE_MORPH * max(gray.shape)) | 1)
    closed = cv2.morphologyEx(gray, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (k, k)))
    return cv2.medianBlur(closed, 5)


def paper_mask(bgr: np.ndarray) -> np.ndarray:
    """Where the paper is: colourless (low saturation) and bright for its
    surroundings (brightness with the lighting divided out, above the Otsu
    threshold). Opening then closing with a square kernel (fast) of PAPER_MORPH of the long
    side removes cloth checks, ruled lines and text; only the largest connected
    region is kept. 255 = paper."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    sat, val = hsv[..., 1], _flatten(hsv[..., 2])
    _, bright = cv2.threshold(val, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    mask = np.where((sat < PAPER_SAT_MAX) & (bright > 0), 255, 0).astype(np.uint8)
    k = max(3, int(PAPER_MORPH * max(mask.shape)) | 1)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (k, k))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if n <= 1:
        return np.zeros_like(mask)
    biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return np.where(labels == biggest, 255, 0).astype(np.uint8)


def edge_map(channel: np.ndarray, low: bool = False) -> np.ndarray:
    """Canny (thresholds from the median, or fixed low ones for flat images),
    then close small gaps so a page border forms one closed outline."""
    g = cv2.GaussianBlur(channel, (5, 5), 0)
    # Median-based thresholds are far too high for a white page on a white
    # table (median ~220), hence the fixed low ones for the second pass.
    e = cv2.Canny(g, 12, 36) if low else auto_canny(g)
    return cv2.dilate(e, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)


def _track_quad(gray: np.ndarray, hint: np.ndarray):
    """Live tracking: the previous frame's outline ([hint], working pixels)
    snapped to this frame's edges and checked like a straight-line quad.
    (ordered quad, score, curved) or None."""
    g = cv2.GaussianBlur(gray, (5, 5), 0)
    return _validate(None, 0, refine_corners(np.float32(hint), gray), float(g.size), g)


def detect_document(
    image: np.ndarray, max_dim: int = MAX_DIM, hint: np.ndarray | None = None, full: bool = False
) -> Detection:
    """Detect the page in a BGR or grayscale image. Corners are in source pixels.

    Passes, until one finds a page confidently (else the best of all): (1) grayscale; (2) lighting normalised +
    CLAHE, for shadows and white-on-white; (3) colour saturation, for a page on
    a coloured background of the same brightness.

    Live frames: [hint] is the previous frame's outline (source pixels); if it
    still fits this frame it is kept (a steady outline, and fast) unless
    [full], which searches every pass anyway.
    """
    if image is None or image.size == 0:
        raise ValueError("empty image")
    h, w = image.shape[:2]
    scale = min(1.0, max_dim / max(h, w))
    small = (
        cv2.resize(image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA) if scale < 1 else image
    )
    # Pad by a few pixels so a page touching the border still forms a closed contour.
    pad = PAD
    small = cv2.copyMakeBorder(small, pad, pad, pad, pad, cv2.BORDER_REPLICATE)
    color = small.ndim == 3
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY) if color else small
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    # (channel, low thresholds, image the borders are checked on: None = the channel itself)
    passes = [
        (gray, False, None),
        (lambda: clahe.apply(gray), True, None),
        (lambda: normalize_lighting(gray), True, None),
        (lambda: suppress_texture(_flatten(_clip_glare(gray))), True, None),
    ]
    if color:
        passes.append((lambda: cv2.cvtColor(small, cv2.COLOR_BGR2HSV)[..., 1], False, None))
        # The paper mask: its outlines are checked against the photo's own
        # edges (the mask's are always crisp), so a blob of paper plus pale
        # cloth does not pass.
        passes.append((lambda: paper_mask(small), False, gray))
    tracked = None
    if hint is not None:
        hw = (np.float32(hint).reshape(4, 2) + 0.5) * scale - 0.5 + pad
        t = _track_quad(gray, hw)
        if t is not None:
            tracked = (t[0], cv2.contourArea(t[0]) / float(gray.size), False, t[1])
    if tracked is not None and not full and not any(_on_frame(tracked[0], gray.shape[1], gray.shape[0])):
        passes = []  # the page still where it was, with all four sides visible: keep it
    best = None
    for channel, low, support in passes:
        channel = channel() if callable(channel) else channel  # built only when needed
        res = _best_quad(edge_map(channel, low), cv2.GaussianBlur(channel if support is None else support, (5, 5), 0))
        if res is not None and (best is None or res[3] > best[3]):
            best = res
        if best is not None and best[3] >= CONFIDENT_SCORE:
            break  # a clear page: skip the remaining passes
    if passes and (best is None or best[3] < CONFIDENT_SCORE or any(_on_frame(best[0], gray.shape[1], gray.shape[0]))):
        # Last: straight lines across the whole photo (a card on busy cloth,
        # whose outline may have merged with the cloth down to the photo's border).
        res = _hough_quad(cv2.GaussianBlur(gray, (5, 5), 0))
        if res is not None and (best is None or res[3] > best[3]):
            best = res
    # Switch away from the tracked outline only for a clearly better one.
    if tracked is not None and (best is None or tracked[3] * TRACK_MARGIN >= best[3]):
        best = tracked
    if best is not None:
        q, ratio, curved, _ = best
        if not curved:  # refining fits straight lines: wrong for a bowed side
            q = refine_corners(q, gray)
        q = (q - pad + 0.5) / scale - 0.5  # pixel-centre aware mapping back to source
        q[:, 0] = np.clip(q[:, 0], 0, w - 1)
        q[:, 1] = np.clip(q[:, 1], 0, h - 1)
        return Detection(q.astype(np.float32), True, ratio)
    return Detection(full_bounds(w, h), False, 0.0)
