"""Detection success rate per hard case (Python reference detector).

A photo counts as a success when the page is found and every corner is within
1 % of the photo diagonal (20 px on 1200x1600) of the true corner.

"Whole frame" counts results that are (nearly) the photo's own border: a
false page.

Run:  python tests/eval_hard_cases.py [--set scenes] [--json out.json]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

from scanner_core import detect_document, order_corners

FIXTURES = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
SETS = {"hard": ("hard", "hard_cases.json"), "scenes": ("scenes", "scene_cases.json")}
HARD = FIXTURES / "hard"


def whole_frame(corners, w, h) -> bool:
    c = np.float32(corners)
    return cv2.contourArea(c) > 0.9 * w * h


def evaluate(which: str = "hard") -> dict[str, dict]:
    folder, index = SETS[which]
    HARD = FIXTURES / folder
    spec = json.loads((HARD / index).read_text())
    w, h = spec["image_size"]
    tol = 0.01 * np.hypot(w, h)
    out = {}
    for case, items in spec["cases"].items():
        ok, errs, frame = 0, [], 0
        for it in items:
            det = detect_document(cv2.imread(str(HARD / it["file"])))
            truth = order_corners(np.float32(it["corners"]))
            err = float(np.linalg.norm(det.corners - truth, axis=1).max()) if det.found else float("inf")
            ok += int(err < tol)
            frame += int(det.found and whole_frame(det.corners, w, h))
            errs.append(err)
        found = [e for e in errs if e != float("inf")]
        out[case] = {
            "success": ok,
            "total": len(items),
            "median_error_px": round(float(np.median(found)), 1) if found else None,
            "whole_frame": frame,
        }
    return out


if __name__ == "__main__":
    which = sys.argv[sys.argv.index("--set") + 1] if "--set" in sys.argv else "hard"
    res = evaluate(which)
    for case, r in res.items():
        print(f"{case:15s} {r['success']:2d}/{r['total']}  median error {r['median_error_px']}  whole frame {r['whole_frame']}")
    if "--json" in sys.argv:
        Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(res, indent=1))
