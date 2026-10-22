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
  final _recognizer = mlkit.TextRecognizer(script: mlkit.TextRecognitionScript.latin);
  var _counter = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<OcrResult> recognize(Uint8List image) async {
    final size = imageHeaderSize(image);
    if (size == null) throw ArgumentError('unsupported image');
    final (w, h) = size;
    // ML Kit reads encoded images from a file.
    final file = File('${(await getTemporaryDirectory()).path}/ocr_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg');
    await file.writeAsBytes(image, flush: true);
    try {
      final r = await _recognizer.processImage(mlkit.InputImage.fromFilePath(file.path));
      final lines = <OcrLine>[
        for (final block in r.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              OcrLine(
                line.text.trim(),
                (line.boundingBox.left / w).clamp(0.0, 1.0),
                (line.boundingBox.top / h).clamp(0.0, 1.0),
                (line.boundingBox.width / w).clamp(0.0, 1.0),
                (line.boundingBox.height / h).clamp(0.0, 1.0),
              ),
      ];
      return OcrResult(lines.map((l) => l.text).join('\n'), lines);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  void dispose() => _recognizer.close();
}
