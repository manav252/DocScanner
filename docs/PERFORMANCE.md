# Performance

What was slow, why, what changed, and the measurements before and after.
Every number here comes from a script in this repository; how to re-run them is
at the end.

## How it was measured

- **Web app, headless Chrome 155 on an Apple M1 (GPU: Metal)**, `tools/audit/perf.mjs`.
  The script seeds the app's own IndexedDB with 12 documents: a 14-page document
  called "CWT" plus 11 smaller ones, 41 pages and ~98 MB in total. Every page has a
  source photo (3024×4032, ~1 MB), a flattened and a rendered page (2400×3200) and
  a thumbnail, the same files the app stores.
  It then measures: home screen load, deleting "CWT" from the Documents list
  (time until the card is gone, frame intervals via `requestAnimationFrame`, long
  tasks via `PerformanceObserver`), scrolling the list, and the JS heap.
- **Before vs after**: the app as it was before this round (commit `19dfe66`) and
  the current app were built the same way and measured **alternately, 5 times
  each**, so machine noise affects both equally. Medians and ranges below.
- **PDF size**: `app/tool/pdf_size_test.dart` runs 10 photos through the real
  native pipeline (detect → flatten → Magic Color → PDF).
- **No unhandled errors / offline**: `tools/audit/flow.mjs` runs the whole flow in a
  fresh browser profile and records every console error, then shuts the server
  down and checks the app still loads and scans.

Headless Chrome on a desktop is faster than a mid-range phone. The relative
changes carry over; absolute times on a phone will be higher. Measuring on real
phones (Flutter DevTools, Android Studio profiler) is listed in `docs/TESTING.md`
as a phone-only check.

## 1. Lag when deleting a document

**What happened.** Deleting asked for confirmation, then deleted every file of
every page (source, flat, render, thumbnail) before the list changed. The change
event then made the list re-read and decode *every* document record, and the
list items had no keys: when the first card disappeared, each remaining card's
widget state (its loaded thumbnail) moved to a different document and every
thumbnail on screen was loaded and decoded again.

**Profiling.** A CPU profile of the delete on a profile build shows the remaining
work in our own Dart code is under 5 ms. The frozen frames were browser-side
work (image decoding, raster), triggered by the whole list reloading.

**Changes.**
- The card folds away at once (fade + collapse, 220 ms, none with reduced motion).
  "Document deleted" with **Undo** is shown for 5 seconds; only then are the files
  removed, in the background (`lib/features/library/delete_controller.dart`).
- If the background delete fails, the card comes back and the snackbar says
  "Couldn't delete “…”. It has been put back."
- The document record is deleted before its images, with a small journal of
  pages being deleted. An interrupted delete leaves no half-deleted document, and
  the startup pass removes leftover files. A page that is still being saved is
  never touched (it is not in the journal).
- The list loads all records once, then re-reads **only the document that
  changed**. A test counts the reads: at most 3 after renaming one of 20 documents.
- List items are keyed by document id and built lazily (`ListView.builder`), so
  removing one card does not rebuild or re-decode the others.
- A collapsed card is dropped from the lazy list once it has folded away. A
  zero-height item at the top of a lazy list gets skipped, and the test caught
  Undo not bringing the card back.

## 2. Thumbnail stuck on a spinner

**Why it never resolved.** The image loader returns "no data" when a page has
no stored thumbnail, for example after a save interrupted between writing the
document and its preview. The card treated "no data" as "still loading", so it
spun forever. Nothing retried, and there was no timeout.

**Changes** (`lib/data/thumbnails.dart`, `lib/features/common/page_image.dart`):
- Thumbnails are made once, when a page is rendered (360 px JPEG, quality 80,
  ~17 KB), and stored separately. Lists never decode full pages.
- Read through an in-memory cache (400 entries) that hands back the *same bytes*,
  so Flutter's image cache also hits, with an 8-second timeout.
- A missing thumbnail is rebuilt from the rendered page (one at a time) and saved.
- If there is no image at all, or storage does not answer in time, the card shows
  a document icon with the name. It is never an endless spinner.
