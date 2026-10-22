import 'package:docscanner/features/corners/corner_adjust_page.dart';
import 'package:docscanner/features/corners/corner_editor.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';


// 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, //
  137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174,
  66, 96, 130,
]);

const imageSize = Size(1000, 1000);
const start = [Pt(100, 100), Pt(900, 100), Pt(900, 900), Pt(100, 900)];

Widget editor(ValueNotifier<List<Pt>> corners) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 500,
          height: 500,
          child: ValueListenableBuilder(
            valueListenable: corners,
            builder: (_, c, _) => CornerEditor(
              image: MemoryImage(_png),
              imageSize: imageSize,
              corners: c,
              onChanged: (v) => corners.value = v,
            ),
          ),
        ),
      ),
    );

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  testWidgets('dragging a corner moves only that corner and shows the loupe', (tester) async {
    final corners = ValueNotifier<List<Pt>>(start);
    await tester.pumpWidget(editor(corners));
    // The 1000x1000 image is shown at 0.5 scale in a 500x500 box: TL handle at (50, 50).
    final g = await tester.startGesture(const Offset(52, 52));
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('loupe')), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('loupe')), findsNothing);
    // 40 px right, 10 px down on screen = 80, 20 image px at 0.5 scale.
    expect(corners.value[0].x, closeTo(180, 1));
    expect(corners.value[0].y, closeTo(120, 1));
    expect(corners.value.sublist(1), start.sublist(1));
  });

  testWidgets('dragging an edge midpoint moves both corners of that side', (tester) async {
    final corners = ValueNotifier<List<Pt>>(start);
    await tester.pumpWidget(editor(corners));
    // Top edge midpoint at (250, 50).
    await tester.dragFrom(const Offset(250, 50), const Offset(0, 60));
    await tester.pump();
    expect(corners.value[0].y, greaterThan(150));
    expect(corners.value[1].y, corners.value[0].y);
    expect(corners.value[2], start[2]);
  });

  testWidgets('corners are clamped to the image', (tester) async {
    final corners = ValueNotifier<List<Pt>>(start);
    await tester.pumpWidget(editor(corners));
    await tester.dragFrom(const Offset(50, 50), const Offset(-200, -200));
    await tester.pump();
    expect(corners.value[0], const Pt(0, 0));
  });

  test('isValidQuad rejects crossed and tiny quads', () {
    expect(isValidQuad(start, imageSize), isTrue);
    expect(isValidQuad(const [Pt(100, 100), Pt(900, 900), Pt(900, 100), Pt(100, 900)], imageSize), isFalse);
    expect(isValidQuad(const [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)], imageSize), isFalse);
  });

  group('image fitting and coordinate mapping', () {
    for (final (name, img, box) in [
      ('portrait photo, wide box', const Size(1200, 1600), const Size(800, 400)),
      ('landscape photo, tall box', const Size(1600, 1200), const Size(375, 700)),
      ('very large photo, square box', const Size(4000, 3000), const Size(500, 500)),
      ('portrait photo, portrait box', const Size(3000, 4000), const Size(390, 600)),
    ]) {
      test(name, () {
        final r = fittedImageRect(img, box);
        // Fully inside the box, aspect ratio kept, centred, touching two opposite sides.
        expect(r.left >= -1e-9 && r.top >= -1e-9 && r.right <= box.width + 1e-9 && r.bottom <= box.height + 1e-9, isTrue);
        expect(r.width / r.height, closeTo(img.width / img.height, 1e-9));
        expect(r.center.dx, closeTo(box.width / 2, 1e-9));
        expect(r.center.dy, closeTo(box.height / 2, 1e-9));
        expect((r.width - box.width).abs() < 1e-9 || (r.height - box.height).abs() < 1e-9, isTrue);
        // Corners of the image map to corners of the rect and back.
        for (final p in [const Pt(0, 0), Pt(img.width - 1, img.height - 1), Pt(img.width / 3, img.height / 2)]) {
          final back = screenToImage(imageToScreen(p, r, img), r, img);
          expect(back.distanceTo(p), lessThan(1e-6));
        }
      });
    }

    test('screen points outside the image clamp to its edge', () {
      const img = Size(1000, 500);
      final r = fittedImageRect(img, const Size(500, 500)); // letterboxed top and bottom
      expect(screenToImage(const Offset(-50, 0), r, img), const Pt(0, 0));
      expect(screenToImage(const Offset(1000, 1000), r, img), const Pt(999, 499));
    });
  });

  testWidgets('the photo is drawn centred and fully inside the editor (portrait photo, wide editor)', (tester) async {
    final corners = ValueNotifier<List<Pt>>(const [Pt(0, 0), Pt(1199, 0), Pt(1199, 1599), Pt(0, 1599)]);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 400,
            child: ValueListenableBuilder(
              valueListenable: corners,
              builder: (_, c, _) => CornerEditor(
                image: MemoryImage(_png),
                imageSize: const Size(1200, 1600),
                corners: c,
                onChanged: (v) => corners.value = v,
              ),
            ),
          ),
        ),
      ),
    ));
    final editor = tester.getRect(find.byType(CornerEditor));
    final image = tester.getRect(find.byKey(const ValueKey('corner-editor-image')));
    expect(image.height, closeTo(400, 0.01));
    expect(image.width, closeTo(300, 0.01));
    expect(image.center.dx, closeTo(editor.center.dx, 0.01), reason: 'not pushed to the left');
    expect(image.bottom, lessThanOrEqualTo(editor.bottom + 0.01), reason: 'bottom not cut off');
    // Dragging the bottom-right handle (image corner) inward maps back to image pixels.
    final br = image.bottomRight - const Offset(1, 1);
    await tester.dragFrom(br, const Offset(-75, -100));
    await tester.pump();
    // 75 x 100 screen px at scale 0.25 = 300 x 400 image px.
    expect(corners.value[2].x, closeTo(1199 - 300, 6));
    expect(corners.value[2].y, closeTo(1599 - 400, 6));
  });

  testWidgets('keyboard: Tab picks a corner, arrows move it 1% (Shift: 0.2%)', (tester) async {
    final corners = ValueNotifier<List<Pt>>(start);
    await tester.pumpWidget(editor(corners));
    final state = tester.state<CornerEditorState>(find.byType(CornerEditor));
    await tester.tap(find.byType(CornerEditor));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // top-left -> top-right
    await tester.pump();
    expect(state.selectedCorner, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(corners.value[1], const Pt(890, 100)); // 1% of 1000 px
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(corners.value[1], const Pt(890, 102)); // 0.2%
    expect(corners.value[0], start[0]);
    expect(find.byKey(const ValueKey('loupe')), findsOneWidget, reason: 'loupe follows the keyboard-selected corner');
  });

  testWidgets('moving an edge stops at the image border (both ends stay inside)', (tester) async {
    final corners = ValueNotifier<List<Pt>>(const [Pt(100, 50), Pt(900, 150), Pt(900, 900), Pt(100, 900)]);
    await tester.pumpWidget(editor(corners));
    // Top edge midpoint at image (500, 100) -> screen (250, 50); drag far up.
    await tester.dragFrom(const Offset(250, 50), const Offset(0, -300));
    await tester.pump();
    expect(corners.value[0].y, 0);
    expect(corners.value[1].y, closeTo(100, 1e-6), reason: 'the edge keeps its slope');
  });

  test('rotating a point clockwise', () {
    // In a 400x300 image, the top-left pixel ends up at the top-right of the 300x400 result.
    expect(rotatePointClockwise(const Pt(0, 0), 400, 300), const Pt(299, 0));
    expect(rotatePointClockwise(const Pt(399, 299), 400, 300), const Pt(0, 399));
  });

  group('adjust page', () {
    testWidgets('buttons have text labels; Cancel closes without a result', (tester) async {
      CornerAdjustResult? result;
      var closed = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage))],
        child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<CornerAdjustResult>(MaterialPageRoute(
                  builder: (_) => CornerAdjustPage(bytes: _png, width: 1000, height: 1000, corners: start),
                ));
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in ['Cancel', 'Reset corners', 'Use full photo', 'Rotate', 'Confirm']) {
        expect(button(label), findsOneWidget, reason: label);
      }
      // Reset is disabled until the corners change.
      expect(tester.widget<ButtonStyleButton>(button('Reset corners')).onPressed, isNull);
      await tester.tap(find.text('Use full photo'));
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(button('Reset corners')).onPressed, isNotNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('confirm returns the edited corners for the same photo', (tester) async {
      CornerAdjustResult? result;
      await tester.pumpWidget(ProviderScope(
        overrides: [scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage))],
        child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context).push<CornerAdjustResult>(MaterialPageRoute(
                builder: (_) => CornerAdjustPage(bytes: _png, width: 1000, height: 1000, corners: start),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use full photo'));
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(result!.corners, fullBounds(1000, 1000));
      expect(result!.rotated, isFalse);
      expect((result!.width, result!.height), (1000, 1000));
    });

    testWidgets('rotate turns the photo and its corners', (tester) async {
      CornerAdjustResult? result;
      final engine = FakeEngine(frameDetector: (_) => noPage);
      await tester.pumpWidget(ProviderScope(
        overrides: [scanEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context).push<CornerAdjustResult>(MaterialPageRoute(
                builder: (_) => CornerAdjustPage(
                  bytes: _png,
                  width: 400,
                  height: 300,
                  corners: const [Pt(10, 20), Pt(390, 20), Pt(390, 280), Pt(10, 280)],
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      expect(engine.processed.single.quarterTurns, 1);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect((result!.width, result!.height), (300, 400));
      expect(result!.rotated, isTrue);
      // TL (10,20) of the old photo is now the top-right corner: (300-1-20, 10).
      expect(result!.corners, const [Pt(19, 10), Pt(279, 10), Pt(279, 390), Pt(19, 390)]);
    });

    testWidgets('no page found: explains and starts from the full photo', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage))],
        child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: CornerAdjustPage(bytes: _png, width: 1000, height: 1000, corners: fullBounds(1000, 1000), detected: false),
        ),
      ));
      expect(find.text('No page edges found. Adjust the corners or keep the full photo.'), findsOneWidget);
    });
  });
}
