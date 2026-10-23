#!/usr/bin/env python3
"""Turn raw test reports (Dart JSON reporter, JUnit XML) into one JSON summary.

    python3 tools/collect_results.py docs/testing/raw website/data/test-results.json

Counts come only from the reports the test runners wrote.
"""
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SUITES = [
    ("dart", "Flutter / Dart (app)", "cd app && tool/host_test.sh"),
    ("js", "JavaScript (opencv.js detector, filters, Tesseract.js OCR)", "cd app/test_js && npm test"),
    ("scanner_core", "Python scanner_core (reference detector)", "cd scanner_core && .venv/bin/python -m pytest"),
    ("backend", "Backend API (FastAPI + Postgres + MinIO)", "cd backend && .venv/bin/python -m pytest"),
]


def dart(path: Path) -> list[dict]:
    names, groups, tests, out = {}, {}, {}, []
    for line in path.read_text().splitlines():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = e.get("type")
        if t == "testStart":
            test = e["test"]
            tests[test["id"]] = test
        elif t == "testDone" and not e.get("hidden"):
            test = tests.get(e["testID"], {})
            url = (test.get("url") or test.get("root_url") or "").split("/test/")[-1]
            status = "skipped" if e.get("skipped") else ("passed" if e["result"] == "success" else "failed")
            out.append({"name": test.get("name", "?"), "file": url, "status": status})
    return out


def junit(path: Path) -> list[dict]:
    out = []
    for case in ET.parse(path).getroot().iter("testcase"):
        if case.find("failure") is not None or case.find("error") is not None:
            status = "failed"
        elif case.find("skipped") is not None:
            status = "skipped"
        else:
            status = "passed"
        out.append({"name": case.get("name"), "file": case.get("classname") or case.get("file") or "", "status": status})
    return out


def main() -> None:
    raw, dest = Path(sys.argv[1]), Path(sys.argv[2])
    suites = []
    for key, title, command in SUITES:
        s = {"id": key, "title": title, "command": command}
        report = raw / (f"{key}.json" if key == "dart" else f"{key}.xml")
        skipped = raw / f"{key}.skipped"
        if report.exists() and report.stat().st_size > 0:
            tests = dart(report) if key == "dart" else junit(report)
            s["status"] = "run"
            s["tests"] = tests
            for k in ("passed", "failed", "skipped"):
                s[k] = sum(1 for t in tests if t["status"] == k)
        else:
            s["status"] = "not run"
            s["reason"] = skipped.read_text().strip() if skipped.exists() else "no report was produced (see the log)"
        suites.append(s)
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except Exception:  # noqa: BLE001
        commit = None
    ran = [s for s in suites if s["status"] == "run"]
    summary = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "commit": commit,
        "totals": {k: sum(s[k] for s in ran) for k in ("passed", "failed", "skipped")},
        "suites": suites,
    }
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(summary, indent=1) + "\n")
    t = summary["totals"]
    print(f"passed {t['passed']}, failed {t['failed']}, skipped {t['skipped']}; "
          + ", ".join(f"{s['id']}: {s['status']}" for s in suites))


if __name__ == "__main__":
    main()
