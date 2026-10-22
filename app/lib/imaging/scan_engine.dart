// Platform-neutral entry point for the image-processing engine
// (document detection, perspective correction, filters).
//
//   Android / iOS : opencv_dart (native OpenCV) on a long-lived background isolate
//   Web           : opencv.js (WASM) in a Web Worker (web/opencv/scanner_worker.js)
//
// Both run the same pipeline as scanner_core (Python) and are tested against
// the same fixtures. UI code depends only on this file.
import 'dart:typed_data';

import 'geometry.dart';
import 'page_edits.dart';
import 'unsupported_engine.dart'
    if (dart.library.js_interop) 'web/web_scan_engine.dart'
    if (dart.library.io) 'native/native_scan_engine.dart';

/// Pixel layout of a raw camera/canvas frame.
enum PixelFormat {
  /// 1 byte per pixel: the Y plane of YUV420/NV21 (Android camera).
  luma,

  /// 4 bytes per pixel, B G R A (iOS camera).
  bgra,

  /// 4 bytes per pixel, R G B A (browser canvas ImageData).
  rgba,
}

class FrameData {
  const FrameData({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    int? rowStride,
  }) : rowStride = rowStride ?? width * (format == PixelFormat.luma ? 1 : 4);

  final Uint8List bytes;
  final int width, height;

  /// Bytes per row (camera buffers are often padded).
  final int rowStride;
  final PixelFormat format;
}

/// A decoded still image (gallery import / captured photo) with its detection.
typedef EncodedDetection = ({Detection detection, int width, int height});

abstract interface class ScanEngine {
  /// Creates the implementation for the current platform.
  factory ScanEngine() => createScanEngine();

  /// Completes once the engine is loaded (opencv.js WASM can take ~1 s on web).
  Future<void> get ready;

  /// Detect on a raw frame. Corners are in frame pixels.
  Future<Detection> detectFrame(FrameData frame);

  /// Decode JPEG/PNG/WebP bytes and detect.
  Future<EncodedDetection> detectEncoded(Uint8List bytes);

  /// Flatten the quad [corners] (source pixels, any order) of the encoded
  /// photo [bytes] to a rectangle. Returns a JPEG.
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92});

  /// Apply [edits] (filter -> rotate -> crop) to an encoded flattened page.
  /// Optionally downscale to [maxSide] (thumbnails). Returns a JPEG.
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90});

  void dispose();
}
