// ID card mode without an ML model: card shape + OCR keywords and number
// patterns. Run against real OCR output of the fake cards
// (shared/test_fixtures/hard/ocr_texts.json, made by test_js/eval_ocr.js).
import 'dart:convert';
import 'dart:io';

import 'package:docscanner/data/id_card.dart';
import 'package:docscanner/services/ocr/ocr_result.dart';
import 'package:flutter_test/flutter_test.dart';

final texts =
    jsonDecode(File('../shared/test_fixtures/hard/ocr_texts.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('Aadhaar and PAN cards are labelled from their OCR text; ordinary pages are not ID cards', () {
    final wrong = <String>[];
    var fields = 0, fieldsRight = 0;
    final perField = <String, int>{};
    for (final MapEntry(key: file, value: e as Map<String, dynamic>) in texts.entries) {
      final shaped = hasCardShape((e['width'] as num).toDouble(), (e['height'] as num).toDouble());
      final info = classifyIdCard(text: e['text'] as String, cardShaped: shaped);
      final truth = e['fields'] as Map<String, dynamic>?;
      final expected = truth == null ? null : (truth['type'] == 'aadhaar' ? IdCardType.aadhaar : IdCardType.pan);
      if (info?.type != expected) wrong.add('$file: ${info?.type} (expected $expected)');
      if (truth != null && info != null) {
        for (final k in ['name', 'dob', 'number']) {
          fields++;
          if (info.fields[k]?.toLowerCase() == (truth[k] as String).toLowerCase()) {
            fieldsRight++;
            perField[k] = (perField[k] ?? 0) + 1;
          }
        }
      }
    }
    // ignore: avoid_print
    print(
      'ID card type: ${texts.length - wrong.length}/${texts.length} right; fields read: $fieldsRight/$fields $perField',
    );
    expect(wrong, isEmpty);
    expect(fieldsRight / fields, greaterThan(0.85));
  });

  test('card shape: ID-1 in either orientation; A4 and receipts are not', () {
    expect(hasCardShape(856, 540), isTrue);
    expect(hasCardShape(540, 856), isTrue);
    expect(hasCardShape(2480, 3508), isFalse);
    expect(hasCardShape(420, 1200), isFalse);
  });

  test('a letter that mentions Aadhaar once is not an Aadhaar card', () {
    expect(classifyIdCard(text: 'Please bring your Aadhaar to the office.\nRegards', cardShaped: false), isNull);
    expect(
      classifyIdCard(text: 'Library card\nMember 4512 0098\nValid to 12/08/2027', cardShaped: true)!.type,
      IdCardType.other,
    );
    expect(
      classifyIdCard(text: 'HDFC BANK\n4512 3456 7890 1234\nVALID THRU 12/28', cardShaped: true)!.type,
      IdCardType.other,
      reason: 'a 16-digit bank card number is not an Aadhaar number',
    );
  });

  test('masking: the first 8 digits are hidden in the text and boxed for the image', () {
    final r = maskAadhaarNumber(const [
      OcrLine('Asha Verma', 0.3, 0.2, 0.3, 0.05),
      OcrLine('2345 6789 0123', 0.2, 0.75, 0.56, 0.08),
    ]);
    expect(r.text, 'Asha Verma\nXXXX XXXX 0123');
    expect(r.boxes, hasLength(1));
    final b = r.boxes.single;
    expect(b.l, closeTo(0.2, 1e-9));
    expect(b.r, closeTo(0.2 + 0.56 * 9 / 14, 1e-9), reason: '"2345 6789" is 9 of the 14 characters');
    expect(b.t, 0.75);
    expect(b.b, closeTo(0.83, 1e-9));
  });

  test('title: "Aadhaar Card – 26 Oct 2026"', () {
    expect(idCardTitle('Aadhaar Card', DateTime(2026, 10, 26)), 'Aadhaar Card – 26 Oct 2026');
  });
}
