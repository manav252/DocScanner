"""Regenerate docs/CHANGES.md: python3 tools/changes_summary.py"""

import subprocess
import collections

BASE = "d7f7a26"


def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True, check=True).stdout


FORMAT = "151a831"
short = {
    "f8b1cd8": "crop fix",
    "bb439e3": "guest-first",
    "54589aa": "OCR",
    "9ab4457": "markup",
    "490271d": "UI redesign",
    "b175834": "accessibility",
    "786f967": "website",
    "3d39b4c": "docs",
    "151a831": "testing/format",
    "2ba8060": "audit",
}
D = {
    "app/lib/features/library/library_page.dart": "Replaced by the new Home and Documents screens",
    "app/test/features/library_editor_widget_test.dart": "Tested the removed Library screen; its 3 tests moved to guest_flow_widget_test.dart (Documents search, empty state, editor rotate/rename)",
    "README.md": "Rewritten: one-command start, guest use, phones, tests, GitHub steps, limitations",
    "start.sh": "One command: backend (Docker), web app build when needed, website + app server",
    "tools/serve.py": "Serves website at / and the app at /app/ with no-cache headers",
    "tools/run_tests.sh": "Runs every test suite and records the real results",
    "tools/collect_results.py": "Turns Dart JSON / JUnit reports into website/data/test-results.json",
    "tools/audit/audit.mjs": "axe-core + Lighthouse accessibility audit of app and website",
    "tools/audit/screenshots.mjs": "Takes real app screenshots (demo camera) for the website",
    "ruff.toml": "Python lint/format settings",
    "docs/FEATURE_AUDIT.md": "Audit of what worked and the plan for this round",
    "docs/TECH_DECISIONS.md": "Architecture, scan flow, decisions vs alternatives, limitations, viva Q&A",
    "docs/TESTING.md": "Test results, accessibility audit, manual and phone-only checks",
    "app/lib/imaging/markup.dart": "Markup item model (text, strokes, shapes, signature), JSON, rotate/crop transforms",
    "app/lib/features/markup/markup_editor_page.dart": "Edit / Markup screen: tools, gestures, keyboard, undo/redo, item list",
    "app/lib/features/markup/markup_model.dart": "Undo/redo history, hit testing, eraser",
    "app/lib/features/markup/markup_painter.dart": "Draws markup; flattens it into images for export",
    "app/lib/features/markup/signature_pad.dart": "Draw a signature once, saved on the device",
    "app/lib/features/capture/scan_guidance.dart": "Spoken + haptic scan guidance, capture announcements",
    "app/lib/features/capture/capture_page.dart": "Scanner screen redesign: labelled controls, upload fallback, error screens, hints",
    "app/lib/features/capture/capture_controller.dart": "Photo normalisation, upload path, camera switch, Move closer / next page states, Retake re-arm",
    "app/lib/features/corners/corner_editor.dart": "Corner editor rewrite: fitted mapping, edges, keyboard, loupe, semantics",
    "app/lib/features/corners/corner_adjust_page.dart": "Review screen: Reset / Use full photo / Rotate / Confirm / Cancel, no-edges message",
    "app/lib/features/editor/document_editor_page.dart": "Editor redesign: labelled toolbar, move earlier/later, delete with Undo, Add pages",
    "app/lib/features/editor/filter_sheet.dart": "Filter preview cards, before/after compare, progress",
    "app/lib/features/editor/export_sheet.dart": "Localized export with platform explanations",
    "app/lib/features/editor/export.dart": "Burns markup into exported pages; Hindi PDF font",
    "app/lib/features/editor/text_sheet.dart": "Text view: No text found, Copy text → Copied, language, errors",
    "app/lib/features/editor/ocr_runner.dart": "OCR in the chosen language; re-runs when the page changes",
    "app/lib/features/editor/document_controller.dart": "Markup transforms, setMarkup, undoable page delete",
    "app/lib/features/home/home_page.dart": "New Home: main actions, status line, recent scans, first-time help",
    "app/lib/features/library/documents_page.dart": "Documents list with search and labelled actions",
    "app/lib/features/library/import_flow.dart": "Normalises imports; skips unreadable files and names them",
    "app/lib/features/library/import_ui.dart": "Import with progress into a new document",
    "app/lib/features/settings/settings_page.dart": "Settings: Simple Mode, theme, text size, speech, language, OCR language, optional backup",
    "app/lib/features/onboarding/onboarding_page.dart": "3-step skippable first-run guide",
    "app/lib/features/common/dialogs.dart": "Rename and delete dialogs",
    "app/lib/features/common/document_card.dart": "Document card and backup badge",
    "app/lib/features/common/page_image.dart": "Page image with live markup overlay",
    "app/lib/features/account/account_page.dart": "Optional sign-in, upload-existing consent, localized errors",
    "app/lib/core/app_settings.dart": "New settings: theme, contrast, text size, Simple Mode, language, speech, OCR language",
    "app/lib/core/theme.dart": "Accessible theme: 48dp targets, focus rings, high contrast, reduced motion, bundled fonts",
    "app/lib/core/l10n.dart": "context.l10n helper",
    "app/lib/core/providers.dart": "Camera index provider (switch camera)",
    "app/lib/main.dart": "Localisation, themes, text scale, onboarding, web semantics on",
    "app/lib/data/models.dart": "Backup flag, OCR language/revision, page markup",
    "app/lib/data/document_repository.dart": "Page file snapshot/restore (undo delete)",
    "app/lib/data/sync/sync_service.dart": "Opt-in backup, conflict titles, markup sync, account preparation",
    "app/lib/imaging/scan_engine.dart": "normalizeEncoded (EXIF, size cap)",
    "app/lib/services/camera/web_scanner_camera.dart": "Choose among webcams",
    "app/lib/services/camera/mobile_scanner_camera.dart": "Choose among lenses; un-mirrored front camera",
    "app/tool/strings.py": "Single source of all UI strings (English + Hindi)",
    "app/web/opencv/scanner.js": "explainDetection for the website; shared working-image helper",
    "app/web/opencv/scanner_worker.js": "EXIF-aware decode, normalise, versioned imports",
    "app/web/ocr/ocr.js": "Word-confidence + meaningful-text filtering, Hindi",
    "backend/app/schemas.py": "Page markup field with limits",
    "backend/docker-compose.yml": "CORS for the 8080 site",
    "website/index.html": "Website home with real screenshots and Try it now",
    "website/how-it-works.html": "Live pipeline steps on an uploaded photo",
    "website/tests.html": "Real test results and accessibility audit",
    "website/features.html": "Feature status and repository link",
    "app/test/features/markup_test.dart": "Markup model, history, hit test, transforms, flatten, editor screen",
    "app/test/features/scanner_page_test.dart": "Scanner controls, camera switch, upload fallback, guidance",
    "app/test/features/accessibility_test.dart": "Guideline checks on every screen, 200% text, keyboard, contrast",
    "app/test/features/error_paths_test.dart": "Server down/401/500, offline backup, bad imports, navigation",
    "app/test/features/guest_flow_widget_test.dart": "No-account flows, editor reorder/undo/filters",
}
status = {}
for line in git("diff", "--name-status", BASE, "HEAD").splitlines():
    st, *paths = line.split("\t")
    status[paths[-1]] = st[0]
