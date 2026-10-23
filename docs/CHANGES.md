# Files created or changed in this round

Generated from git (`d7f7a26..HEAD`, 195 files): 85 added, 108 changed, 2 deleted.
Commits: `f8b1cd8` crop fix; `bb439e3` guest-first; `54589aa` OCR; `9ab4457` markup; `490271d` UI redesign; `b175834` accessibility; `786f967` website; `3d39b4c` docs; `151a831` testing/format; `2ba8060` audit.

## (root)

| File | | What |
|---|---|---|
| `.gitignore` | changed | Changed for: audit, crop fix, website |
| `ruff.toml` | added | Python lint/format settings |
| `start.sh` | added | One command: backend (Docker), web app build when needed, website + app server |

## app/analysis_options.yaml

| File | | What |
|---|---|---|
| `app/analysis_options.yaml` | changed | Formatting only (dart format / ruff format) |

## app/android

| File | | What |
|---|---|---|
| `app/android/app/build.gradle.kts` | changed | Changed for: OCR |

## app/assets

| File | | What |
|---|---|---|
| `app/assets/fonts/NotoSans-Bold.ttf` | added | Changed for: markup |
| `app/assets/fonts/NotoSans-Regular.ttf` | added | Changed for: markup |
| `app/assets/fonts/NotoSansDevanagari-Regular.ttf` | added | Changed for: OCR |
| `app/assets/fonts/OFL.txt` | added | Changed for: OCR |

## app/ios

| File | | What |
|---|---|---|
| `app/ios/Podfile` | changed | Changed for: OCR |

## app/l10n.yaml

| File | | What |
|---|---|---|
| `app/l10n.yaml` | added | Changed for: guest-first |

## app/lib