- A background pass a few seconds after start rebuilds missing thumbnails for
  existing documents.
- The preview reports its state to screen readers ("Loading page preview",
  "Page preview", "Preview not available"), which also lets the scripts measure it.

## 3. General smoothness

- **Full-size pages decoded at display size**: a 2400×3200 page shown 400 px wide
  was decoded at full resolution (~30 MB of pixels). It is now decoded at about
  the displayed width, in 256 px steps.
- **Heavy work off the UI thread**: image work (decode, warp, filters) already ran
  in a web worker (opencv.js) or a background isolate (phones), and OCR in
  Tesseract's worker. PDF building now runs in a background isolate on phones
  (`compute`). The web has no isolates; there the page JPEGs are embedded without
  re-encoding.
- **Progress and Cancel** for export (page by page), import (per file and per PDF
  page), text recognition, and backup export/import.
- **Lazy lists, keyed items, selective listening** as above.
- **Memory**: the JS heap was measured over 20 open/close cycles of the 14-page
  document (table below).
- **Reduced motion**: the new delete animation is instant when the system asks
  for reduced motion.

## 4. Storage and PDF size

Rendered pages were stored and exported at up to 3200 px, JPEG quality 90.
Measured with `tool/pdf_size_test.dart` (10 pages through the real pipeline; the
photos are the test fixtures upscaled to 12 MP with camera-like noise):

| Page size (long side) | JPEG quality | 10-page PDF |
|---|---|---|
| 3200 px (before) | 90 | **13.97 MB** |
| 3200 px | 85 | 10.75 MB |
| 2480 px | 90 | 10.49 MB |
| **2480 px (now)** | **85** | **8.05 MB** (−42 %) |
| 2480 px | 80 | 6.51 MB |

2480 px is ~210 dpi on the long side of A4 (300 dpi across), sharper than the
200 dpi usually used for document scanning. Quality 85 was chosen over 80 to stay
on the safe side for small text; 80 would save another 19 % (not compared visually
in detail). Black & White pages are much smaller (mostly
white). Settings shows how much space the app uses.

## 5. Measurements

All runs: 12 documents, 41 pages, ~98 MB seeded; the 14-page document is
deleted. "Old" = the app before this round (commit `19dfe66`), "new" = now.
Medians, with the range in brackets; *n* = valid runs (runs where headless
Chrome crashed or timed out are left out, never counted as good).

### Delete

| Set | n (old / new) | Card gone after | Worst frame | Longest task |
|---|---|---|---|---|
| A. First baseline, old build only, after opening the 14-page document 5 times | 4 / – | 181–204 ms | **33–217 ms**; stalls of 133–217 ms in 3 of 4 runs | 0–227 ms |
| B. Alternating, fresh profile | 5 / 5 | 164 → **71 ms** (53–82) | 33 → 50 ms | 0 → 54 ms |
| C. Alternating, after opening the document 5 times | 3 / 3 | 185 → **77 ms** (57–84) | 33 → 67 ms | 0 → 60 ms |
| D. Final build (only the deleted card rebuilds), service worker settled | 3 / 1 | 181 → **54 ms** | 50 (33–100) → 33 ms | 54 (50–70) → 0 ms |

What this shows, plainly:
- **The delete responds 2.5–3× faster** in every set (the card is gone in 54–77 ms
  instead of 164–204 ms, and there is no dialog to tap through first).
- **Frame smoothness is noisy in both builds.** The old build sometimes froze for
  133–217 ms (set A) and sometimes did not (sets B, C). Sets B and C showed the new
  build adding one ~55–60 ms frame: every visible card was rebuilding when one
  card started folding away. That was fixed (each card now listens only to its
  own delete state; `_DeletableItem`). The one valid run of the final build
  (set D) had no long task, but **one run is not enough to claim it is fixed**:
  the other four runs of set D, on both builds, were lost to the machine being busy.
- The files are still removed: storage is checked after the Undo window in every run.

### Home screen, scrolling, memory

