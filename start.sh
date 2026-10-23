#!/usr/bin/env bash
# Start everything with one command:
#   1. the backend (FastAPI + Postgres + MinIO in Docker) — optional, for backup/sync
#   2. a build of the Flutter web app (only when missing or REBUILD=1)
#   3. the showcase website at http://localhost:8080/ and the app at http://localhost:8080/app/
#
#   ./start.sh                 # PORT=8080 by default
#   REBUILD=1 ./start.sh       # rebuild the web app first
#   HOST=0.0.0.0 ./start.sh    # reachable from other devices on your network
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd)
PORT=${PORT:-8080}
HOST=${HOST:-127.0.0.1}

# --- 1. backend (the app works without it; only backup/sync needs it) ---
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "Starting backend (Docker)…"
  (cd backend && docker compose up -d --build) >/dev/null
  echo "  API: http://localhost:8000/docs"
else
  echo "Docker is not running: skipping the backend. Every feature works without it except backup/sync."
fi

# --- 2. Flutter web app ---
FLUTTER=${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}
INDEX=app/build/web/index.html
if [[ "${REBUILD:-0}" == 1 || ! -f $INDEX ]] || ! grep -q '<base href="/app/">' "$INDEX"; then
  if [[ ! -x $FLUTTER ]]; then
    echo "Flutter not found. Install it (README › Setup) or set FLUTTER=/path/to/flutter." >&2
    exit 1
  fi
  echo "Building the web app (about a minute)…"
  # Flutter keeps its config in XDG_CONFIG_HOME when HOME/.config is not writable.
  (cd app && "$FLUTTER" build web --release --no-wasm-dry-run --base-href /app/ \
      --dart-define=ASSET_VERSION="$(date +%s)") | tail -1
fi

# --- 3. website + app ---
echo "Open http://localhost:$PORT/ (website) or http://localhost:$PORT/app/ (the app). Ctrl+C stops the server."
exec python3 "$ROOT/tools/serve.py" --port "$PORT" --host "$HOST"
