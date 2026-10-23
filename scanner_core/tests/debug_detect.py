"""Run detection on every fixture, print the corner error and save an overlay sheet.

Usage: python tests/debug_detect.py [out.jpg]
"""

import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scanner_core import detect_document  # noqa: E402

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
spec = json.loads((FIX / "expected_corners.json").read_text())
tiles = []
for name, case in spec["cases"].items():
    img = cv2.imread(str(FIX / f"{name}.jpg"))
    t = time.perf_counter()
    d = detect_document(img)
    ms = (time.perf_counter() - t) * 1000
    err = "-"
    if case["found"] and d.found:
        err = f"{np.linalg.norm(d.corners - np.float32(case['corners']), axis=1).max():.1f}px"
    print(f"{name:22s} expected={case['found']!s:5} found={d.found!s:5} max_err={err:>8} {ms:5.1f}ms")
    vis = img.copy()
    cv2.polylines(vis, [d.corners.astype(np.int32)], True, (0, 255, 0) if d.found else (0, 0, 255), 8)
    for i, p in enumerate(d.corners.astype(int)):
        cv2.circle(vis, tuple(p), 22, (255, 120, 0), -1)
        cv2.putText(vis, "TL TR BR BL".split()[i], tuple(p + [-18, 8]), 0, 0.8, (255, 255, 255), 2)
    vis = cv2.resize(vis, (300, 400))
    cv2.putText(vis, name, (5, 20), 0, 0.55, (0, 0, 255), 2)
    tiles.append(vis)
if len(sys.argv) > 1:
    cv2.imwrite(sys.argv[1], np.vstack([np.hstack(tiles[:4]), np.hstack(tiles[4:8])]))