| Metric | Old | New | n |
|---|---|---|---|
| Home: first titles on screen (repeat visit, same plain server, service worker settled) | 339 ms (310–374) | 381 ms (378–392) | 5 / 5 |
| Home: longest task while loading | 76 ms in every run | none in 3 of 5 runs (52–59 ms in 2) | 5 / 5 |
| Home: thumbnails shown | not measurable (no state) | 431–448 ms | – / 5 |
| Documents list scroll: p95 frame | 16.7 ms | 16.7 ms | 5 / 5 |
| JS heap over 20 open/close cycles of the 14-page document | 25.3 → 28.4 MB | 26.0 → 28.8 MB | 1 / 1 |

- The home screen shows its first titles **~40 ms later** than before, with fewer
  long tasks. The extra time is most likely the service worker answering requests
  on a repeat visit (the price of working offline). That is a small regression,
  reported as one.
- The heap grows by ~3 MB over 20 cycles **in both builds**, slowing down
  (+0.4 MB in the last five), i.e. caches filling, not a leak introduced here.
  The decoded image memory of the renderer (WebAssembly) is not in this number.

### Stuck thumbnail

`tools/audit/thumbcheck.mjs`: a 14-page document whose first page has no stored
thumbnail, home screen after 12 seconds:

| | Old | New |
|---|---|---|
| What the card shows | spinner, still loading | the page preview |
| Thumbnail in storage | no (never retried) | yes (rebuilt from the page) |

Screenshots: `docs/testing/thumb-before.png`, `docs/testing/thumb-after.png`.

### Whole flow, errors, offline

`tools/audit/flow.mjs` on the final build: 11 of 11 steps passed, **0 console
errors, 0 uncaught exceptions**; with the server shut down, the app reloaded from
its offline copy (48 cached files) and the demo camera scanned a page.

## 6. Crop screen (corner dragging)

**What was slow.** Every finger move rebuilt the whole screen (buttons, banner, hint
text) and repainted the full-size photo with the outline, because they shared one
layer. The photo was decoded at full resolution (a 12 MP photo is ~48 MB) to be shown
~360 px wide.

**What changed.** While dragging, the corners live in a `ValueNotifier` inside the
editor: only the outline/handles (`CustomPainter` with `repaint:`) and the loupe
update; the page hears the new corners once, on release. Photo, outline and loupe each
have a `RepaintBoundary`. The photo is decoded at screen size, the loupe's copy at
most 2048 px. The warp still runs only after *Confirm*.

**Bug found while measuring.** On iPhone/iPad/Mac the screen's edge "swipe back"
gesture took drags that started on the left corner handles (they sit in that strip)
and swiped the screen away. The swipe is now off on this screen; Back still works.

`node tools/audit/cropdrag.mjs`: a 3000×4000 photo, phone viewport (390×844 @2x),
~2 s drag of a corner, CPU throttled, 3 fresh runs each:

| | Before | After |
|---|---|---|
| CPU 6× slower: p95 frame | 33.4 ms (30 fps) | **16.7–16.8 ms (60 fps)** |
| CPU 6× slower: frames over 33 ms per drag | 5, 9, 14 | **1, 1, 1** |
| CPU 6× slower: long tasks | 1–6 (up to 122 ms) | **none** |
| CPU 4× slower: p95 frame | 16.7–16.8 ms | 16.8 ms |
| CPU 4× slower: frames over 33 ms | 1–2 | 0–1 |

The first run at 4× had one stall at the start of the drag both before (394 ms) and
after (491 ms): first-use warm-up of the browser, not the drag itself.

## How to re-run

```bash
./start.sh                                           # app at http://localhost:8080/app/
cd tools/audit
node perf.mjs --label mine                           # load, delete, scroll, memory
node perf.mjs --label mem --cycles 20                # memory over 20 open/close cycles
node flow.mjs                                        # full flow: console errors, offline
node thumbcheck.mjs http://localhost:8080/app/ now   # missing thumbnail → rebuilt?
node cropdrag.mjs http://localhost:8080/app/ --label mine --cpu 6   # crop screen drag
cd ../../app && tool/host_test.sh tool/pdf_size_test.dart   # 10-page PDF size
```

Raw results: `docs/testing/perf-*.json`, `flow-report.json`, `thumb-*.png`.
