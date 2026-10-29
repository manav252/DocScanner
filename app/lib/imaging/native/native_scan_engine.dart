// ScanEngine for Android/iOS: runs opencv_dart on one long-lived
// background isolate so detection never blocks the UI thread.
import 'dart:async';
import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../scan_engine.dart';
import '../detector_params.dart';
import '../geometry.dart';
import '../page_edits.dart';
import 'opencv_filters.dart';
import 'opencv_detector.dart';

ScanEngine createScanEngine() => NativeScanEngine();

class NativeScanEngine implements ScanEngine {
  NativeScanEngine() {
    _receive.listen(_onMessage);
    Isolate.spawn(_worker, _receive.sendPort, debugName: 'document-detector').then((i) => _isolate = i);
  }

  final _receive = ReceivePort();
  final _sendPort = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  var _nextId = 0;

  @override
  Future<void> get ready => _sendPort.future;

  void _onMessage(dynamic msg) {
    if (msg is SendPort) {
      _sendPort.complete(msg);
      return;
    }
    final (id, ok, payload) = msg as (int, bool, Object?);
    final c = _pending.remove(id);
    if (c == null) return;
    ok ? c.complete(payload) : c.completeError(StateError(payload as String));
  }

  Future<Object?> _call(_Request req) async {
    final port = await _sendPort.future;
    final id = _nextId++;
    final c = _pending[id] = Completer<Object?>();
    port.send((id, req));
    return c.future;
  }

  @override
  Future<Detection> detectFrame(FrameData f) async {
    final yuv = f.format == PixelFormat.yuv420;
    final r = await _call(
      _Request(
        _Kind.frame,
        // Y, U, V one after the other; the split is in yLength/uLength.
        TransferableTypedData.fromList([f.bytes, if (yuv) f.u!, if (yuv) f.v!]),
        width: f.width,
        height: f.height,
        stride: f.rowStride,
        format: f.format.index,
        yLength: yuv ? f.bytes.length : 0,
        uLength: yuv ? f.u!.length : 0,
        uvStride: f.uvRowStride,
        uvPixelStride: f.uvPixelStride,
      ),
    );
    return _decodeDetection(r! as List<Object?>);
  }

  @override
  Future<EncodedDetection> detectEncoded(Uint8List bytes) async {
    final r = await _call(_Request(_Kind.encoded, TransferableTypedData.fromList([bytes]))) as List<Object?>;
    return (detection: _decodeDetection(r), width: r[3]! as int, height: r[4]! as int);
  }

  @override
  Future<NormalizedImage> normalizeEncoded(Uint8List bytes, {int maxSide = 4000, int quality = 92}) async {
    final r = await _call(
      _Request(_Kind.normalize, TransferableTypedData.fromList([bytes]), maxSide: maxSide, quality: quality),
    ) as List<Object?>;
    return (
      bytes: (r[0]! as TransferableTypedData).materialize().asUint8List(),
      width: r[1]! as int,
      height: r[2]! as int,
    );
  }

  @override
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92}) async {
    final r = await _call(
      _Request(
        _Kind.warp,
        TransferableTypedData.fromList([bytes]),
        corners: Float64List.fromList([
          for (final p in corners) ...[p.x, p.y],
        ]),
        maxSide: maxSide,
        quality: quality,
      ),
    );
    return (r! as TransferableTypedData).materialize().asUint8List();
  }

  @override
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90}) async {
    final r = await _call(
      _Request(
        _Kind.process,
        TransferableTypedData.fromList([bytes]),
        edits: edits.toJson(),
        maxSide: maxSide ?? 0,
        quality: quality,
      ),
    );
    return (r! as TransferableTypedData).materialize().asUint8List();
  }

  @override
  Future<Uint8List> prepareOcrEncoded(Uint8List bytes, {bool contrast = false, int quality = 92}) async {
    final r = await _call(
      _Request(_Kind.ocr, TransferableTypedData.fromList([bytes]), contrast: contrast, quality: quality),
    );
    return (r! as TransferableTypedData).materialize().asUint8List();
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receive.close();
    for (final c in _pending.values) {
      c.completeError(StateError('detector disposed'));
    }
    _pending.clear();
  }
}

enum _Kind { frame, encoded, warp, process, normalize, ocr }

class _Request {
  _Request(
    this.kind,
    this.bytes, {
    this.width = 0,
    this.height = 0,
    this.stride = 0,
    this.format = 0,
    this.corners,
    this.edits,
    this.maxSide = 0,
    this.quality = 0,
    this.contrast = false,
    this.yLength = 0,
    this.uLength = 0,
    this.uvStride = 0,
    this.uvPixelStride = 1,
  });
  final _Kind kind;
  final TransferableTypedData bytes;
  final int width, height, stride, format, maxSide, quality;

  /// YUV frames: where the U and V planes start in [bytes], and their layout.
  final int yLength, uLength, uvStride, uvPixelStride;

  /// OCR input: the grayscale + CLAHE variant.
  final bool contrast;
  final Float64List? corners;
  final Map<String, Object>? edits;
}

// Wire format: [corners as 8 doubles, found, score, (width, height)]
List<Object?> _encodeDetection(Detection d, [int? w, int? h]) => [
  Float64List.fromList([
    for (final p in d.corners) ...[p.x, p.y],
  ]),
  d.found,
  d.score,
  w,
  h,
];

Detection _decodeDetection(List<Object?> r) {
  final c = r[0]! as Float64List;
  return Detection(
    [for (var i = 0; i < 4; i++) Pt(c[2 * i], c[2 * i + 1])],
    found: r[1]! as bool,
    score: r[2]! as double,
  );
}

