import 'dart:typed_data';

import 'package:docscanner/features/corners/corner_adjust_page.dart';
import 'package:docscanner/features/corners/corner_editor.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


// 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, //
  137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174,
  66, 96, 130,
]);

const imageSize = Size(1000, 1000);
const start = [Pt(100, 100), Pt(900, 100), Pt(900, 900), Pt(100, 900)];

Widget editor(ValueNotifier<List<Pt>> corners) => MaterialApp(
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

  testWidgets('adjust page pops with the edited corners; whole-photo toggle works', (tester) async {
    List<Pt>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.of(context).push<List<Pt>>(MaterialPageRoute(
            builder: (_) => CornerAdjustPage(bytes: _png, width: 1000, height: 1000, corners: start),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Use whole photo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Use detected edges'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-corners')));
    await tester.pumpAndSettle();
    expect(result, start);
  });

  testWidgets('adjust page shows a hint when no page was detected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CornerAdjustPage(bytes: _png, width: 1000, height: 1000, corners: fullBounds(1000, 1000), detected: false),
    ));
    expect(find.textContaining("Couldn't find the page edges"), findsOneWidget);
  });
}
