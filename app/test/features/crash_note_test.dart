// iPhone Safari can kill the page with no error to catch; the next launch
// says what the app was doing (web crash notes), and stops automatic text
// recognition if that is what died.
import 'package:docscanner/core/crash_note.dart';
import 'package:docscanner/features/common/crash_note_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

const ocrCrash = CrashNote(
  step: 'text recognition: page 799x1199',
  details: 'Closed during: text recognition: page 799x1199\nBrowser: iPhone',
);

void main() {
  test('only a crash while reading text turns automatic text recognition off', () {
    expect(diedReadingText(ocrCrash), isTrue);
    expect(diedReadingText(const CrashNote(step: 'image work: warpEncoded (360 KB)', details: '')), isFalse);
  });

  testWidgets('the note says what the app was doing, offers the details, and that recognition was turned off', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCrashNote(context, ocrCrash, ocrTurnedOff: true),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('The app closed unexpectedly'), findsOneWidget);
    expect(find.textContaining('It closed while: text recognition: page 799x1199'), findsOneWidget);
    expect(find.byKey(const ValueKey('crash-ocr-off')), findsOneWidget);
    expect(find.text('Copy details'), findsOneWidget);
    expect(find.textContaining('Browser: iPhone'), findsOneWidget);
  });
}
