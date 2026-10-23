#!/usr/bin/env python3
"""Summarise alternating before/after runs of perf.mjs (docs/testing/perf-<prefix>-*.json).

    python3 tools/audit/summarize_perf.py [ab|abm]
Prints median and range per metric and writes docs/testing/perf-summary-<prefix>.json.
"""

import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "docs" / "testing"

METRICS = {
    "Home: titles on screen (ms)": lambda r: r.get("homeLoadMs"),
    "Home: longest task (ms)": lambda r: max(r.get("homeLongTasks") or [0]),
    "Home: worst frame (ms)": lambda r: (r.get("homeFrames") or {}).get("max"),
    "Delete: card gone after (ms)": lambda r: r.get("deleteCardGoneMs"),
    "Delete: worst frame (ms)": lambda r: (r.get("deleteFrames") or {}).get("max"),
    "Delete: frames over 50 ms": lambda r: (r.get("deleteFrames") or {}).get("over50ms"),
    "Delete: longest task (ms)": lambda r: max(r.get("deleteLongTasks") or [0]),
    "Scroll: p95 frame (ms)": lambda r: (r.get("scroll") or {}).get("p95"),
    "Scroll: worst frame (ms)": lambda r: (r.get("scroll") or {}).get("max"),
    "JS heap after 5 opens of the 14-page document (MB)": lambda r: r.get("heapAfter5OpensMB"),
}


def load(side: str, prefix: str) -> list[dict]:
    runs = []
    for p in sorted(root.glob(f"perf-{prefix}-{side}-*.json")):
        r = json.loads(p.read_text())
        if not r.get("error"):
            runs.append(r)
    return runs


def stats(values: list) -> dict | None:
    v = [x for x in values if isinstance(x, (int, float))]
    if not v:
        return None
    return {"median": round(statistics.median(v), 1), "min": min(v), "max": max(v), "n": len(v)}


def main() -> None:
    import sys

    prefix = sys.argv[1] if len(sys.argv) > 1 else "ab"
    before, after = load("before", prefix), load("after", prefix)
    out = {"runs": {"before": len(before), "after": len(after)}, "metrics": {}}
    print(f"runs: before {len(before)}, after {len(after)}")
    print(f"{'metric':52} {'before median (range)':>26} {'after median (range)':>26}")
    for name, f in METRICS.items():
        b, a = stats([f(r) for r in before]), stats([f(r) for r in after])
        out["metrics"][name] = {"before": b, "after": a}

        def fmt(s):
            return "-" if s is None else f"{s['median']} ({s['min']}-{s['max']})"

        print(f"{name:52} {fmt(b):>26} {fmt(a):>26}")
    (root / f"perf-summary-{prefix}.json").write_text(json.dumps(out, indent=1) + "\n")


if __name__ == "__main__":
    main()
