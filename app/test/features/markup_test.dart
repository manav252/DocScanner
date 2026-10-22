// Markup: JSON, undo/redo, hit testing, rotate/crop transforms, flattening
// for export, and the editor screen (labelled tools, keyboard, save).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_controller.dart';
import 'package:docscanner/features/markup/markup_editor_page.dart';
import 'package:docscanner/features/markup/markup_model.dart';
import 'package:docscanner/features/markup/markup_painter.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/markup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

const text = TextMarkup(
  id: 't',
  text: 'Approved',
  x: 0.5,
  y: 0.3,
  width: 0.5,
  size: 0.05,
  color: 0xFFC62828,
  bold: true,
);
const pen = StrokeMarkup(
  id: 'p',
  highlighter: false,
  color: 0xFF111111,
  width: 0.007,
  points: [Pt(0.1, 0.1), Pt(0.2, 0.15), Pt(0.3, 0.1)],
);
const hl = StrokeMarkup(
  id: 'h',
  highlighter: true,
  color: 0xFFFFD400,
  width: 0.03,
  points: [Pt(0.1, 0.8), Pt(0.6, 0.8)],
);
const rect = ShapeMarkup(
  id: 'r',
  kind: MarkupKind.rect,
  color: 0xFF1A4FD6,
  width: 0.006,
  a: Pt(0.6, 0.6),
  b: Pt(0.9, 0.7),
);
const arrow = ShapeMarkup(
  id: 'a',
  kind: MarkupKind.arrow,
  color: 0xFF111111,
  width: 0.006,
  a: Pt(0.1, 0.5),
  b: Pt(0.4, 0.5),
);
const white = ShapeMarkup(
  id: 'w',
  kind: MarkupKind.whiteout,
  color: 0xFFFFFFFF,
  width: 0,
  a: Pt(0.05, 0.9),
  b: Pt(0.3, 0.97),
);
const sig = SignatureMarkup(
  id: 's',
  x: 0.7,
  y: 0.4,
  width: 0.3,
  height: 0.1,
  color: 0xFF1A4FD6,
  strokes: [
    [Pt(0, 0.5), Pt(0.5, 0), Pt(1, 1)],
  ],
);
const all = <MarkupItem>[text, pen, hl, rect, arrow, white, sig];

bool near(Pt a, Pt b) => (a.x - b.x).abs() < 1e-3 && (a.y - b.y).abs() < 1e-3;