groups = collections.OrderedDict()
for f in sorted(status):
    commits = [c[:7] for c in git("log", "--format=%H", f"{BASE}..HEAD", "--", f).split()]
    if "app/lib/l10n/app_localizations" in f:
        desc = "Generated from tool/strings.py (flutter gen-l10n)"
    elif f.startswith("website/img/screens/"):
        desc = "Real app screenshot (tools/audit/screenshots.mjs)"
    elif f in D:
        desc = D[f]
    elif commits == [FORMAT] and status[f] == "M":
        desc = "Formatting only (dart format / ruff format)"
    else:
        desc = "Changed for: " + ", ".join(short.get(c, c) for c in reversed(commits))
    top = f.split("/")[0] if "/" in f else "(root)"
    if top == "app":
        top = "app/" + f.split("/")[1]
    groups.setdefault(top, []).append((f, status[f], desc))
words = {"A": "added", "M": "changed", "D": "deleted"}
out = [
    "# Files created or changed in this round",
    "",
    f"Generated from git (`{BASE[:7]}..HEAD`, {len(status)} files): "
    + ", ".join(f"{sum(1 for s in status.values() if s == k)} {v}" for k, v in words.items())
    + ".",
    "Commits: " + "; ".join(f"`{k}` {v}" for k, v in short.items()) + ".",
    "",
]
for g, rows in groups.items():
    out += [f"## {g}", "", "| File | | What |", "|---|---|---|"]
    out += [f"| `{f}` | {words[s]} | {d} |" for f, s, d in rows]
    out.append("")
open("docs/CHANGES.md", "w").write("\n".join(out))
print(len(status))
