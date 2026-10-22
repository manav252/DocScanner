// ScanEngine for Android/iOS: runs opencv_dart on one long-lived
// background isolate so detection never blocks the UI thread.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../scan_engine.dart';
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
    final r = await _call(_Request(
      _Kind.frame,
      TransferableTypedData.fromList([f.bytes]),
      width: f.width,
      height: f.height,
      stride: f.rowStride,
      format: f.format.index,
    ));
    return _decodeDetection(r! as List<Object?>);
  }

  @override
  Future<EncodedDetection> detectEncoded(Uint8List bytes) async {
    final r = await _call(_Request(_Kind.encoded, TransferableTypedData.fromList([bytes]))) as List<Object?>;
    return (detection: _decodeDetection(r), width: r[3]! as int, height: r[4]! as int);
  }

  @override
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92}) async {
    final r = await _call(_Request(
      _Kind.warp,
      TransferableTypedData.fromList([bytes]),
      corners: Float64List.fromList([for (final p in corners) ...[p.x, p.y]]),
      maxSide: maxSide,
      quality: quality,
    ));
    return (r! as TransferableTypedData).materialize().asUint8List();
  }

  @override
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90}) async {
    final r = await _call(_Request(
      _Kind.process,
      TransferableTypedData.fromList([bytes]),
      edits: edits.toJson(),
      maxSide: maxSide ?? 0,
      quality: quality,
    ));
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

enum _Kind { frame, encoded, warp, process }

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
  });
  final _Kind kind;
  final TransferableTypedData bytes;
  final int width, height, stride, format, maxSide, quality;
  final Float64List? corners;
  final Map<String, Object>? edits;
}

// Wire format: [corners as 8 doubles, found, score, (width, height)]
List<Object?> _encodeDetection(Detection d, [int? w, int? h]) => [
      Float64List.fromList([for (final p in d.corners) ...[p.x, p.y]]),
      d.found,
      d.score,
      w,
      h,
    ];

Detection _decodeDetection(List<Object?> r) {
  final c = r[0]! as Float64List;
  return Detection([for (var i = 0; i < 4; i++) Pt(c[2 * i], c[2 * i + 1])],
      found: r[1]! as bool, score: r[2]! as double);
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
        } else {
          final cv.Mat result;
          if (req.kind == _Kind.warp) {
            final c = req.corners!;
            result = warpPerspectiveMat(m, [for (var i = 0; i < 4; i++) Pt(c[2 * i], c[2 * i + 1])], maxSide: req.maxSide);
          } else {
            result = applyEdits(m, PageEdits.fromJson(req.edits!), maxSide: req.maxSide == 0 ? null : req.maxSide);
          }
          final (ok, jpeg) = cv.imencode('.jpg', result, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, req.quality]));
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
      } else {
        final m = _matFrom(bytes, req.width, req.height, req.stride, 4);
        final gray = cv.cvtColor(m, format == PixelFormat.bgra ? cv.COLOR_BGRA2GRAY : cv.COLOR_RGBA2GRAY);
        d = detectDocumentMat(gray);
        m.dispose();
        gray.dispose();
      }
      out.send((id, true, _encodeDetection(d)));
    } catch (e) {
      out.send((id, false, e.toString()));
    }
  });
}
