// Recognised text of a page, with line boxes for the searchable-PDF text layer.

class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.width, this.height);
  final String text;

  /// Box normalised to the page image (0..1).
  final double left, top, width, height;

  List<Object> toJson() => [text, left, top, width, height];
  static OcrLine fromJson(List<dynamic> j) => OcrLine(j[0] as String, (j[1] as num).toDouble(), (j[2] as num).toDouble(),
      (j[3] as num).toDouble(), (j[4] as num).toDouble());
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
final _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Remove OCR noise: page borders and table rules read as "|", "[" or "!" at
/// the ends of lines, and lines without any letter or digit.
OcrResult cleanOcr(OcrResult r) {
  final lines = <OcrLine>[
    for (final l in r.lines)
      if (_hasWord.hasMatch(l.text))
        OcrLine(l.text.replaceAll(_edgeJunk, ''), l.left, l.top, l.width, l.height),
  ];
  return OcrResult(lines.map((l) => l.text).join('\n'), lines);
}
