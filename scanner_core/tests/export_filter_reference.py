"""Write a flattened test page and the Python output of every filter to
shared/test_fixtures/filters/ (PNG, lossless). The Dart and JS ports compare
their filters against these files.

Usage: python tests/export_filter_reference.py
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scanner_core import Filter, apply_filter, warp_perspective  # noqa: E402

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
OUT = FIX / "filters"
OUT.mkdir(exist_ok=True)
spec = json.loads((FIX / "expected_corners.json").read_text())
img = cv2.imread(str(FIX / "shadow_across.jpg"))
flat = warp_perspective(img, np.float32(spec["cases"]["shadow_across"]["corners"]), max_side=800)
# Add a solid red stamp so colour preservation is covered too.
cv2.rectangle(flat, (420, 30), (590, 70), (40, 40, 200), -1)
cv2.imwrite(str(OUT / "input.png"), flat)
for f in Filter:
    cv2.imwrite(str(OUT / f"{f.value}.png"), apply_filter(flat, f))
print("wrote", sorted(p.name for p in OUT.iterdir()))