| File | | What |
|---|---|---|
| `app/lib/core/app_settings.dart` | changed | New settings: theme, contrast, text size, Simple Mode, language, speech, OCR language |
| `app/lib/core/l10n.dart` | added | context.l10n helper |
| `app/lib/core/providers.dart` | changed | Camera index provider (switch camera) |
| `app/lib/core/theme.dart` | added | Accessible theme: 48dp targets, focus rings, high contrast, reduced motion, bundled fonts |
| `app/lib/data/document_repository.dart` | changed | Page file snapshot/restore (undo delete) |
| `app/lib/data/image_header.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/data/models.dart` | changed | Backup flag, OCR language/revision, page markup |
| `app/lib/data/page_renderer.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/data/storage/key_value_store.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/data/sync/sync_controller.dart` | changed | Changed for: guest-first, testing/format |
| `app/lib/data/sync/sync_service.dart` | changed | Opt-in backup, conflict titles, markup sync, account preparation |
| `app/lib/features/account/account_page.dart` | changed | Optional sign-in, upload-existing consent, localized errors |
| `app/lib/features/capture/capture_controller.dart` | changed | Photo normalisation, upload path, camera switch, Move closer / next page states, Retake re-arm |
| `app/lib/features/capture/capture_page.dart` | changed | Scanner screen redesign: labelled controls, upload fallback, error screens, hints |
| `app/lib/features/capture/scan_guidance.dart` | added | Spoken + haptic scan guidance, capture announcements |
| `app/lib/features/capture/widgets/live_quad_overlay.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/features/capture/widgets/shutter_button.dart` | changed | Changed for: UI redesign, testing/format |
| `app/lib/features/common/dialogs.dart` | added | Rename and delete dialogs |
| `app/lib/features/common/document_card.dart` | added | Document card and backup badge |
| `app/lib/features/common/page_image.dart` | changed | Page image with live markup overlay |
| `app/lib/features/corners/corner_adjust_page.dart` | changed | Review screen: Reset / Use full photo / Rotate / Confirm / Cancel, no-edges message |
| `app/lib/features/corners/corner_editor.dart` | changed | Corner editor rewrite: fitted mapping, edges, keyboard, loupe, semantics |
| `app/lib/features/diagnostics/detector_diagnostics_page.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/features/editor/crop_page.dart` | changed | Changed for: UI redesign, testing/format |
| `app/lib/features/editor/document_controller.dart` | changed | Markup transforms, setMarkup, undoable page delete |
| `app/lib/features/editor/document_editor_page.dart` | changed | Editor redesign: labelled toolbar, move earlier/later, delete with Undo, Add pages |
| `app/lib/features/editor/export.dart` | changed | Burns markup into exported pages; Hindi PDF font |
| `app/lib/features/editor/export_sheet.dart` | changed | Localized export with platform explanations |
| `app/lib/features/editor/filter_sheet.dart` | changed | Filter preview cards, before/after compare, progress |
| `app/lib/features/editor/ocr_runner.dart` | changed | OCR in the chosen language; re-runs when the page changes |
| `app/lib/features/editor/text_sheet.dart` | changed | Text view: No text found, Copy text → Copied, language, errors |
| `app/lib/features/home/home_page.dart` | added | New Home: main actions, status line, recent scans, first-time help |
| `app/lib/features/library/documents_page.dart` | added | Documents list with search and labelled actions |
| `app/lib/features/library/import_flow.dart` | changed | Normalises imports; skips unreadable files and names them |
| `app/lib/features/library/import_ui.dart` | added | Import with progress into a new document |
| `app/lib/features/library/library_controller.dart` | changed | Changed for: guest-first, testing/format |
| `app/lib/features/library/library_page.dart` | deleted | Replaced by the new Home and Documents screens |
| `app/lib/features/markup/markup_editor_page.dart` | added | Edit / Markup screen: tools, gestures, keyboard, undo/redo, item list |
| `app/lib/features/markup/markup_model.dart` | added | Undo/redo history, hit testing, eraser |
| `app/lib/features/markup/markup_painter.dart` | added | Draws markup; flattens it into images for export |
| `app/lib/features/markup/signature_pad.dart` | added | Draw a signature once, saved on the device |
| `app/lib/features/onboarding/onboarding_page.dart` | added | 3-step skippable first-run guide |
| `app/lib/features/settings/settings_page.dart` | added | Settings: Simple Mode, theme, text size, speech, language, OCR language, optional backup |
| `app/lib/imaging/detector_params.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/imaging/geometry.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/imaging/markup.dart` | added | Markup item model (text, strokes, shapes, signature), JSON, rotate/crop transforms |
| `app/lib/imaging/native/native_scan_engine.dart` | changed | Changed for: crop fix, testing/format |
| `app/lib/imaging/native/opencv_detector.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/imaging/native/opencv_filters.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/imaging/page_edits.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/imaging/scan_engine.dart` | changed | normalizeEncoded (EXIF, size cap) |
| `app/lib/imaging/server_scan_engine.dart` | changed | Changed for: crop fix, testing/format |
| `app/lib/imaging/web/web_scan_engine.dart` | changed | Changed for: crop fix, testing/format |
| `app/lib/l10n/app_en.arb` | added | Changed for: guest-first, OCR, markup, UI redesign, testing/format |
| `app/lib/l10n/app_hi.arb` | added | Changed for: guest-first, OCR, markup, UI redesign, testing/format |
| `app/lib/l10n/app_localizations.dart` | added | Generated from tool/strings.py (flutter gen-l10n) |
| `app/lib/l10n/app_localizations_en.dart` | added | Generated from tool/strings.py (flutter gen-l10n) |
| `app/lib/l10n/app_localizations_hi.dart` | added | Generated from tool/strings.py (flutter gen-l10n) |
| `app/lib/main.dart` | changed | Localisation, themes, text scale, onboarding, web semantics on |
| `app/lib/services/api/api_client.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/services/camera/demo_scanner_camera.dart` | changed | Changed for: UI redesign, testing/format |
| `app/lib/services/camera/mobile_scanner_camera.dart` | changed | Choose among lenses; un-mirrored front camera |
| `app/lib/services/camera/scanner_camera.dart` | changed | Changed for: UI redesign, testing/format |
| `app/lib/services/camera/unsupported_camera.dart` | changed | Changed for: UI redesign |
| `app/lib/services/camera/web_scanner_camera.dart` | changed | Choose among webcams |
| `app/lib/services/export/pdf_builder.dart` | changed | Changed for: OCR, testing/format |
| `app/lib/services/export/share_service.dart` | changed | Formatting only (dart format / ruff format) |
| `app/lib/services/import/import_service.dart` | changed | Changed for: guest-first |
| `app/lib/services/ocr/mlkit_text_recognizer.dart` | changed | Changed for: OCR, testing/format |
| `app/lib/services/ocr/ocr_result.dart` | changed | Changed for: OCR, testing/format |
| `app/lib/services/ocr/text_recognizer.dart` | changed | Changed for: OCR |
| `app/lib/services/ocr/web_text_recognizer.dart` | changed | Changed for: OCR, testing/format |

