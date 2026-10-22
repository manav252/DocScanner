# scanner_core

Reference OpenCV pipeline for the document scanner. The backend `/process`
endpoint uses it directly, and the Flutter (native + web) implementations are
tested against the same fixtures in `../shared/test_fixtures`.

| Module | What it does |
|---|---|
| `detect.py` | downscale → gray → blur → Canny → dilate → contours → largest convex quad → order TL,TR,BR,BL → sub-pixel side refinement; CLAHE second pass for low contrast; clipped-corner recovery; full-frame fallback |
| `warp.py` | perspective correction to a flat rectangle |
| `filters.py` | original, grayscale, B&W (shadow-normalised adaptive threshold), magic color; rotate, crop |
| `smoothing.py` | `CornerSmoother` (EMA + snap on big moves + hold on misses), `StabilityTracker` (auto-capture trigger) |
| `pipeline.py` | `scan()` one-shot detect → warp → filter → rotate, plus image encode/decode |

```bash
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
.venv/bin/python tests/make_fixtures.py        # regenerate test photos + expected corners
.venv/bin/python -m pytest -q                  # 79 tests
.venv/bin/python tests/debug_detect.py         # per-fixture corner error and timing
.venv/bin/python tests/render_results.py ../docs/stage1_results.jpg
```
