// Recognised text of a page, with line boxes for the searchable-PDF text layer.

class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.width, this.height, {this.confidence = 1.0});
  final String text;

  /// Box normalised to the page image (0..1).
  final double left, top, width, height;

  /// Engine confidence 0..1 (1.0 when the engine does not report one).
  final double confidence;

  List<Object> toJson() => [text, left, top, width, height, confidence];
  static OcrLine fromJson(List<dynamic> j) => OcrLine(j[0] as String, (j[1] as num).toDouble(), (j[2] as num).toDouble(),
      (j[3] as num).toDouble(), (j[4] as num).toDouble(),
      confidence: j.length > 5 ? (j[5] as num).toDouble() : 1.0);
}

class OcrResult {
  const OcrResult(this.text, this.lines);
  final String text;
  final List<OcrLine> lines;

  static const empty = OcrResult('', []);

  Map<String, Object> toJson() => {'text': text, 'lines': [for (final l in lines) l.toJson()]};
  static OcrResult fromJson(Map<String, dynamic> j) =>
      OcrResult(j['text'] as String? ?? '', [for (final l in (j['lines'] as List? ?? const [])) OcrLine.fromJson(l as List)]);
}

final _edgeJunk = RegExp(r'^[\s|\[\]{}!¦]+|[\s|\[\]{}!¦]+$');
final _wordChar = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);

/// Lines below this confidence are dropped.
const minOcrConfidence = 0.5;

/// A line counts as text when at least half its visible characters are
/// letters/digits (any script, Devanagari included). Mirrors web/ocr/ocr.js.
bool meaningfulText(String text) {
  final visible = text.replaceAll(RegExp(r'\s'), '');
  if (visible.length < 2) return false;
  final word = _wordChar.allMatches(visible).length;
  return word >= 2 && word / visible.length >= 0.5;
}

/// Remove OCR noise: low-confidence lines, page borders and table rules read as
/// "|", "[" or "!" at the ends of lines, and lines without real words. A photo
/// with no text ends up with no lines (shown as "No text found on this page").
OcrResult cleanOcr(OcrResult r) {
  final lines = <OcrLine>[
    for (final l in r.lines)
      if (l.confidence >= minOcrConfidence)
        if (l.text.replaceAll(_edgeJunk, '') case final t when meaningfulText(t))
          OcrLine(t, l.left, l.top, l.width, l.height, confidence: l.confidence),
  ];
  return OcrResult(lines.map((l) => l.text).join('\n'), lines);
}
