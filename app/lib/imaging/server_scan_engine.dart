// ScanEngine that sends still-image work (detect / warp / filters) to the
// backend's POST /process, for devices too slow to run OpenCV comfortably.
// Live camera frames always stay on the device. Any server failure falls
// back to the local engine, so scanning keeps working offline.
import 'dart:convert';
import 'dart:typed_data';

import '../services/api/api_client.dart';
import 'geometry.dart';
import 'page_edits.dart';
import 'scan_engine.dart';

class ServerScanEngine implements ScanEngine {
  ServerScanEngine(this.local, this.api);
  final ScanEngine local;
  final ApiClient api;

  @override
  Future<void> get ready => local.ready;

  @override
  Future<Detection> detectFrame(FrameData frame) => local.detectFrame(frame);

  Future<T> _orLocal<T>(Future<T> Function() remote, Future<T> Function() fallback) async {
    try {
      return await remote();
    } on Exception {
      return fallback();
    }
  }

  @override
  Future<NormalizedImage> normalizeEncoded(Uint8List bytes, {int maxSide = 4000, int quality = 92}) =>
      local.normalizeEncoded(bytes, maxSide: maxSide, quality: quality);

  @override
  Future<EncodedDetection> detectEncoded(Uint8List bytes) => _orLocal(() async {
    final r = jsonDecode((await api.process(bytes, {'detect_only': 'true'})).body) as Map<String, dynamic>;
    return (
      detection: Detection(
        [for (final c in r['corners'] as List) Pt(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble())],
        found: r['found'] as bool,
        score: r['found'] as bool ? 1.0 : 0.0,
      ),
      width: r['width'] as int,
      height: r['height'] as int,
    );
  }, () => local.detectEncoded(bytes));

  @override
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92}) => _orLocal(
    () async => (await api.process(bytes, {
      'corners': jsonEncode([
        for (final c in corners) [c.x, c.y],
      ]),
      'filter': 'original',
      'max_side': '$maxSide',
      'quality': '$quality',
    })).bodyBytes,
    () => local.warpEncoded(bytes, corners, maxSide: maxSide, quality: quality),
  );

  @override
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90}) => _orLocal(
    () async => (await api.process(bytes, {
      'flat': 'true',
      'filter': edits.filter.wireName,
      'rotate': '${edits.quarterTurns}',
      if (!edits.crop.isFull) 'crop': jsonEncode(edits.crop.toJson()),
      'max_side': '${maxSide ?? 8000}',
      'quality': '$quality',
    })).bodyBytes,
    () => local.processEncoded(bytes, edits, maxSide: maxSide, quality: quality),
  );

  @override
  Future<Uint8List> prepareOcrEncoded(Uint8List bytes, {bool contrast = false, int quality = 92}) =>
      local.prepareOcrEncoded(bytes, contrast: contrast, quality: quality);

  @override
  void dispose() {} // the local engine is owned elsewhere
}
