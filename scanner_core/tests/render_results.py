"""Render a before/after sheet: detection overlay, flattened page and each filter.

Usage: python tests/render_results.py ../docs/stage1_results.jpg
"""

import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scanner_core import Filter, apply_filter, detect_document, warp_perspective  # noqa: E402

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
NAMES = ["tilted_paper", "low_contrast", "cluttered_background", "shadow_across", "strong_perspective"]
TH = 420


def fit(img, label):
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    s = min(TH / img.shape[0], 320 / img.shape[1])
    img = cv2.resize(img, (round(img.shape[1] * s), round(img.shape[0] * s)), interpolation=cv2.INTER_AREA)
    tile = np.full((TH + 34, 330, 3), 255, np.uint8)
    x, y = (330 - img.shape[1]) // 2, 34 + (TH - img.shape[0]) // 2
    tile[y : y + img.shape[0], x : x + img.shape[1]] = img
    cv2.putText(tile, label, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (30, 30, 30), 1, cv2.LINE_AA)
    return tile


rows = []
for name in NAMES:
    img = cv2.imread(str(FIX / f"{name}.jpg"))
    det = detect_document(img)
    vis = img.copy()
    cv2.polylines(vis, [det.corners.astype(np.int32)], True, (60, 200, 60), 10, cv2.LINE_AA)
    for p in det.corners.astype(int):
        cv2.circle(vis, tuple(p), 20, (255, 140, 0), -1)
    flat = warp_perspective(img, det.corners)
    tiles = [fit(vis, f"{name} (detected)"), fit(flat, "flattened")]
    tiles += [fit(apply_filter(flat, f), f.value) for f in (Filter.GRAYSCALE, Filter.BW, Filter.MAGIC_COLOR)]
    rows.append(np.hstack(tiles))
out = sys.argv[1] if len(sys.argv) > 1 else "stage1_results.jpg"
cv2.imwrite(out, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
print("wrote", out)
