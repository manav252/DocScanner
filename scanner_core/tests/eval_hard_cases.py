"""Detection success rate per hard case (Python reference detector).

A photo counts as a success when the page is found and every corner is within
1 % of the photo diagonal (20 px on 1200x1600) of the true corner.

Run:  python tests/eval_hard_cases.py [--json out.json]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

from scanner_core import detect_document, order_corners

HARD = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures" / "hard"


def evaluate() -> dict[str, dict]:
    spec = json.loads((HARD / "hard_cases.json").read_text())
    w, h = spec["image_size"]
    tol = 0.01 * np.hypot(w, h)
    out = {}
    for case, items in spec["cases"].items():
        ok, errs = 0, []
        for it in items:
            det = detect_document(cv2.imread(str(HARD / it["file"])))
            truth = order_corners(np.float32(it["corners"]))
            err = float(np.linalg.norm(det.corners - truth, axis=1).max()) if det.found else float("inf")
            ok += int(err < tol)
            errs.append(err)
        found = [e for e in errs if e != float("inf")]
        out[case] = {
            "success": ok,
            "total": len(items),
            "median_error_px": round(float(np.median(found)), 1) if found else None,
        }
    return out


if __name__ == "__main__":
    res = evaluate()
    for case, r in res.items():
        print(f"{case:12s} {r['success']:2d}/{r['total']}  median error {r['median_error_px']}")
    if "--json" in sys.argv:
        Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(res, indent=1))
