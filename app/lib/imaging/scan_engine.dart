// Platform-neutral entry point for the image-processing engine
// (document detection, perspective correction, filters).
//
//   Android / iOS : opencv_dart (native OpenCV) on a long-lived background isolate
//   Web           : opencv.js (WASM) in a Web Worker (web/opencv/scanner_worker.js)
//
// Both run the same pipeline as scanner_core (Python) and are tested against
// the same fixtures. UI code depends only on this file.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

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

  /// Android camera YUV_420_888: [FrameData.bytes] is the Y plane (so it reads
  /// like [luma]); the colour planes are in [FrameData.u] / [FrameData.v].
  /// Detection converts it to colour at detection size, so the colour
  /// (saturation) pass runs as on the web.
  yuv420,
}

class FrameData {
  const FrameData({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    int? rowStride,
    this.u,
    this.v,
    this.uvRowStride = 0,
    this.uvPixelStride = 1,
  }) : rowStride = rowStride ?? width * (format == PixelFormat.luma || format == PixelFormat.yuv420 ? 1 : 4);

  final Uint8List bytes;
  final int width, height;

  /// Bytes per row (camera buffers are often padded).
  final int rowStride;
  final PixelFormat format;

  /// [PixelFormat.yuv420] only: the U and V planes (half size), their bytes
  /// per row and bytes between neighbouring samples (2 when interleaved).
  final Uint8List? u, v;
  final int uvRowStride, uvPixelStride;

  /// Bytes per pixel in [bytes]: 1 for a brightness plane, 4 for RGBA/BGRA.
  int get bytesPerPixel => format == PixelFormat.luma || format == PixelFormat.yuv420 ? 1 : 4;
}

/// A decoded still image (gallery import / captured photo) with its detection.
typedef EncodedDetection = ({Detection detection, int width, int height});

/// A photo re-encoded upright (EXIF orientation applied, tag removed) and capped in size.
typedef NormalizedImage = ({Uint8List bytes, int width, int height});

/// Longest side a photo is kept at when it enters the app. Pages are flattened
/// to at most 2480 px, so more only costs memory: on the web (iPhone Safari
/// kills a tab that uses too much) 3000 px, a 12 MP photo's copies then take
/// 27 MB each instead of 48 MB.
const photoMaxSide = kIsWeb ? 3000 : 4000;

abstract interface class ScanEngine {
  /// Creates the implementation for the current platform.
  factory ScanEngine() => createScanEngine();

  /// Completes once the engine is loaded (opencv.js WASM can take ~1 s on web).
  Future<void> get ready;

  /// Detect on a raw frame. Corners are in frame pixels.
  Future<Detection> detectFrame(FrameData frame);

  /// Normalise a photo as it enters the app: apply the EXIF orientation, cap the
  /// longest side at [maxSide], re-encode as JPEG without EXIF. Afterwards every
  /// decoder (Flutter, OpenCV, the browser, the PDF writer) sees the same pixels.
  Future<NormalizedImage> normalizeEncoded(Uint8List bytes, {int maxSide = 4000, int quality = 92});

  /// Decode JPEG/PNG/WebP bytes and detect.
  Future<EncodedDetection> detectEncoded(Uint8List bytes);

  /// Flatten the quad [corners] (source pixels, any order) of the encoded
  /// photo [bytes] to a rectangle. Returns a JPEG.
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92});

  /// Apply [edits] (filter -> rotate -> crop) to an encoded flattened page.
  /// Optionally downscale to [maxSide] (thumbnails). Returns a JPEG.
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90});

  /// The page image [bytes] prepared for text recognition: a small page (an ID
  /// card far from the camera) enlarged so its text is ~30 px tall or more, a
  /// large one capped; [contrast]: grayscale + CLAHE (the second try when the
  /// first finds little text). Returns a JPEG.
  Future<Uint8List> prepareOcrEncoded(Uint8List bytes, {bool contrast = false, int quality = 92});

  void dispose();
}
