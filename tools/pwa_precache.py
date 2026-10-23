#!/usr/bin/env python3
"""Write app/build/web/precache.json: every file the offline app needs (run after `flutter build web`).

Leaves out debug symbols and the renderer variants this build does not load.
"""

import json
import sys
from pathlib import Path

web = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "app" / "build" / "web")
skip_suffix = (".symbols", ".map", "LICENSE.md", ".LICENSE.txt")
skip_names = {"precache.json", "flutter_service_worker.js", "sw.js", "_probe"}
files = []
for p in sorted(web.rglob("*")):
    rel = p.relative_to(web).as_posix()
    if not p.is_file() or rel.startswith("_probe") or p.name in skip_names or rel.endswith(skip_suffix):
        continue
    # Renderers: the app uses CanvasKit (root and chromium/ builds); skwasm/wimp are for WasmGC builds.
    if rel.startswith("canvaskit/") and any(k in rel for k in ("skwasm", "wimp")):
        continue
    files.append(rel)
(web / "precache.json").write_text(json.dumps(["./", *files], indent=0) + "\n")
total = sum((web / f).stat().st_size for f in files)
print(f"precache.json: {len(files)} files, {total / 1048576:.1f} MB")
