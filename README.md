# DocScanner

**Code:** https://github.com/manav252/DocScanner

| Live | |
|---|---|
| Website | https://manav252.github.io/DocScanner/ |
| Web app (try it) | https://manav252.github.io/DocScanner/app/ |
| Backend API | https://docscanner-api-vwgz.onrender.com ([health](https://docscanner-api-vwgz.onrender.com/health), [API docs](https://docscanner-api-vwgz.onrender.com/docs)) |

> **How it works, technically:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains the whole
> system end to end (OpenCV pipeline, offline storage, JWT auth, sync protocol, deployment, glossary).

A document scanner in the spirit of Adobe Scan / CamScanner: one Flutter app for
**Android, iPhone and the web** (your Mac's webcam works in the browser), an optional
**FastAPI** backend for backup and sync, and a showcase **website**.

**Every feature works without an account.** Scans stay on your device; signing in
only adds backup and sync.

- Live page outline, auto-capture when steady, spoken and vibration guidance (optional)
- Switch camera, flashlight, low-light and "Move closer" hints; **upload a photo** if there is no camera
- Corner editor: drag corners or edges, keyboard arrows, loupe, *Use full photo*, *Rotate*
- Filters with before/after compare: Original, Grayscale, Black & White, Magic Color
- Multi-page: reorder (drag or *Move earlier/later*), rotate, crop, retake, delete with *Undo*
- **Edit / Markup**: text, pen, highlighter, eraser, saved signature, rectangle, arrow, line,
  whiteout; undo/redo; editable until export, then burned into the PDF/JPG
- Text recognition in **English and Hindi** (ML Kit on phones, Tesseract.js on the web):
  *Copy text*, searchable PDFs, "No text found on this page" instead of noise
- Import photos and PDFs; export PDF or JPG (download, share sheet)
- Library with search; delete is instant with **Undo**; English and Hindi interface; Simple Mode; light, dark, high contrast;
  text up to 200 %; screen readers and keyboard (WCAG 2.2 AA checked, see `docs/TESTING.md`)
- **Backup without an account**: Settings › *Export all documents (ZIP)* and *Import backup*;
  Settings also shows how much space your documents use
- Web app is **installable** ("Add to Home Screen") and works **offline** after the first visit
- **Accounts, backup and sync** across devices through the hosted backend

## Architecture in one minute

```
Browser / phone (works fully offline)          Production hosting (free tiers)
┌───────────────────────────────────────┐      ┌─────────────────────────────────────┐
│ Flutter app (Dart, Riverpod)          │      │ GitHub Pages: website + web app     │
│  · OpenCV page detection              │ HTTPS│ Render: FastAPI in Docker (uvicorn) │
│    (opencv_dart / opencv.js worker)   │◄────►│  ├─ Neon PostgreSQL: users, docs    │
│  · OCR: ML Kit / Tesseract.js         │ JWT  │  └─ Cloudflare R2 (S3): page images │
│  · Files / IndexedDB local store      │      └─────────────────────────────────────┘
│  · PDF export, service worker (PWA)   │
└───────────────────────────────────────┘
```

| Layer | Technology |
|---|---|
| App | Flutter 3.47 / Dart 3.13, Riverpod 3, gen-l10n (English + Hindi) |
| Computer vision | OpenCV: Canny edges → contours → `approxPolyDP` quadrilateral → sub-pixel line fit → perspective warp |
| OCR | Google ML Kit (phones), Tesseract.js (web); invisible text layer makes PDFs searchable |
| Local storage | Key-value store: files on phones, IndexedDB on the web; offline-first |
| Backend | FastAPI (Python 3.12), SQLAlchemy async + asyncpg, Alembic migrations |
| Auth | Argon2id password hashes, JWT access (60 min) + refresh (30 days) tokens |
| Sync | Change cursor (Postgres sequence), optimistic concurrency (`base_version`, 409), tombstones |
| Storage | PostgreSQL (metadata, JSONB pages) + S3-compatible bucket (images) |
| Deploy | GitHub Actions → GitHub Pages; `render.yaml` Blueprint → Render (Docker); Neon; Cloudflare R2 |

Full explanation with diagrams: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

```
DocScanner/
├── start.sh          One command: backend + web app + website
├── app/              Flutter app (android, ios, web)
│   ├── lib/features/     home, capture (scanner), corners, editor, markup, library, settings, account
│   ├── lib/imaging/      OpenCV pipeline: opencv_dart (phones), opencv.js in a worker (web); markup model
│   ├── lib/data/         models, local storage, page rendering, sync
│   ├── lib/services/     camera, API client, OCR, import/export
│   ├── web/              opencv.js, Tesseract.js (+eng, hin), pdf.js: self-hosted, works offline
│   ├── tool/strings.py   all UI strings (English + Hindi) → lib/l10n
│   └── test/, test_js/   Dart and Node tests
├── backend/          FastAPI + Postgres + S3 storage (MinIO locally via Docker Compose; Neon + R2 in production)
├── scanner_core/     Python reference of the detector (also used by the backend)
├── shared/           Test photos, expected corners, detector parameters (shared by all 3 detectors)
├── website/          Showcase site: Home, How it works (live pipeline), Test results, Features
├── tools/            serve.py, run_tests.sh, collect_results.py, audit/ (axe, Lighthouse, screenshots)
└── docs/             FEATURE_AUDIT, TECH_DECISIONS, TESTING, CHANGES, testing/ reports
```

## Quick start (Mac): one command

Needs: Flutter 3.47 (Dart 3.13), Python 3.12, and Docker Desktop (Docker is optional:
without it everything except backup/sync works).

```bash
./start.sh
```

Then open:

- **http://localhost:8080/**: the website (screenshots, *How it works*, test results)
- **http://localhost:8080/app/**: the app (`/app/?demo=1` uses sample pages instead of a camera)
- http://localhost:8000/docs: the backend API

`REBUILD=1 ./start.sh` rebuilds the web app after code changes; `PORT=9000 ./start.sh`
changes the port. Ctrl+C stops the web server; `cd backend && docker compose down`
stops the backend.

First-time backend setup (only for the backend tests and the demo account):

```bash
cd backend
cp .env.example .env
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt -e ../scanner_core
.venv/bin/python scripts/seed_demo.py     # optional demo account + sample PDF
```

Install Flutter with `brew install --cask flutter` (or the SDK from flutter.dev on
your `PATH`), then `flutter doctor`.

## Using it without an account

Open the app and tap **Scan Document**. Allow the camera, hold the page still and it
is captured; check the corners, tap **Keep scan**, scan more pages, then **Done**.
No camera? Tap **Upload a photo**. Your documents are on the home screen under
*Recent scans* and in **View Documents**.

To back up: **Settings → Back up and sync across devices**, sign in or create an
account. You choose whether documents already on the device are uploaded.

## Run on a physical phone

Find your Mac's Wi-Fi address: `ipconfig getifaddr en0` (e.g. `192.168.1.20`). For
backup, the phone and Mac must be on the same network; in Settings → Back up and sync
use `http://<that address>:8000` as the server.

### Android

1. On the phone: Settings → About phone → tap **Build number** 7 times, then
   Developer options → **USB debugging** on (or **Wireless debugging**).
2. Connect by USB, accept the prompt, then:
   ```bash
   cd app
   flutter devices                 # your phone is listed
   flutter run -d <device-id> --release
   ```
   Wireless: Developer options → Wireless debugging → Pair with code, then
   `adb pair <ip>:<port>` and `adb connect <ip>:<port>`.
3. The first build needs the Android NDK and CMake (Android Studio → SDK Manager → SDK Tools).

### iPhone

1. Install Xcode, then:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   brew install cocoapods
   cd app/ios && pod install
   ```
2. Open `app/ios/Runner.xcworkspace` → Runner → **Signing & Capabilities** → your
   Team (a free Apple ID works) and a unique bundle id.
3. iPhone: Settings → Privacy & Security → **Developer Mode** on. Connect, trust, then
   `cd app && flutter run -d <iphone-id> --release`. Requires iOS 15.5+ (ML Kit).

### Phone browser (no install)

Browsers allow the camera only over **HTTPS**. Start with `HOST=0.0.0.0 ./start.sh`,
then expose it with a tunnel, for example:

```bash
cloudflared tunnel --url http://localhost:8080   # https://<random>.trycloudflare.com/app/
cloudflared tunnel --url http://localhost:8000   # API (only for backup)
```

For backup through the tunnel, add the web tunnel's URL to `DOCSCANNER_CORS_ORIGINS`
in `backend/.env` and restart the API.

## Tests

```bash
tools/run_tests.sh                 # everything; writes website/data/test-results.json
```

Or one suite at a time:

```bash
cd app && tool/host_test.sh                      # Flutter/Dart incl. native OpenCV (218 with the backend running)
cd app/test_js && npm install && npm test        # opencv.js detector + filters + Tesseract OCR (24)
cd scanner_core && .venv/bin/python -m pytest    # Python reference detector (80)
cd backend && .venv/bin/python -m pytest         # API against Postgres + MinIO (22)
cd tools/audit && npm install && npm run audit   # axe-core + Lighthouse on app and website
cd tools/audit && node flow.mjs                  # full flow in Chrome: no console errors; works offline
cd tools/audit && node perf.mjs --label after    # seeded 14-page document: load, delete, scroll, memory
```

Latest run: **344 passed, 0 failed** (see `docs/TESTING.md`, which also lists the
checks that need a real phone). Lint/format: `dart analyze`, `dart format`,
`ruff check .`, `ruff format --check .`.

`tool/host_test.sh` builds opencv_dart for macOS with CMake + Ninja
(`python3 -m venv ~/development/buildtools && ~/development/buildtools/bin/pip install cmake ninja`);
without full Xcode it uses a small `xcodebuild` stand-in for that run only.

## Online deployment

It is live (links at the top). The website and web app are built by GitHub Actions and
served by GitHub Pages; the backend runs on Render (Docker, `render.yaml`) with Neon
Postgres and Cloudflare R2. The app's server address is set at build time from the
repository variable `API_URL`. All secrets live in Render's environment settings,
none in this repository. The free Render instance sleeps when idle; the app shows
"Waking up the server…" and waits. Setup steps: `docs/DEPLOY.md`.

## Source code on GitHub

**https://github.com/manav252/DocScanner**

```bash
git clone https://github.com/manav252/DocScanner.git
cd DocScanner && ./start.sh
```

## Documentation

- `docs/ARCHITECTURE.md`: **how it works end to end**: components, scan pipeline, storage, API, auth, sync protocol, deployment, glossary
- `docs/TECH_DECISIONS.md`: architecture diagram, scan flow, choices vs alternatives, limitations, viva Q&A
- `docs/TESTING.md`: test results, accessibility audit, manual and phone-only checks
- `docs/PERFORMANCE.md`: what was slow, why, what changed, before/after measurements
- `docs/DEPLOY.md`: how it is deployed: GitHub Pages, Render, Neon, Cloudflare R2 (step by step)
- `docs/FEATURE_AUDIT.md`: the audit this round of work started from
- `docs/CHANGES.md`: every file created or changed in this round

## Troubleshooting

- **`Flutter failed to create a directory at ~/.config/flutter`**: `~/.config` is
  owned by root: `sudo chown -R "$USER" ~/.config`.
- **Camera "not available here" in the browser**: use `localhost` or HTTPS. The app
  offers *Upload a photo* and the demo camera instead.
- **Old version after a rebuild**: the server sends `no-cache` and the app versions its
  worker scripts; reload the page once.
- **Phone can't reach the backend**: use the Mac's LAN address, same Wi-Fi, port 8000;
  `curl http://<address>:8000/health` from another device.

## Known limitations

- Classic edge detection can miss a page on a background of the same colour and
  texture, or a curled page; drag the corners or keep the full photo. No book-page dewarping.
- Printed text only (no handwriting). Tesseract on the web takes ~1-3 s per page.
- OCR word positions stay on the device that ran OCR; synced devices get the text
  (search, copy) and re-run OCR for a positioned PDF text layer.
- The same document edited on two devices: the newer version wins (you are told which).
- Session tokens are stored in app storage, not the OS keychain; use HTTPS outside your LAN.