## app/pubspec.lock

| File | | What |
|---|---|---|
| `app/pubspec.lock` | changed | Changed for: guest-first, UI redesign |

## app/pubspec.yaml

| File | | What |
|---|---|---|
| `app/pubspec.yaml` | changed | Changed for: guest-first, OCR, markup, UI redesign |

## app/test

| File | | What |
|---|---|---|
| `app/test/data/repository_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/features/accessibility_test.dart` | added | Guideline checks on every screen, 200% text, keyboard, contrast |
| `app/test/features/capture_controller_test.dart` | changed | Changed for: UI redesign, testing/format |
| `app/test/features/corner_editor_test.dart` | changed | Changed for: crop fix, UI redesign, testing/format |
| `app/test/features/document_controller_test.dart` | changed | Changed for: crop fix, testing/format |
| `app/test/features/error_paths_test.dart` | added | Server down/401/500, offline backup, bad imports, navigation |
| `app/test/features/guest_flow_widget_test.dart` | added | No-account flows, editor reorder/undo/filters |
| `app/test/features/library_editor_widget_test.dart` | deleted | Tested the removed Library screen; its 3 tests moved to guest_flow_widget_test.dart (Documents search, empty state, editor rotate/rename) |
| `app/test/features/markup_test.dart` | added | Markup model, history, hit test, transforms, flatten, editor screen |
| `app/test/features/ocr_test.dart` | changed | Changed for: OCR, testing/format |
| `app/test/features/scanner_camera_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/features/scanner_page_test.dart` | added | Scanner controls, camera switch, upload fallback, guidance |
| `app/test/features/text_sheet_test.dart` | added | Changed for: OCR, markup, testing/format |
| `app/test/imaging/fixtures.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/imaging/geometry_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/imaging/native_scan_engine_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/imaging/opencv_detector_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/imaging/opencv_filters_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/imaging/orientation_engine_test.dart` | added | Changed for: crop fix, testing/format |
| `app/test/imaging/page_renderer_engine_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/integration/sync_e2e_test.dart` | changed | Changed for: guest-first, testing/format |
| `app/test/services/api_client_test.dart` | changed | Formatting only (dart format / ruff format) |
| `app/test/support/fakes.dart` | changed | Changed for: crop fix, UI redesign, testing/format |
| `app/test/support/test_app.dart` | added | Changed for: guest-first, testing/format |

## app/test_js

| File | | What |
|---|---|---|
| `app/test_js/package-lock.json` | changed | Changed for: OCR |
| `app/test_js/package.json` | changed | Changed for: OCR |
| `app/test_js/scanner.test.js` | changed | Changed for: OCR, website |

## app/tool

| File | | What |
|---|---|---|
| `app/tool/check_pdf_text.py` | added | Changed for: OCR, testing/format |
| `app/tool/render_ocr_fixture_test.dart` | added | Changed for: OCR, testing/format |
| `app/tool/strings.py` | added | Single source of all UI strings (English + Hindi) |

## app/web

| File | | What |
|---|---|---|
| `app/web/ocr/lang/hin.traineddata.gz` | added | Changed for: OCR |
| `app/web/ocr/ocr.js` | changed | Word-confidence + meaningful-text filtering, Hindi |
| `app/web/opencv/scanner.js` | changed | explainDetection for the website; shared working-image helper |
| `app/web/opencv/scanner_worker.js` | changed | EXIF-aware decode, normalise, versioned imports |

## backend

| File | | What |
|---|---|---|
| `backend/alembic/versions/0001_initial.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/api/auth.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/api/documents.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/api/process.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/core/security.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/main.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/schemas.py` | changed | Page markup field with limits |
| `backend/app/services/imaging.py` | changed | Formatting only (dart format / ruff format) |
| `backend/app/services/storage.py` | changed | Formatting only (dart format / ruff format) |
| `backend/docker-compose.yml` | changed | CORS for the 8080 site |
| `backend/requirements-dev.txt` | changed | Formatting only (dart format / ruff format) |
| `backend/scripts/seed_demo.py` | changed | Formatting only (dart format / ruff format) |
| `backend/tests/conftest.py` | changed | Formatting only (dart format / ruff format) |
| `backend/tests/test_auth.py` | changed | Formatting only (dart format / ruff format) |
| `backend/tests/test_documents.py` | changed | Changed for: markup, testing/format |
| `backend/tests/test_process.py` | changed | Formatting only (dart format / ruff format) |

