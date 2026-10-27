#!/usr/bin/env python3
"""Write app/build/web/precache.json: every file the offline app needs (run after `flutter build web`).

Each entry is "path?h=<content hash>": the service worker copies a file whose
hash it already has from the previous version's cache instead of downloading
it again, so an update downloads only what changed (a few MB, not ~45 MB).
Leaves out debug symbols, the renderer variants this build does not load and
the plain (no-SIMD) OCR core for very old browsers (fetched if ever used).
"""

import hashlib
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
    if rel.startswith("canvaskit/") and any(k in rel for k in ("skwasm", "wimp", "webparagraph")):
        continue
    if rel == "ocr/tesseract-core-lstm.wasm.js":
        continue
    files.append(rel)
entries = [f"{f}?h={hashlib.sha1((web / f).read_bytes()).hexdigest()[:12]}" for f in files]
(web / "precache.json").write_text(json.dumps(["./", *entries], indent=0) + "\n")
total = sum((web / f).stat().st_size for f in files)
print(f"precache.json: {len(files)} files, {total / 1048576:.1f} MB")
