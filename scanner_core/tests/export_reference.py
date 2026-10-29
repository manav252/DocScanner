"""Write the Python detector's output for every fixture to
shared/test_fixtures/python_reference.json, and for every hard case to
shared/test_fixtures/hard/python_reference.json (and scenes/python_reference.json
for the phone-test scenes). The Dart and JS ports compare
against them to prove they behave the same as this reference implementation.

Usage: python tests/export_reference.py
"""

import json
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scanner_core import detect_document, page_curves  # noqa: E402

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
spec = json.loads((FIX / "expected_corners.json").read_text())
out = {}
for name in spec["cases"]:
    d = detect_document(cv2.imread(str(FIX / f"{name}.jpg")))
    out[name] = {"found": d.found, "corners": [[round(float(x), 2), round(float(y), 2)] for x, y in d.corners]}
(FIX / "python_reference.json").write_text(json.dumps(out, indent=2))
hard = json.loads((FIX / "hard" / "hard_cases.json").read_text())
out_hard = {}
for items in hard["cases"].values():
    for it in items:
        d = detect_document(cv2.imread(str(FIX / "hard" / it["file"])))
        out_hard[it["file"]] = {
            "found": d.found,
            "corners": [[round(float(x), 2), round(float(y), 2)] for x, y in d.corners],
        }
        # The fitted top/bottom edge curves at the true corners (None = straight).
        curves = page_curves(cv2.imread(str(FIX / "hard" / it["file"])), np.float32(it["corners"]))
        out_hard[it["file"]]["curves"] = None if curves is None else [[round(float(v), 3) for v in c] for c in curves]
(FIX / "hard" / "python_reference.json").write_text(json.dumps(out_hard, indent=1))
scenes = json.loads((FIX / "scenes" / "scene_cases.json").read_text())
out_scenes = {}
for items in scenes["cases"].values():
    for it in items:
        d = detect_document(cv2.imread(str(FIX / "scenes" / it["file"])))
        out_scenes[it["file"]] = {"found": d.found, "corners": [[round(float(x), 2), round(float(y), 2)] for x, y in d.corners]}
(FIX / "scenes" / "python_reference.json").write_text(json.dumps(out_scenes, indent=1))
print(f"wrote {len(out)} + {len(out_hard)} + {len(out_scenes)} reference results")
