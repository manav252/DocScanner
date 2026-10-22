# Feature audit

Audit of `~/DocScanner` at commit `d7f7a26` (before this round of work), against the
requested feature list. Status meanings:

- **Complete**: implemented and verified by automated tests and/or a browser run.
- **Partial**: implemented but missing part of what was asked, or has a known bug.
- **Mocked**: a stand-in exists (clearly labelled), not the real thing.
- **Missing**: not implemented.
- **Unverified**: implemented but never run where it matters (e.g. no physical phone).

## Repository overview

| Part | Path | Entry point | Tests |
|---|---|---|---|
| Flutter app (Android, iOS, web) | `app/` | `lib/main.dart` → `LibraryPage` | `app/test` (Dart, `tool/host_test.sh`), `app/test_js` (Node) |
| Web pipeline (opencv.js worker) | `app/web/opencv/` | `scanner_worker.js` | `app/test_js/scanner.test.js` |
| Python reference pipeline | `scanner_core/` | `scanner_core/detect.py` | `scanner_core/tests` (pytest) |
| Backend (FastAPI, Postgres, MinIO) | `backend/` | `app/main.py`, `docker-compose.yml` | `backend/tests` (pytest, real containers) |
| Shared fixtures | `shared/` | 8 photos + expected corners | used by all suites |

Web app launch: `flutter build web`, then serve `app/build/web` (e.g. `python3 -m http.server 8090`).
Backend: `docker compose up -d` in `backend/`.
State management: Riverpod 3. Storage: files (mobile) / IndexedDB (web) through `KeyValueStore`.

## Status by feature

| Feature | Status | Notes |
|---|---|---|
| Live edge detection + outline | Complete | Native (`opencv_dart`) and web (`opencv.js` worker); verified with demo camera in browser; tests on fixtures |
| Auto-capture when steady | Complete | `CaptureController` + `StabilityTracker`; re-arms only for a new page |
| Manual capture, flashlight, low-light hint | Complete | Flashlight only where the camera exposes torch |
| Camera switch (front/back) | Missing | Always uses the back camera |
| Corner editor with loupe | **Partial (bug)** | User report: confirmed crop does not match the selection; photo not fitted (shifted left, bottom cut off). Likely cause: image orientation / size mismatch between the decoder that measures the photo and the one that displays it (EXIF orientation, very large photos). No Rotate / Reset / keyboard control |
| Perspective warp | Complete | Same corners used for warp; tested on fixtures |
| Filters (Original, Grayscale, B&W, Magic Color) | Complete | Python/Dart/JS parity tests. No before/after compare |
| Rotate, rectangular crop | Complete | |
| Multi-page: add, reorder, delete, retake | Partial | Reorder by drag only (no move up/down buttons); delete has no Undo |
| Import photos / PDF | Complete (picker unverified in browser) | Flow unit-tested; file dialog not driven in automated runs |
| Export PDF / JPG, share / download | Complete | Web download verified (intercepted); share sheet on phones unverified |
| Library: search, rename, delete | Partial | Search includes OCR text; no local vs synced marker; no "last modified" label; no download from list |
| OCR | Partial | ML Kit (mobile, unverified) / Tesseract.js (web, verified). No confidence filtering for ML Kit; garbage can appear as text; copy button is icon-only; English only |
| Searchable PDF | Complete | Invisible text layer verified with pdf.js |
| Markup (text, pen, signature, shapes, whiteout, undo) | Missing | |
| Works without an account | Partial | Everything already works signed out (home = library), but sign-in sits behind an unlabeled cloud icon; no "Recent scans" home; no explicit offer to upload local documents when signing in (it uploads silently) |
| Sync status / pending / conflicts | Partial | Status shown; pending count and conflicts not shown |
| Settings | Partial | Server URL, server processing, auto-OCR only. No theme, text size, Simple Mode, language, spoken guidance |
| Dark mode | Partial | Follows system; no toggle; no high-contrast mode |
| First-run guide | Missing | |
| i18n (English, Hindi) | Missing | Strings are hard-coded English |
| Accessibility (WCAG 2.2 AA) | Partial / unaudited | Many icon-only buttons (tooltips exist), no semantics audit, no spoken guidance, no reduced-motion handling |
| Demo camera | Mocked (labelled) | Plays bundled sample photos; title says "Scan (demo)" |
| Backend: auth, documents, PDF, upload, /process | Complete | 19 API tests against real Postgres + MinIO |
| Offline-first sync | Complete | 9 two-device end-to-end tests |
| Showcase website | Missing | |
| Interactive "how it works" pipeline view | Missing | |
| Tech decisions document | Missing | |
| Physical Android / iPhone | Unverified | No Android SDK or Xcode on this Mac |
| Real webcam in browser | Unverified by automation | The automation browser blocks cameras; needs a manual check in Chrome/Safari |
| GitHub upload | Missing | `gh` installed; login not completed |

## Plan

1. **Crop editor fix** (highest priority): normalise every photo once when it enters the app
   (apply EXIF orientation, cap very large photos, re-encode without EXIF) so the editor,
   the warp and the PDF all see identical pixels; fit/centre the photo; add Use full photo,
   Reset, Rotate, Confirm, Cancel, keyboard corner movement; tests with portrait,
   landscape, EXIF-rotated and very large photos.
2. **Guest-first**: new Home (Scan, Import Photos, Import PDF, View Documents, Recent scans,
   offline/sync status, first-time guidance); sign-in only from Settings as "Back up and
   sync"; offer to upload existing documents; show pending changes and conflicts.
3. **OCR**: confidence filtering for both engines, "No text found on this page",
   "Copy text" → "Copied", progress and clear errors, English/Hindi.
4. **Markup**: editable annotation layer per page (text, pen, highlighter, eraser,
   signature, rectangle, arrow, line, whiteout, undo/redo), flattened on export.
5. **UI/UX + accessibility**: theme (light/dark/high contrast), text size, Simple Mode,
   labelled buttons, move up/down + Undo delete, filter before/after, 3-screen guide,
   spoken + haptic scan guidance, reduced motion, English/Hindi strings.
6. **Showcase website** started with one command: home, live demo (the Flutter web app),
   interactive pipeline steps using the real opencv.js pipeline, real test results, features.
7. **docs/TECH_DECISIONS.md**, tests for all of the above, axe audit, lint, README, report.
