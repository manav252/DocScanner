import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:docscanner/imaging/geometry.dart';

/// Shared fixtures live in ../shared (flutter test runs from the app root).
final fixturesDir = Directory('../shared/test_fixtures');
final spec = jsonDecode(File('${fixturesDir.path}/expected_corners.json').readAsStringSync()) as Map<String, dynamic>;
final pythonReference =
    jsonDecode(File('${fixturesDir.path}/python_reference.json').readAsStringSync()) as Map<String, dynamic>;
final sharedParams = jsonDecode(File('../shared/detector_params.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> get cases => spec['cases'] as Map<String, dynamic>;
int get imageWidth => (spec['image_size'] as List)[0] as int;
int get imageHeight => (spec['image_size'] as List)[1] as int;

/// 1% of the image diagonal (20 px on a 1200x1600 photo), same as the Python suite.
double get tolerance => 0.01 * math.sqrt(imageWidth * imageWidth + imageHeight * imageHeight);

List<Pt> cornersOf(dynamic json) => [for (final p in json as List) Pt.fromJson(p as List)];

double maxCornerError(List<Pt> a, List<Pt> b) =>
    [for (var i = 0; i < 4; i++) a[i].distanceTo(b[i])].reduce(math.max);
