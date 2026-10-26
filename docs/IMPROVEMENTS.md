# Improvements: phone PDF import, smoothness, detection, OCR, ID cards

Round of 26–27 Oct 2026. Everything is measured on the test sets in this
repository; nothing below was checked on a physical phone (see "Not solved").

## What changed

| Area | Change | Commit |
|---|---|---|
| PDF import on phones | Each PDF page is measured first (9 dpi) and rendered with its long side ≤ 2480 px; runs of same-size pages share one pdf.js pass. Skipped files show why. | `bc20c42` |
| Crop screen | Corners live in a `ValueNotifier` while dragging (only outline, handles and loupe repaint); photo, overlay and loupe in separate `RepaintBoundary`s; photo decoded at screen size, loupe ≤ 2048 px; no edge swipe-back on this screen. | `861daad` |
| Detection | Candidate quads scored by size, border support, squareness and fit; straight edges from outlines recover hidden corners; 4 passes (gray, CLAHE, lighting-normalised, saturation); min page area 4 %. Same in Python, Dart and web. | `17ffea3`, `01d2979` |
| Curved pages | Top/bottom edges traced and fitted; grid warp when they bow, plain perspective warp otherwise. | `bf35d44` |
| Auto-capture | Waits for a sharp frame (variance of the Laplacian). | `bf35d44` |
| OCR | Input enlarged to a 2000 px long side (≤ 3×) on the scan engine; pages shown as Original/Gray/B&W are read from their Magic Color version; little text → second pass (gray + CLAHE) merged; handwriting note. | `1514635` |
| ID card mode | Aadhaar/PAN recognised from card shape + keywords + number patterns; label with Change; editable details; name "Aadhaar Card – date"; never uploaded until approved; export can hide the first 8 Aadhaar digits; B&W keeps photo/signature grey; card pages at JPEG 95. | `1a7f94f`, `596487e` |

## 1. Phone PDF import: root cause

Measured in Chrome with phone emulation by feeding a real file to the file input
and logging the canvases pdf.js created:

| PDF page | Canvas before | Canvas after |
|---|---|---|
| A4 (595 × 842 pt) | 1654 × 2338 (3.9 MP) | 1652 × 2338 (3.9 MP) |
| Photo-sized, from a "photo to PDF" app (3024 × 4032 pt) | **8400 × 11200 (94 MP, ~380 MB)**, 18 s for one page on a desktop | **1860 × 2480 (4.6 MP)** |

Safari's canvas limit is 16.7 MP, and a 2–3 GB phone cannot spare 380 MB, so such
PDFs failed on phones. The error was caught and only the file name was shown
("skipped"); now the reason is shown (password-protected PDF, damaged or
unsupported file). Size limits (20 MB per file), CORS and the cold-start wait
were checked and were not the cause. The file picker filter (`.pdf`) was not
changed; whether every phone picker lists PDFs needs a real-phone check.

## 2. Smoothness

Crop screen, `tools/audit/cropdrag.mjs` (3000 × 4000 photo, 390 × 844 @2x, ~2 s
drag, headless Chrome with the CPU throttled; 3 runs each):

| | Before | After |
|---|---|---|
| CPU 6× slower: p95 frame | 33.4 ms (30 fps) | **16.7–16.8 ms (60 fps)** |
| CPU 6× slower: frames > 33 ms per drag | 5, 9, 14 | **1, 1, 1** |
| CPU 6× slower: long tasks | 1–6 (up to 122 ms) | **none** |
| CPU 4× slower: p95 frame | 16.7–16.8 ms | 16.8 ms |

Delete (card gone in ~54 ms, no stalls), thumbnails (generated once, cached) and
list scrolling (p95 16.7 ms) were already done in the previous round
(`PERFORMANCE.md`). Detection, warp, filters, OCR preparation and (on phones)
PDF building run off the UI thread. The new sharpness check costs 0.06 ms per
640 × 480 frame on the UI thread.

| Web app, first visit, 4G-like network (9 Mbit/s, 60 ms) | Before | After |
|---|---|---|
| Time until usable | 4.1–5.3 s | 4.1–5.5 s |
| Downloaded at start | 2.23 MB | 2.24 MB |

opencv.js, Tesseract.js and pdf.js are not downloaded at start (loaded on first
use). The renderer stays CanvasKit (the WASM renderer needs WasmGC, which older
phone browsers lack).

**APK size: not measured.** The Android SDK is not installed on this Mac, so no
APK was built before or after. No package was added in this round, so the size
should be essentially unchanged; build with `flutter build apk --release
--split-per-abi` to confirm.

## 3. Detection

`shared/test_fixtures/hard`: 8 cases × 12 seeded synthetic photos (1200 × 1600,
fake card data). Success = every corner within 20 px of the truth.

| Case | Before | After (Python = Dart = web) |
|---|---:|---:|
| Hand-held (fingers over corners, shake) | 4 | **12** |
| Plain white page, light table | 12 | 12 |
| Cluttered (cloth, other papers) | 6 | **7** |
| Half shadow | 12 | 12 |
| Handwritten | 12 | 12 |
| Curved page (corners) | 0 | **11** |
| Aadhaar card (small in frame) | 0 | **1** (web 2) |
| PAN card | 2 | **10** |

Curved pages, flattened (bend of the title rule, % of page height, 12 pages):
**3.9 % → 0.55 %** median (worst 0.69 %); none of the 72 flat pages is treated as
curved. Dart and web agree with the Python reference within 6 px on every photo
it gets right; curve fits agree within 4 px. Speed: web 13.3 → 12.7 ms per
720 × 1280 frame, Python 25 ms per HD frame.

Filters on half-shadow pages (left/right paper brightness gap): original 111
levels, Magic Color 1, B&W 0 (already adaptive; unchanged).

