#!/usr/bin/env bash
# Run every automated test suite and record the real results for the
# showcase website (website/data/test-results.json) and docs/testing/.
#
#   tools/run_tests.sh
#
# Suites: Flutter/Dart (app), JavaScript (opencv.js + OCR), Python scanner_core,
# backend API (needs Docker: Postgres + MinIO), app<->backend end-to-end sync
# (runs only when the backend answers on http://localhost:8000).
# A suite that cannot run is recorded as "not run" with the reason, never as passed.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT="$ROOT/docs/testing/raw"
mkdir -p "$OUT"
rm -f "$OUT"/*
FLUTTER_BIN=$(dirname "${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}")
export PATH="$FLUTTER_BIN:$PATH"

API=http://localhost:8000
if curl -sf "$API/health" >/dev/null 2>&1; then BACKEND_UP=1; else BACKEND_UP=0; fi

echo "== Flutter/Dart tests"
if [[ $BACKEND_UP == 1 ]]; then export DOCSCANNER_E2E_API=$API; fi
(cd app && tool/host_test.sh --file-reporter "json:$OUT/dart.json" >"$OUT/dart.log" 2>&1)
echo "   exit $?"

echo "== JavaScript tests (opencv.js detector, filters, OCR)"
(cd app/test_js && node --test --test-reporter=spec --test-reporter-destination=stdout \
    --test-reporter=junit --test-reporter-destination="$OUT/js.xml" >"$OUT/js.log" 2>&1)
echo "   exit $?"

echo "== Python scanner_core tests"
(cd scanner_core && .venv/bin/python -m pytest -q --junitxml="$OUT/scanner_core.xml" >"$OUT/scanner_core.log" 2>&1)
echo "   exit $?"

echo "== Backend API tests"
if [[ $BACKEND_UP == 1 ]]; then
  (cd backend && .venv/bin/python -m pytest -q --junitxml="$OUT/backend.xml" >"$OUT/backend.log" 2>&1)
  echo "   exit $?"
else
  echo "backend not running at $API (start it with ./start.sh or docker compose up -d in backend/)" >"$OUT/backend.skipped"
  echo "   not run: backend is not running"
fi

python3 tools/collect_results.py "$OUT" website/data/test-results.json
cp website/data/test-results.json docs/testing/test-results.json
[[ -f docs/testing/a11y-report.json ]] && cp docs/testing/a11y-report.json website/data/a11y-report.json
echo "Results: website/data/test-results.json"
