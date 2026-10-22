# DocScanner app (Flutter: Android, iOS, Web)

Status: complete (Stage 6: OCR + searchable PDFs). Everything from Stage 4 (library, multi-page scanning,
filters, rotate/crop, import, PDF/JPG export, offline storage) plus accounts and
cloud sync with the backend in `../backend`, and optional server-side processing.

Open `/?demo=1` on the web (or pick "Use demo camera" in the scanner menu) to try
the whole flow without a camera. Sign in from the cloud icon in the library.

## Layout
- `lib/imaging/` – image processing, no UI
  - `geometry.dart` – pure-Dart geometry (corner ordering, line fitting…)
  - `document_detector.dart` – platform-neutral `DocumentDetector` interface
  - `native/` – opencv_dart (FFI) pipeline + background-isolate detector (Android/iOS)
  - `web/` – Web Worker client; the pipeline itself is `web/opencv/scanner.js` (opencv.js)
  - `corner_smoother.dart` – live-preview smoothing + auto-capture steadiness
- `lib/services/camera/` – `ScannerCamera`: `camera` plugin (mobile), getUserMedia (web), demo camera
- `lib/features/capture/` – live scanner screen + `CaptureController` (Riverpod)
- `lib/features/corners/` – corner editor (drag corners/edges, loupe)
- `lib/core/providers.dart` – service providers (overridden with fakes in tests)
- `lib/imaging/page_edits.dart` + `native/opencv_filters.dart` / `web/opencv/scanner.js` – filters, rotate, crop
- `lib/data/` – models, `DocumentRepository`, `PageRenderer`, storage (`FileStore` / `IndexedDbStore`)
- `lib/features/library/` – home screen, search, import flow
- `lib/features/editor/` – document editor, filter sheet, crop, export
- `lib/services/export/` – PDF builder, share/download; `lib/services/import/` – file picking, PDF rasterising
- `lib/services/api/api_client.dart` – backend client (token refresh, offline detection)
- `lib/data/sync/` – `SyncService` (push/pull/conflicts) and `SyncController` (when to sync, status)
- `lib/imaging/server_scan_engine.dart` – "Process photos on the server" (falls back to on-device)
- `lib/features/account/` – sign in / create account, sync status, server settings
- `lib/services/ocr/` – OCR: ML Kit (Android/iOS), Tesseract.js via `web/ocr/ocr.js` (web);
  `features/editor/ocr_runner.dart` recognises new/changed pages, export adds an invisible text layer

Each page keeps its original photo, corners and edits (filter, rotation, crop), so
every step stays editable. Rendering: source -warp-> flat -edits-> render -> thumb.
- `test/imaging/` – Dart tests on the shared fixtures in `../shared/test_fixtures`
- `test_js/` – Node tests for `web/opencv/scanner.js`

## Sync

Signed out, everything stays on the device. Signed in (cloud icon in the library),
the app syncs shortly after every change, every 2 minutes, and on "Sync now".
Offline edits are kept and pushed later; if two devices edit the same document,
the newer edit wins. Session tokens are kept in the app's local storage
(files / IndexedDB); a hardened build would move them to the platform keychain.

Phones reach a backend on your Mac at `http://<your-Mac-LAN-IP>:8000` (set it on the
sign-in screen; the Android emulator default is `http://10.0.2.2:8000`). Debug builds
allow plain HTTP on the local network; use HTTPS for anything public.

## Tests
```bash
tool/host_test.sh            # Dart tests incl. native OpenCV (needs cmake+ninja, see below)
DOCSCANNER_E2E_API=http://localhost:8000 tool/host_test.sh test/integration   # sync against the real backend
cd test_js && npm install && npm test   # web (opencv.js) pipeline
```
`tool/host_test.sh` builds opencv_dart's native library for macOS with Ninja. It needs
`cmake` and `ninja` (`python3 -m venv ~/development/buildtools && ~/development/buildtools/bin/pip install cmake ninja`).
On a Mac without full Xcode it puts a tiny `xcodebuild` stand-in (`tool/host_shims/`) on PATH for that run only.

## Run in a browser
```bash
flutter build web && python3 -m http.server 8090 --directory build/web
```
`web/opencv/opencv.js` is opencv.js 4.12.0 (from `@techstark/opencv-js`), `web/pdfjs/` is pdf.js 6.2.108
(used to import PDFs) and `web/ocr/` is Tesseract.js 7.0.0 with English `best_int` data; all are served by the
app itself so the web version works offline.
