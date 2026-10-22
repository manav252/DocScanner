// ML Kit on Android/iOS; unavailable on other dart:io platforms (desktop tests).
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' as mlkit;
import 'package:path_provider/path_provider.dart';

import '../../data/image_header.dart';
import 'ocr_result.dart';
import 'text_recognizer.dart';

TextRecognizer createTextRecognizer() =>
    Platform.isAndroid || Platform.isIOS ? MlKitTextRecognizer() : const UnavailableTextRecognizer();

class MlKitTextRecognizer implements TextRecognizer {
  // Devanagari model also reads Latin text; created on first Hindi use.
  final _recognizers = <String, mlkit.TextRecognizer>{};
  var _counter = 0;

  mlkit.TextRecognizer _for(String language) => _recognizers[language] ??= mlkit.TextRecognizer(
        script: language == 'hin' ? mlkit.TextRecognitionScript.devanagiri : mlkit.TextRecognitionScript.latin,
      );

  @override
  bool get isAvailable => true;

  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) async {
    final size = imageHeaderSize(image);
    if (size == null) throw ArgumentError('unsupported image');
    final (w, h) = size;
    // ML Kit reads encoded images from a file.
    final file = File('${(await getTemporaryDirectory()).path}/ocr_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg');
    await file.writeAsBytes(image, flush: true);
    try {
      final r = await _for(language).processImage(mlkit.InputImage.fromFilePath(file.path));
      final lines = <OcrLine>[];
      for (final block in r.blocks) {
        for (final line in block.lines) {
          // Drop low-confidence words (Android reports confidence; iOS may not).
          final words = [
            for (final e in line.elements)
              if (e.text.trim().isNotEmpty && (e.confidence ?? 1.0) >= minOcrConfidence) e,
          ];
          if (words.isEmpty) continue;
          final box = words.map((e) => e.boundingBox).reduce((a, b) => a.expandToInclude(b));
          final conf = words.map((e) => e.confidence ?? 1.0).reduce((a, b) => a + b) / words.length;
          lines.add(OcrLine(
            words.map((e) => e.text.trim()).join(' '),
            (box.left / w).clamp(0.0, 1.0),
            (box.top / h).clamp(0.0, 1.0),
            (box.width / w).clamp(0.0, 1.0),
            (box.height / h).clamp(0.0, 1.0),
            confidence: conf,
          ));
        }
      }
      return OcrResult(lines.map((l) => l.text).join('\n'), lines);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.close();
    }
  }
}
