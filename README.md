# DocScanner

A document scanner in the spirit of Adobe Scan / CamScanner: one Flutter app for
**Android, iOS and the web** (use your Mac's camera in a browser), plus a
**FastAPI** backend for accounts and cloud sync.

- Live camera preview with real-time page detection (outline drawn on screen)
- Auto-capture when the page is steady, manual shutter, flashlight, low-light hint
- Corner editor with draggable corners/edges and a magnifier loupe
- Perspective correction; filters: Original, Grayscale, B&W, Magic Color; rotate; crop
- Multi-page documents: add, reorder (drag), delete, retake pages
- Import photos and **PDFs**; export **PDF** (searchable) or **JPG**; share sheet / download
- Local library with search (titles and recognised text), rename, delete; works offline
- **OCR**: Google ML Kit on phones, Tesseract.js in the browser: searchable PDFs and copyable text
- Accounts + offline-first **cloud sync** between phone and web; optional server-side processing

```
docscanner/
├── app/              Flutter app (android, ios, web)              → app/README.md
│   ├── lib/imaging/      OpenCV pipeline: opencv_dart (mobile), opencv.js worker (web)
│   ├── lib/features/     capture, corners, editor, library, account (Riverpod)
│   ├── lib/data/         models, local storage, rendering, sync
│   ├── lib/services/     camera, API client, OCR, import/export
│   ├── web/              opencv.js, Tesseract.js, pdf.js (self-hosted → offline)
│   └── test/, test_js/   Dart + Node tests
├── backend/          FastAPI + Postgres + MinIO (Docker Compose)  → backend/README.md
├── scanner_core/     Python reference of the OpenCV pipeline (used by the backend)
├── shared/           Test photos + expected corners + detector parameters (all implementations)
└── docs/             Result images
```

The detection algorithm (downscale → gray → blur → Canny → dilate → contours →
largest convex quad → order corners → sub-pixel edge refinement) exists three
times (Python, Dart/native, JS/web). All three are tested against the same photos
and checked against each other; their tuning lives in `shared/detector_params.json`.

## Prerequisites

| | Needed for |
|---|---|
| Flutter 3.47 (Dart 3.13) | the app |
| Docker Desktop | the backend |
| Python 3.12 | backend tests, `scanner_core` |
| Node 20+ | web pipeline tests (`app/test_js`) |
| Android Studio (SDK) or an Android phone | Android |
| Xcode 26 + CocoaPods + an Apple ID | iOS |

Install Flutter: `brew install --cask flutter`, or download the SDK from
flutter.dev and add `<sdk>/bin` to your `PATH`. Then run `flutter doctor`.

## Quick start (Mac, web app + backend)

```bash
cd backend
cp .env.example .env
docker compose up -d --build          # API http://localhost:8000/docs
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -e ../scanner_core
.venv/bin/python scripts/seed_demo.py # optional demo account + sample PDF
```

```bash
cd app
flutter pub get
flutter run -d chrome                 # or: flutter build web && python3 -m http.server 8090 --directory build/web
```

Open the app, allow the camera, and point it at a page. Add `?demo=1` to the URL to
use bundled sample photos instead of a camera. Sign in from the cloud icon to sync.
The web app expects the API on the same host at port 8000; change it on the sign-in
screen if needed.

## Run on a physical phone

First find your Mac's address on the Wi-Fi: `ipconfig getifaddr en0` (e.g. `192.168.1.20`).
The phone and the Mac must be on the same network; on the sign-in screen use
`http://<that address>:8000` as the server. If macOS asks whether to accept incoming
connections for Docker, allow it.

### Android

1. On the phone: Settings → About phone → tap **Build number** 7 times, then
   Developer options → turn on **USB debugging** (or **Wireless debugging**).
2. Connect it by USB and accept the prompt, then:
   ```bash
   cd app
   flutter devices                 # your phone should be listed
   flutter run -d <device-id>      # debug build; add --release for full speed
   ```
   Wireless: Developer options → Wireless debugging → Pair with code, then
   `adb pair <ip>:<port>` and `adb connect <ip>:<port>`.
3. The first build compiles OpenCV's wrapper with the Android NDK and CMake that
   Android Studio installs (SDK Manager → SDK Tools → NDK and CMake).

### iPhone

1. Install Xcode from the App Store, then:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   brew install cocoapods          # or: sudo gem install cocoapods
   ```
2. Open `app/ios/Runner.xcworkspace` in Xcode → Runner target → **Signing &
   Capabilities** → choose your Team (a free Apple ID works) and a unique bundle id.
3. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (restart).
   Connect by cable, trust the computer, then:
   ```bash
   cd app
   flutter run -d <iphone-id>
   ```
   The first time, iOS asks you to trust the developer: Settings → General →
   VPN & Device Management.
4. Requires iOS 15.5+ (ML Kit). The phone's camera and local-network prompts appear
   on first use.

### Phone browser (no install)

Browsers only give web pages the camera over **HTTPS**. Expose both the web app and
the API through HTTPS tunnels, for example:

```bash
cloudflared tunnel --url http://localhost:8090   # web app → https://<random>.trycloudflare.com
cloudflared tunnel --url http://localhost:8000   # API
```

Add the web app's tunnel URL to `DOCSCANNER_CORS_ORIGINS` in `backend/.env`
(`["https://<web-tunnel>", ...]`), restart the API, open the web tunnel on the phone
and set the API tunnel URL as the server when signing in.

## Tests

```bash
cd scanner_core && .venv/bin/python -m pytest -q          # detection, warp, filters (80)
cd backend && .venv/bin/python -m pytest -q               # API against Postgres + MinIO (19)
cd app && tool/host_test.sh                               # Dart, incl. native OpenCV (106)
cd app && DOCSCANNER_E2E_API=http://localhost:8000 tool/host_test.sh test/integration   # 2-device sync
cd app/test_js && npm install && npm test                 # opencv.js pipeline + Tesseract OCR (19)
```

`tool/host_test.sh` builds opencv_dart for macOS with CMake + Ninja
(`python3 -m venv ~/development/buildtools && ~/development/buildtools/bin/pip install cmake ninja`);
on a Mac without full Xcode it uses a small `xcodebuild` stand-in for that run only.

## Troubleshooting

- **`Flutter failed to create a directory at ~/.config/flutter`**: `~/.config` is
  owned by root: `sudo chown -R "$USER" ~/.config`.
- **Camera says "not available here" on the web**: open the app on `localhost` or
  over HTTPS.
- **Phone can't reach the server**: use the Mac's LAN address (not `localhost`),
  same Wi-Fi, port 8000 open; `curl http://<address>:8000/health` from another device.
- **Docker can't pull `minio/minio`**: MinIO stopped publishing images; Compose
  uses the pinned `bitnamilegacy/minio` instead.

## Known limitations

- OCR is English (Latin script); the PDF text layer uses the built-in PDF font, so
  characters outside Latin-1 are dropped from the text layer (the image is unaffected).
- OCR line positions stay on the device that ran OCR; synced devices get the text
  (search, copy) and can re-run OCR for positioned PDF text.
- Session tokens are stored in app storage, not the OS keychain; no rate limiting
  or refresh-token revocation on the server yet. Use HTTPS outside your LAN.
- Edits on the web take a few seconds per page (full-resolution decode in WASM).