/// An Android YUV_420_888 frame: converted to colour at detection size (the
/// brightness plane shrunk, the half-size colour planes scaled to match), then
/// detected like a web frame. Corners are returned in frame pixels.
Detection _detectYuv(Uint8List all, _Request req) {
  final w = req.width, h = req.height;
  final scale = math.min(1.0, DetectorParams.maxDim / math.max(w, h));
  final size = (math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
  final yFull = _matFrom(Uint8List.sublistView(all, 0, req.yLength), w, h, req.stride, 1);
  final y = scale < 1 ? cv.resize(yFull, size, interpolation: cv.INTER_AREA) : yFull.clone();
  yFull.dispose();
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
  cv.Mat chroma(int start, int length) {
    final src = Uint8List.sublistView(all, start, start + length);
    final dense = Uint8List(cw * ch);
    final ps = req.uvPixelStride, rs = req.uvStride;
    for (var r = 0; r < ch; r++) {
      final row = r * rs;
      for (var c = 0; c < cw; c++) {
        final i = row + c * ps;
        dense[r * cw + c] = i < src.length ? src[i] : 128;
      }
    }
    final half = cv.Mat.fromList(ch, cw, cv.MatType.CV_8UC1, dense);
    final out = cv.resize(half, size, interpolation: cv.INTER_LINEAR);
    half.dispose();
    return out;
  }

  final u = chroma(req.yLength, req.uLength);
  final v = chroma(req.yLength + req.uLength, all.length - req.yLength - req.uLength);
  final yuv = cv.merge(cv.VecMat.fromList([y, u, v]));
  final bgr = cv.cvtColor(yuv, cv.COLOR_YUV2BGR);
  for (final m in [y, u, v, yuv]) {
    m.dispose();
  }
  final d = detectDocumentMat(bgr);
  bgr.dispose();
  if (scale >= 1) return d;
  return Detection(
    [
      for (final p in d.corners)
        Pt(
          ((p.x + 0.5) / scale - 0.5).clamp(0, w - 1).toDouble(),
          ((p.y + 0.5) / scale - 0.5).clamp(0, h - 1).toDouble(),
        ),
    ],
    found: d.found,
    score: d.score,
  );
}

/// Pack a possibly row-padded buffer into a dense Mat.
cv.Mat _matFrom(Uint8List b, int w, int h, int stride, int channels) {
  final rowBytes = w * channels;
  final Uint8List dense;
  if (stride == rowBytes) {
    dense = Uint8List.sublistView(b, 0, rowBytes * h);
  } else {
    dense = Uint8List(rowBytes * h);
    for (var r = 0; r < h; r++) {
      dense.setRange(r * rowBytes, (r + 1) * rowBytes, b, r * stride);
    }
  }
  return cv.Mat.fromList(h, w, channels == 1 ? cv.MatType.CV_8UC1 : cv.MatType.CV_8UC4, dense);
}

void _worker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((msg) {
    final (id, req) = msg as (int, _Request);
    try {
      final bytes = req.bytes.materialize().asUint8List();
      if (req.kind != _Kind.frame) {
        final m = cv.imdecode(bytes, cv.IMREAD_COLOR);
        if (m.isEmpty) throw ArgumentError('could not decode image');
        if (req.kind == _Kind.encoded) {
          out.send((id, true, _encodeDetection(detectDocumentMat(m), m.cols, m.rows)));
        } else if (req.kind == _Kind.normalize) {
          // imdecode already applied the EXIF orientation; imencode writes no EXIF.
          final longest = m.cols > m.rows ? m.cols : m.rows;
          final scaled = longest > req.maxSide
              ? cv.resize(m, (
                  (m.cols * req.maxSide / longest).round(),
                  (m.rows * req.maxSide / longest).round(),
                ), interpolation: cv.INTER_AREA)
              : m.clone();
          final (ok, jpeg) = cv.imencode(
            '.jpg',
            scaled,
            params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, req.quality]),
          );
          final size = (scaled.cols, scaled.rows);
          scaled.dispose();
          if (!ok) throw StateError('JPEG encoding failed');
          out.send((
            id,
            true,
            [
              TransferableTypedData.fromList([jpeg]),
              size.$1,
              size.$2,
            ],
          ));
        } else {
          final cv.Mat result;
          if (req.kind == _Kind.ocr) {
            result = prepareOcr(m, contrast: req.contrast);
          } else if (req.kind == _Kind.warp) {
            final c = req.corners!;
            result = warpPageMat(m, [for (var i = 0; i < 4; i++) Pt(c[2 * i], c[2 * i + 1])], maxSide: req.maxSide);
          } else {
            result = applyEdits(m, PageEdits.fromJson(req.edits!), maxSide: req.maxSide == 0 ? null : req.maxSide);
          }
          final (ok, jpeg) = cv.imencode(
            '.jpg',
            result,
            params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, req.quality]),
          );
          result.dispose();
          if (!ok) throw StateError('JPEG encoding failed');
          out.send((id, true, TransferableTypedData.fromList([jpeg])));
        }
        m.dispose();
        return;
      }
      final format = PixelFormat.values[req.format];
      Detection d;
      if (format == PixelFormat.luma) {
        d = detectDocumentLuma(bytes, req.width, req.height, rowStride: req.stride);
      } else if (format == PixelFormat.yuv420) {
        d = _detectYuv(bytes, req);
      } else {
        // Colour in, like the web: the saturation pass needs it.
        final m = _matFrom(bytes, req.width, req.height, req.stride, 4);
        final bgr = cv.cvtColor(m, format == PixelFormat.bgra ? cv.COLOR_BGRA2BGR : cv.COLOR_RGBA2BGR);
        d = detectDocumentMat(bgr);
        m.dispose();
        bgr.dispose();
      }
      out.send((id, true, _encodeDetection(d)));
    } catch (e) {
      out.send((id, false, e.toString()));
    }
  });
}
