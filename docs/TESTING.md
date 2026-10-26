# Testing report

Last full run: **27 Oct 2026**, `tools/run_tests.sh` (the website's *Test results*
page shows the same run, read from the runners' own reports:
`website/data/test-results.json`).

| Suite | Command | Passed | Failed | Skipped |
|---|---|---:|---:|---:|
| Flutter / Dart app | `cd app && tool/host_test.sh` | 239 | 0 | 1 |
| JavaScript: opencv.js detector, filters, Tesseract.js OCR | `cd app/test_js && npm test` | 35 | 0 | 0 |
| Python `scanner_core` (reference detector) | `cd scanner_core && .venv/bin/python -m pytest` | 83 | 0 | 0 |
| Backend API (real Postgres + MinIO in Docker) | `cd backend && .venv/bin/python -m pytest` | 23 | 0 | 0 |
| **Total** | `tools/run_tests.sh` | **380** | **0** | **1** |

The app ↔ backend sync tests run only when the backend API answers on
`http://localhost:8000` (`DOCSCANNER_E2E_API`); in this run the API container was
not started, so they are counted as 1 skipped, never as passed.

Static checks: `dart analyze` (0 issues), `dart format` at 120 columns (clean),
`ruff check .` and `ruff format --check .` for all Python (clean).

## 1. Automated

What the suites cover, by area:

- **Hard detection cases** (`shared/test_fixtures/hard`, 8 cases × 12 seeded synthetic
  photos with fake card data: hand-held, plain white, cluttered, half shadow,
  handwritten, curved, Aadhaar, PAN): success rate per case written to
  `docs/testing/detection-*.json`; Dart and web must match the Python reference
  within 6 px wherever it is right; curved pages must come out flat (title rule
  bend < 1 %) and flat pages must keep the plain warp. See `docs/IMPROVEMENTS.md`.
- **OCR of ID cards**: `app/test_js/eval_ocr.js` (name, DOB, number read exactly);
  enlarged input, contrast retry and merge; the Original filter is read from its
  Magic Color version.
- **ID card mode**: type from real OCR output (30/30), fields, Aadhaar masking,
  card pages re-rendered, sync holds a card back until approved, B&W keeps the
  photo/signature strip grey.
- **PDF import**: page render size capped (a photo-sized page no longer needs a
  94 MP canvas); skipped files say why.
- **Crop screen**: one report per drag, separate repaint layers, no swipe-back.

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
- **Delete and thumbnails** (`delete_and_thumbnails_test.dart`): the card goes in one
  frame with no dialog; Undo brings it back with nothing deleted; without Undo the
  files go after 5 s; a failing delete puts the card back with an error and removes
  no image; a missing thumbnail is rebuilt and cached (same bytes); a page without
  images gives a placeholder with the name, no spinner; storage that never answers
  times out; the repair pass rebuilds thumbnails and removes only journalled leftovers.
- **Large documents**: a 30-page document among 20 lists correctly, and renaming one
  document re-reads at most 3 records (not the library); deleting it removes all
  120 page files.
- **Backup** (`backup_test.dart`): ZIP export (manifest, documents, pages, no
  flattened copies, stored not deflated); import on a new device (text, markup,
  images back, kept on the device); import over existing documents (newer wins,
  sync identity kept); not-a-backup files rejected; cancel.
- **Error screen**: a screen that throws shows "Something went wrong" with Retry,
  and Retry rebuilds it.
- **Hosted backend settings**: `postgres://` URLs get the async driver; CORS origins
  from JSON.

### Browser checks (headless Chrome)

| Script | What it checks | Last result |
|---|---|---|
| `tools/audit/flow.mjs` | The whole flow in a fresh profile: guide, scan 2 pages (demo camera), filters, rotate, markup, text recognition, PDF download (valid `%PDF`), delete + Undo, ZIP backup; **every console error and uncaught exception recorded**; then the server is shut down and the app must reload and scan from its offline copy | 11/11 steps, 0 console errors, 0 uncaught exceptions; offline reload and scan OK |
| `tools/audit/perf.mjs` | Seeded 14-page document: home load, delete, scroll, memory | see `docs/PERFORMANCE.md` |
| `tools/audit/thumbcheck.mjs` | A page with a missing thumbnail: rebuilt, or stuck? | see `docs/PERFORMANCE.md` |
| `tools/audit/audit.mjs` | axe-core + Lighthouse accessibility | see below |

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
| Smoothness on a mid-range phone | `flutter run --profile`, open DevTools › Performance; delete a 14-page document, scroll Documents, open/close a document 10 times | Frames under 16 ms (60 fps) except at most one; memory returns to its level after closing |
| Backup on a phone | Settings › Export all documents (ZIP) › save to Files; delete the app's data; Import backup | All documents back |

## 4. How to re-run everything

```bash
./start.sh                      # backend + web app + website (needed for the sync tests)
tools/run_tests.sh              # all suites; updates website/data/test-results.json
cd tools/audit && npm install && npm run audit   # accessibility audit
```
