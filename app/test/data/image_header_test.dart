import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/data/image_header.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';

void main() {
  test('JPEG and PNG sizes from headers', () {
    expect(imageHeaderSize(File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync()), (1200, 1600));
    expect(imageHeaderSize(File('${fixturesDir.path}/filters/input.png').readAsBytesSync()), (583, 800));
  });

  test('unknown data', () {
    expect(imageHeaderSize(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
