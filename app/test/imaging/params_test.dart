import 'dart:convert';

import 'package:docscanner/imaging/detector_params.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('DetectorParams mirrors shared/detector_params.json', () {
    expect(jsonDecode(jsonEncode(DetectorParams.toJson())), sharedParams);
  });
}