## docs

| File | | What |
|---|---|---|
| `docs/FEATURE_AUDIT.md` | added | Audit of what worked and the plan for this round |
| `docs/TECH_DECISIONS.md` | added | Architecture, scan flow, decisions vs alternatives, limitations, viva Q&A |
| `docs/TESTING.md` | added | Test results, accessibility audit, manual and phone-only checks |
| `docs/testing/a11y-report.json` | added | Changed for: accessibility, website |
| `docs/testing/test-results.json` | added | Changed for: website, testing/format |

## scanner_core

| File | | What |
|---|---|---|
| `scanner_core/scanner_core/__init__.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/scanner_core/detect.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/scanner_core/filters.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/scanner_core/pipeline.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/scanner_core/smoothing.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/scanner_core/warp.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/debug_detect.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/export_filter_reference.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/export_reference.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/make_fixtures.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/make_orientation_fixtures.py` | added | Changed for: crop fix, testing/format |
| `scanner_core/tests/render_results.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/test_detect.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/test_filters.py` | changed | Formatting only (dart format / ruff format) |
| `scanner_core/tests/test_warp.py` | changed | Formatting only (dart format / ruff format) |

## shared

| File | | What |
|---|---|---|
| `shared/test_fixtures/ocr/hindi_page.png` | added | Changed for: OCR |
| `shared/test_fixtures/ocr/hindi_page.txt` | added | Changed for: OCR |
| `shared/test_fixtures/ocr/no_text.jpg` | added | Changed for: OCR |
| `shared/test_fixtures/orientation/exif_rotated.jpg` | added | Changed for: crop fix |
| `shared/test_fixtures/orientation/landscape.jpg` | added | Changed for: crop fix |
| `shared/test_fixtures/orientation/large.jpg` | added | Changed for: crop fix |
| `shared/test_fixtures/orientation/orientation.json` | added | Changed for: crop fix |
| `shared/test_fixtures/orientation/portrait.jpg` | added | Changed for: crop fix |

## tools

| File | | What |
|---|---|---|
| `tools/audit/.gitignore` | added | Changed for: accessibility |
| `tools/audit/audit.mjs` | added | axe-core + Lighthouse accessibility audit of app and website |
| `tools/audit/package-lock.json` | added | Changed for: accessibility |
| `tools/audit/package.json` | added | Changed for: accessibility |
| `tools/audit/screenshots.mjs` | added | Takes real app screenshots (demo camera) for the website |
| `tools/collect_results.py` | added | Turns Dart JSON / JUnit reports into website/data/test-results.json |
| `tools/run_tests.sh` | added | Runs every test suite and records the real results |
| `tools/serve.py` | added | Serves website at / and the app at /app/ with no-cache headers |

## website

| File | | What |
|---|---|---|
| `website/css/site.css` | added | Changed for: website |
| `website/data/a11y-report.json` | added | Changed for: website |
| `website/data/site.json` | added | Changed for: website |
| `website/data/test-results.json` | added | Changed for: website, testing/format |
| `website/features.html` | added | Feature status and repository link |
| `website/how-it-works.html` | added | Live pipeline steps on an uploaded photo |
| `website/img/logo.svg` | added | Changed for: website |
| `website/img/sample-page.jpg` | added | Changed for: website |
| `website/img/screens/editor-desktop.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/editor.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/export.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/filters.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/guide.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/home-empty.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/markup.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/review-corners.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/img/screens/scanner.png` | added | Real app screenshot (tools/audit/screenshots.mjs) |
| `website/index.html` | added | Website home with real screenshots and Try it now |
| `website/js/features.js` | added | Changed for: website |
| `website/js/how.js` | added | Changed for: website |
| `website/js/pipeline_worker.js` | added | Changed for: website |
| `website/js/site.js` | added | Changed for: website |
| `website/js/tests.js` | added | Changed for: website |
| `website/tests.html` | added | Real test results and accessibility audit |
