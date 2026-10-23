"""Write the Python detector's output for every fixture to
shared/test_fixtures/python_reference.json. The Dart and JS ports compare
against it to prove they behave the same as this reference implementation.

Usage: python tests/export_reference.py
"""

import json
import sys
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scanner_core import detect_document  # noqa: E402

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
spec = json.loads((FIX / "expected_corners.json").read_text())
out = {}
for name in spec["cases"]:
    d = detect_document(cv2.imread(str(FIX / f"{name}.jpg")))
    out[name] = {"found": d.found, "corners": [[round(float(x), 2), round(float(y), 2)] for x, y in d.corners]}
(FIX / "python_reference.json").write_text(json.dumps(out, indent=2))
print(f"wrote {len(out)} reference results")
