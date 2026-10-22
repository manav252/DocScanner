// On-device text recognition (OCR).
//   Android / iOS : Google ML Kit text recognition (Latin script)
//   Web           : Tesseract.js (WASM), self-hosted under web/ocr/
//   Other (desktop tests): unavailable
import 'dart:typed_data';

import 'ocr_result.dart';
import 'unsupported_recognizer.dart'
    if (dart.library.js_interop) 'web_text_recognizer.dart'
    if (dart.library.io) 'mlkit_text_recognizer.dart';

abstract interface class TextRecognizer {
  factory TextRecognizer() => createTextRecognizer();

  /// False where no OCR engine exists (e.g. desktop test runs).
  bool get isAvailable;

  /// Recognise text in a JPEG/PNG page image. [language] is 'eng' or 'hin'
  /// (Hindi also reads English, as documents often mix both).
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'});

  void dispose();
}

/// Used where OCR is not supported.
class UnavailableTextRecognizer implements TextRecognizer {
  const UnavailableTextRecognizer();
  @override
  bool get isAvailable => false;
  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) =>
      throw UnsupportedError('Text recognition is not available here');
  @override
  void dispose() {}
}