void main() {
  group('model', () {
    test('every kind survives JSON, and unknown kinds are skipped', () {
      final back = markupFromJson([
        ...markupToJson(all),
        {'k': 'sticker', 'id': 'x'},
      ]);
      expect(back.map((i) => i.kind), all.map((i) => i.kind));
      expect(markupToJson(back), markupToJson(all));
      final t = back.first as TextMarkup;
      expect((t.text, t.bold, t.color), ('Approved', true, 0xFFC62828));
    });

    test('page JSON keeps markup', () {
      const page = ScanPage(
        id: 'x',
        sourceWidth: 1,
        sourceHeight: 1,
        corners: [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1)],
        markup: all,
      );
      final back = ScanPage.fromJson(page.toJson());
      expect(markupToJson(back.markup), markupToJson(all));
    });

    test('four clockwise turns return every item to where it was', () {
      for (final item in all) {
        var r = item;
        for (var i = 0; i < 4; i++) {
          r = r.rotatedClockwise();
        }
        final a = item.bounds(), b = r.bounds();
        expect(near(Pt(a.l, a.t), Pt(b.l, b.t)) && near(Pt(a.r, a.b), Pt(b.r, b.b)), isTrue, reason: item.kind.name);
      }
      // One turn: a point at the top-left moves to the top-right.
      final turned = pen.rotatedClockwise();
      expect(near(turned.points.first, const Pt(0.9, 0.1)), isTrue);
    });

    test('cropping keeps items on the same page content', () {
      // Old crop is the whole page; new crop is the right half.
      final from = [0.0, 0.0, 1.0, 1.0], to = [0.5, 0.0, 0.5, 1.0];
      final moved = rect.recropped(from, to, 1.0);
      expect(near(moved.a, const Pt(0.2, 0.6)), isTrue);
      expect(near(moved.b, const Pt(0.8, 0.7)), isTrue);
      final t = text.recropped(from, to, 2.0);
      expect(t.size, closeTo(0.1, 1e-9));
    });
  });

  group('history', () {
    test('undo/redo, previews and dirty state', () {
      final h = MarkupHistory(const []);
      expect((h.canUndo, h.canRedo, h.dirty), (false, false, false));
      h.commit([text]);
      h.commit([text, rect]);
      expect(h.items.length, 2);
      h.undo();
      expect(h.items, [text]);
      expect(h.canRedo, isTrue);
      h.redo();
      expect(h.items.length, 2);

      // A drag shows previews and records one step.
      final before = h.items;
      h.preview(h.replace('r', (i) => i.translate(0.01, 0)));
      h.preview(h.replace('r', (i) => i.translate(0.01, 0)));
      h.commitFrom(before);
      expect(near((h.items[1] as ShapeMarkup).a, const Pt(0.62, 0.6)), isTrue);
      h.undo();
      expect(identical(h.items, before), isTrue);

      h.commit(h.without('t'));
      expect(h.items.map((i) => i.id), ['r']);
      expect(h.canRedo, isFalse); // a new step clears redo
      h
        ..undo()
        ..undo()
        ..undo();
      expect(h.items, isEmpty);
      expect(h.dirty, isFalse);
    });
  });

  group('hit testing', () {
    const page = Size(600, 800);
    test('finds the topmost item, lines by distance, empty space is null', () {
      expect(hitTestMarkup(all, const Pt(0.75, 0.65), page)?.id, 'r');
      expect(hitTestMarkup(all, const Pt(0.25, 0.505), page)?.id, 'a');
      expect(hitTestMarkup(all, const Pt(0.25, 0.56), page), isNull);
      expect(hitTestMarkup(all, const Pt(0.2, 0.15), page)?.id, 'p');
      expect(hitTestMarkup(all, const Pt(0.5, 0.3), page)?.id, 't');
      expect(hitTestMarkup(all, const Pt(0.7, 0.4), page)?.id, 's');
      // Overlap: the later item wins.
      const top = ShapeMarkup(
        id: 'top',
        kind: MarkupKind.whiteout,
        color: 0,
        width: 0,
        a: Pt(0.55, 0.55),
        b: Pt(0.95, 0.75),
      );
      expect(hitTestMarkup([...all, top], const Pt(0.75, 0.65), page)?.id, 'top');
    });

    test('eraser removes strokes only', () {
      expect(eraseAt(all, const Pt(0.2, 0.15), const Size(600, 800)).toList(), ['p']);
      expect(eraseAt(all, const Pt(0.75, 0.65), const Size(600, 800)).toList(), isEmpty);
    });
  });

  testWidgets('flattening burns markup into the exported image', (tester) async {
    final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();
    final out = (await tester.runAsync(() async {
      final flat = await flattenMarkup(png, const [
        ShapeMarkup(id: 'b', kind: MarkupKind.rect, color: 0xFF1A4FD6, width: 0.02, a: Pt(0.1, 0.1), b: Pt(0.9, 0.9)),
        ShapeMarkup(id: 'w', kind: MarkupKind.whiteout, color: 0, width: 0, a: Pt(0.3, 0.3), b: Pt(0.7, 0.7)),
      ]);
      final img = (await (await ui.instantiateImageCodec(flat)).getNextFrame()).image;
      final data = (await img.toByteData())!;
      final w = img.width, h = img.height;
      int px(double fx, double fy) => data.getUint32(((fy * h).round() * w + (fx * w).round()) * 4);
      return (w: w, h: h, center: px(0.5, 0.5), edge: px(0.5, 0.1));
    }))!;
    expect((out.w, out.h), (583, 800)); // same size as the page
    expect(out.center, 0xFFFFFFFF); // whiteout
    expect(out.edge >> 8 & 0xFFFFFF, 0x1A4FD6); // RGBA: blue rectangle edge
  });

  group('editor screen', () {
    Future<MemoryStore> seed({List<MarkupItem> markup = const []}) async {
      final store = MemoryStore();
      final repo = DocumentRepository(store);
      final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();
      final p = ScanPage(
        id: 'p',
        sourceWidth: 583,
        sourceHeight: 800,
        corners: const [Pt(0, 0), Pt(582, 0), Pt(582, 799), Pt(0, 799)],
        revision: 1,
        renderWidth: 583,
        renderHeight: 800,
        markup: markup,
      );
      for (final k in PageImage.values) {
        await repo.putPageImage('p', k, png);
      }
      await repo.save(
        ScanDocument(id: 'd', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: [p]),
      );
      return store;
    }

    Future<ProviderContainer> open(WidgetTester tester, MemoryStore store) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (c) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(c).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MarkupEditorPage(documentId: 'd', pageId: 'p'),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
          overrides: [
            keyValueStoreProvider.overrideWithValue(store),
            scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage)),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return ProviderScope.containerOf(tester.element(find.byType(MarkupEditorPage)));
    }

    Future<List<MarkupItem>> saved(WidgetTester tester, MemoryStore store) async =>
        (await tester.runAsync(() => DocumentRepository(store).get('d')))!.pages.single.markup;

    testWidgets('every tool is a labelled button; Simple Mode shows the essentials', (tester) async {
      final store = (await tester.runAsync(seed))!;
      await open(tester, store);
      for (final label in ['Select', 'Add text', 'Pen', 'Signature', 'Whiteout', 'Eraser']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      expect(find.widgetWithText(ChoiceChip, 'Arrow'), findsNothing);
      for (final label in ['Undo', 'Redo', 'Done']) {
        expect(
          find.widgetWithText(ButtonStyleButton, label).evaluate().isNotEmpty ||
              find
                  .ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
                  .evaluate()
                  .isNotEmpty,
          isTrue,
          reason: label,
        );
      }
      expect(find.text('Items on this page (0)'), findsOneWidget);
    });

    testWidgets('add text in the middle, edit it with the keyboard, undo/redo, save', (tester) async {
      final store = (await tester.runAsync(seed))!;
      await open(tester, store);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Add text'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-in-middle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('markup-text-field')), 'Paid in full');
      await tester.tap(find.byKey(const ValueKey('markup-text-ok')));
      await tester.pumpAndSettle();

      final state = tester.state<MarkupEditorPageState>(find.byType(MarkupEditorPage));
      expect((state.items.single as TextMarkup).text, 'Paid in full');
      await tester.scrollUntilVisible(find.text('Text: Paid in full'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Text: Paid in full'), findsOneWidget);
      expect(state.selectedId, isNotNull);

      // Keyboard: arrow moves the selected item; Ctrl+Z undoes the move.
      await tester.tap(find.byKey(const ValueKey('markup-canvas')), warnIfMissed: false);
      state.selectedId = state.items.single.id; // tapping empty space deselects
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect((state.items.single as TextMarkup).x, closeTo(0.51, 1e-9));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect((state.items.single as TextMarkup).x, closeTo(0.5, 1e-9));
      await tester.tap(find.byKey(const ValueKey('markup-redo')));
      await tester.pump();
      expect((state.items.single as TextMarkup).x, closeTo(0.51, 1e-9));

      // Bigger button and bold toggle act on the selection.
      final size = (state.items.single as TextMarkup).size;
      await tester.tap(find.text('Bigger'));
      await tester.pump();
      expect((state.items.single as TextMarkup).size, greaterThan(size));

      await tester.tap(find.byKey(const ValueKey('markup-save')));
      await settle(tester);
      final items = await saved(tester, store);
      expect(items.single, isA<TextMarkup>());
      expect((items.single as TextMarkup).text, 'Paid in full');
      expect(find.byType(MarkupEditorPage), findsNothing);
    });

    testWidgets('drag draws a rectangle; Delete key removes the selection', (tester) async {
      final store = (await tester.runAsync(seed))!;
      final c = await open(tester, store);
      await tester.runAsync(
        () => c.read(appSettingsProvider.notifier).update(c.read(appSettingsProvider).copyWith(simpleMode: false)),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rectangle'));
      await tester.pump();
      final canvas = tester.getRect(find.byKey(const ValueKey('markup-canvas')));
      await tester.dragFrom(canvas.center, const Offset(120, 80));
      await tester.pump();
      final state = tester.state<MarkupEditorPageState>(find.byType(MarkupEditorPage));
      expect(state.items.single, isA<ShapeMarkup>());
      expect(state.selectedId, state.items.single.id);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(state.items, isEmpty);
      expect(find.text('Nothing added yet.'), findsOneWidget);
    });

    testWidgets('pen strokes and eraser; leaving with changes asks first', (tester) async {
      final store = (await tester.runAsync(() => seed(markup: const [rect])))!;
      await open(tester, store);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pen'));
      await tester.pump();
      final canvas = tester.getRect(find.byKey(const ValueKey('markup-canvas')));
      await tester.dragFrom(canvas.center - const Offset(100, 0), const Offset(200, 0));
      await tester.pump();
      final state = tester.state<MarkupEditorPageState>(find.byType(MarkupEditorPage));
      expect(state.items.whereType<StrokeMarkup>(), hasLength(1));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Eraser'));
      await tester.pump();
      await tester.tapAt(canvas.center);
      await tester.pump();
      expect(state.items.whereType<StrokeMarkup>(), isEmpty);
      expect(state.items.single.id, 'r'); // eraser leaves shapes alone

      // Back with unsaved changes: confirm dialog; Keep editing stays.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkupEditorPage), findsOneWidget);
      nav.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.byType(MarkupEditorPage), findsNothing);
      expect((await saved(tester, store)).single.id, 'r'); // unchanged
    });

    testWidgets('rotating the page keeps markup on the content', (tester) async {
      final store = (await tester.runAsync(() => seed(markup: const [pen])))!;
      final c = await open(tester, store);
      await tester.runAsync(() => c.read(documentProvider('d').notifier).rotate('p'));
      final p = (await saved(tester, store)).single as StrokeMarkup;
      expect(near(p.points.first, const Pt(0.9, 0.1)), isTrue);
      expect(p.width, pen.width); // sizes are in units of the shorter side
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