## 4. OCR

Fake ID cards read with Tesseract.js (the web engine), fields found exactly:

| Field | Aadhaar before | Aadhaar after | PAN before | PAN after |
|---|---:|---:|---:|---:|
| Name | 2/12 | **9/12** | 11/12 | **12/12** |
| Date of birth | 12/12 | 12/12 | 11/12 | 11/12 |
| Number | 12/12 | 12/12 | 12/12 | 12/12 |

Remaining Aadhaar misses: "Meera **l**yer" (I read as l in this sans-serif),
"Kabirsingh" (space lost), one name not read at all.

**Handwriting.** ML Kit (phones) handles neat handwriting moderately, Tesseract
(web) poorly; the app now says so. Options, none added:

| Option | Where | Size / cost |
|---|---|---|
| TrOCR-small (handwritten) | on device (ONNX) | ~61 M parameters, ~234 MB in float ([Qualcomm AI Hub](https://aihub.qualcomm.com/models/trocr)); smaller only if quantised |
| Google Cloud Vision `DOCUMENT_TEXT_DETECTION` | cloud | first 1,000 pages/month free, then $1.50 per 1,000 ([pricing](https://cloud.google.com/vision/pricing)) |
| Azure AI Document Intelligence, Read | cloud | about $1.50 per 1,000 pages; small free tier ([pricing](https://azure.microsoft.com/pricing/details/ai-document-intelligence/)) |

The cloud options send the image off the phone, which conflicts with the
offline/private design; they would need an explicit opt-in.

## 5. ID card mode

| Check | Result |
|---|---|
| Card type from real OCR output (24 fake cards + 6 ordinary pages) | **30/30** |
| Fields extracted from that text: name / DOB / number | 19 / 23 / 24 of 24 |
| B&W photo/signature strip found (12 PAN cards / 72 ordinary pages) | 12 / 0 |
| Signature vs original grey (correlation), plain B&W → card B&W | 0.87 → **1.00** |
| Photo grey levels, plain B&W → card B&W | 2 → **78** |

Rules: on a card-shaped page (1.58 : 1 ± 8 %), the card's number pattern plus a
keyword fragment or a date ("overnment of India" still counts); a 16-digit bank
card number is not an Aadhaar number; a page of paragraphs is never a card.
Front and back scanned into one document export as one PDF.

## 6. iPhone web app (27 Oct)

Checked in WebKit 18.0 (Safari's engine, Playwright, iPhone 13 emulation:
`tools/audit/iphone_flow.mjs`) and Chrome; not on a physical iPhone.

| Problem | Cause found | Fix | Result |
|---|---|---|---|
| Choosing a PDF did nothing | The file picker counted the window regaining focus as "cancelled" if no file arrived within 0.5 s; iPhone Safari regains focus as the Files sheet closes, before the PDF is copied in | Picker waits for the file (cancel still works) | Needs your check on an iPhone (focus timing is iOS-only) |
| PDF failed to open on Safari before 18.2 | pdf.js 6.2 "modern" build uses `Uint8Array.toHex` on every PDF, and other new APIs | pdf.js "legacy" build of the same release | WebKit 18.0: failed 3/3 → works 3/3, also on the live site |
| Crashes while scanning | Not reproduced (desktop WebKit has no iPhone memory limit); no leak found; memory use reduced | OCR shut down 8 s after use (~200 MB); no OCR while the camera is open; photos ≤ 3000 px; image cache 32 MB | Tab peak (median of 3): 12 MP photo 634 → 539 MB, corners 488 → 422 MB, scanning ≈ same |
| Scanner busy on a slow phone | Each camera frame drawn full-size onto a read-back canvas (28 % of the main thread) | Browser shrinks the frame (`createImageBitmap` resize) | Main thread busy at CPU 6×: 72 % → 58 % |
| Old iPhones (before iOS 16.4) | No OffscreenCanvas: scanning/importing cannot work | Clear notice on Home | — |

## Not solved / not verified

- **iPhone crashes**: not reproduced here; memory and main-thread work reduced.
  Which iPhone, iOS version and screen (camera, after Keep scan, export...) would
  narrow it down.
- **Real phones**: PDF import on Android Chrome and iPhone Safari, crop-screen
  frame times on a low-end phone, ML Kit OCR on cards: not checked on devices.
- **APK size**: not measured (no Android SDK here).
- **Cluttered** (7/12): a page on a checked cloth next to similar papers can still
  lose to a neighbouring shape.
- **Aadhaar detection** (1–2/12): the synthetic card has an orange header and red
  footer that blend into a brown table in grayscale; the detector cuts them off
  (24–40 px error). Colour edges fixed it but cost other cases, so not kept.
- **Curved page** (1/12) where a corner of the bowed page is misplaced.
- **Skin-colour masking** was not kept (wood tables are skin-coloured); straight-edge
  quads handle fingers instead.
- **OCR**: look-alike letters (I/l) and lost spaces; handwriting not solved.
- **B&W photo strip** is found from tones, so a card whose photo is very light or
  missing keeps full B&W.
- The test photos are synthetic; real photos (glare, laminate reflections, motion)
  may score differently.

## Re-run

```bash
cd scanner_core && ../backend/.venv/bin/python tests/eval_hard_cases.py      # detection (Python)
cd app && tool/host_test.sh test/imaging/hard_cases_test.dart                # Dart, writes detection-after-dart.json
cd app/test_js && npm test                                                   # web, writes detection-after-web.json
cd app/test_js && node eval_ocr.js --pipeline before|after                   # OCR on the fake cards
cd tools/audit && node cropdrag.mjs http://localhost:8080/app/ --cpu 6       # crop screen frames
```
