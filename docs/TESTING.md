# Testing report

Last full run: **23 Oct 2026**, `tools/run_tests.sh` (the website's *Test results*
page shows the same run, read from the runners' own reports:
`website/data/test-results.json`).

| Suite | Command | Passed | Failed | Skipped |
|---|---|---:|---:|---:|
| Flutter / Dart app (incl. 10 app ↔ backend sync tests) | `cd app && tool/host_test.sh` | 201 | 0 | 0 |
| JavaScript: opencv.js detector, filters, Tesseract.js OCR | `cd app/test_js && npm test` | 24 | 0 | 0 |
| Python `scanner_core` (reference detector) | `cd scanner_core && .venv/bin/python -m pytest` | 80 | 0 | 0 |
| Backend API (real Postgres + MinIO in Docker) | `cd backend && .venv/bin/python -m pytest` | 20 | 0 | 0 |
| **Total** | `tools/run_tests.sh` | **325** | **0** | **0** |

The 10 sync tests run only when the backend answers on `http://localhost:8000`
(`DOCSCANNER_E2E_API`); without it they are reported as skipped, never as passed.

Static checks: `dart analyze` (0 issues), `dart format` at 120 columns (clean),
`ruff check .` and `ruff format --check .` for all Python (clean).

## 1. Automated

What the suites cover, by area:

- **Detection and warp**: 8 shared fixture photos (tilted, low contrast, shadow,
  clutter, strong perspective, narrow receipt, fills the frame, no document) with
  expected corners, checked in Python, Dart (native OpenCV) and JavaScript, and
  cross-checked against the Python reference. Speed: ~20 ms per 720×1280 frame in opencv.js.
- **Photo orientation**: portrait, landscape, EXIF-rotated and very large photos;
  corners stay in original pixels; the warp equals the crop.
- **Corner editor**: fitted mapping, drag, edges, keyboard (Tab, arrows, Shift),
  Reset / Use full photo / Rotate / Confirm / Cancel, "No page edges found".
- **Scanner**: auto-capture once per page, moving page not captured, re-arming,
  Retake, "Move closer", low light, flashlight, switch camera, upload a photo,
  camera denied / missing / busy, spoken and haptic guidance (English, Hindi, off).
- **Editor**: filters (preview cards, compare, apply to all), rotate, crop, reorder by
  drag and by Move earlier/later, delete with Undo, Add pages, rename, export PDF/JPG.
- **Markup**: every item type round-trips JSON; undo/redo; hit testing; eraser;
  rotate and crop transforms; flattening into the exported image; the editor screen
  (labelled tools, keyboard, discard confirmation).
- **OCR**: English and Hindi text found; photos without text give "No text found";
  word confidence and meaningful-text filters; Copy text → Copied; failures with Try again.
- **No account needed**: Home, Documents, search, Settings, first-run guide, Hindi
  interface, all without signing in; backup is opt-in per document.
- **Errors**: server unreachable / 401 / 500 at sign-in, Test connection, backup offline,
  files that are not photos (skipped and named), invalid crop/markup on the server.
- **Navigation**: Home → Documents → document → back.
- **Accessibility**: on Home, Documents, Editor, Markup, Settings, Guide, Backup & sync
  and the scanner (running and error screen), in light, dark and high-contrast themes:
  tap targets ≥ 48 dp / 44 pt, every tappable thing labelled, text contrast ≥ 4.5:1;
  200 % text without overflow; keyboard Tab order and Enter.
- **Backend**: auth, documents CRUD, versions and 409 conflicts, files in MinIO,
  `/process`, PDF download, upload, markup validation and size limits.

### Accessibility audit (web)

`cd tools/audit && npm run audit` (axe-core 4.10, WCAG 2.2 A/AA rules; Lighthouse 12),
report in `docs/testing/a11y-report.json`:

| Page | axe violations | Lighthouse accessibility |
|---|---:|---:|
| Web app: Home, Documents, Settings | 0 | 100 |
| Website: Home, How it works, Test results, Features | 0 | 100 |

Limit: the app draws text on a canvas, so axe cannot measure its colour contrast;
the Flutter guideline tests above cover contrast instead.

## 2. Manual checks on a computer (done in Chrome on macOS)

- Web app at `/app/`: demo camera scan → Keep scan → Done → editor; filters with
  compare; markup (text, pen) saved and shown on the page and thumbnail; rotate keeps
  markup on the content; JPG export contains the markup (checked pixel colours);
  markup synced to the server (checked in Postgres).
- Camera blocked in the browser → "Camera access is off" with Upload a photo.
- Website: How it works on the sample photo (page found, 6 step images); phone width
  (375 px) without horizontal scrolling; Test results page shows the run above.

## 3. Needs a physical phone (not done here)

These depend on phone hardware or system apps that tests and emulators cannot
reproduce faithfully. To check, install the app (README › Run on a physical phone) and:

| Check | How | Expected |
|---|---|---|
| Live detection and auto-capture | Scan a sheet on a desk in normal light | Blue outline follows the page; captures after ~1 s still; "Page captured. Show the next page." |
| Camera focus, flash | Dim room, tap Flashlight on | Torch lights; "Too dark" hint disappears |
| Switch camera | Tap Switch camera | Front camera opens; outline lines up with the page (preview not mirrored) |
| Haptics | Scan a page | Short vibration on "Hold still" and on capture |
| Spoken guidance | Settings → Spoken guidance on; scan | Hears "Move closer" / "Hold still" / "Captured, page 2" (English and Hindi voices installed) |
| ML Kit text (English, Hindi) | Scan printed English and Hindi pages, open Text | Text matches; a photo without text says "No text found on this page" |
| Share sheet | Export → Share or save → Save to Files / Drive | File saved and opens |
| TalkBack / VoiceOver | Turn on the screen reader; scan, edit, export | Every control is announced with its label; captures announced |
| 200 % system font | Largest font size in system settings | Nothing cut off; toolbars wrap or scroll |
| iOS build | `cd app/ios && pod install` then build in Xcode | Builds (new pods: flutter_tts, ML Kit Devanagari) |

## 4. How to re-run everything

```bash
./start.sh                      # backend + web app + website (needed for the sync tests)
tools/run_tests.sh              # all suites; updates website/data/test-results.json
cd tools/audit && npm install && npm run audit   # accessibility audit
```
