// ID card mode: recognise Aadhaar and PAN cards without an ML model, from the
// card's shape (ID-1 size, 85.6 x 54 mm: about 1.58 : 1) and the words and
// number patterns OCR finds on it. Also reads the main fields and masks an
// Aadhaar number for export.
import '../imaging/geometry.dart';
import '../services/ocr/ocr_result.dart';

enum IdCardType {
  aadhaar('aadhaar'),
  pan('pan'),

  /// Card-shaped, type not recognised (the user can pick one).
  other('id'),

  /// The user said this is not an ID card.
  none('none');

  const IdCardType(this.wireName);
  final String wireName;

  static IdCardType? fromWire(String? s) => s == null ? null : values.where((t) => t.wireName == s).firstOrNull;
}

/// Width : height of an ID-1 card (85.6 x 54 mm).
const idCardAspect = 85.6 / 54;

/// Whether a flattened page of [width] x [height] has an ID card's shape
/// (either orientation, within ~8%).
bool hasCardShape(double width, double height) {
  if (width <= 0 || height <= 0) return false;
  final r = width > height ? width / height : height / width;
  return (r - idCardAspect).abs() <= 0.08 * idCardAspect;
}

/// The flattened size of a page (as the warp makes it) from its corners.
(double, double) flatSize(List<Pt> corners) {
  final c = orderCorners(corners);
  final w = [c[1].distanceTo(c[0]), c[2].distanceTo(c[3])].reduce((a, b) => a > b ? a : b);
  final h = [c[3].distanceTo(c[0]), c[2].distanceTo(c[1])].reduce((a, b) => a > b ? a : b);
  return (w, h);
}

// Keywords and fragments of them (OCR often misreads a letter or two of a
// heading: "overnment of India", "INCOME TAX DEPARGOSNIOF").
const _aadhaarWords = [
  'aadhaar',
  'aadhar',
  'आधार',
  'government of india',
  'ment of india',
  'govt of india',
  'भारत सरकार',
  'unique identification',
  'uidai',
];
const _panWords = ['income tax', 'आयकर', 'permanent account', 'account number', 'tax department'];

/// 12 digits in 4-4-4 groups on one line; Aadhaar numbers never start with 0
/// or 1. Not part of a longer run (a 16-digit bank card number).
final aadhaarNumber = RegExp(r'(?<!\d ?)[2-9]\d{3} ?\d{4} ?\d{4}(?! ?\d)');

/// PAN: 5 letters, 4 digits, 1 letter.
final panNumber = RegExp(r'(?<![A-Z0-9])[A-Z]{5}[0-9]{4}[A-Z](?![A-Z0-9])');
final _date = RegExp(r'(?<!\d)(\d{2})[/-](\d{2})[/-](\d{4})(?!\d)');

class IdCardInfo {
  const IdCardInfo(this.type, {this.fields = const {}});
  final IdCardType type;

  /// 'name', 'dob', 'number' (whatever could be read).
  final Map<String, String> fields;
}

int _hits(String lower, List<String> words) => words.where(lower.contains).length;

/// Classify a document from its pages' OCR [text] and whether they are
/// card-shaped. Null when it does not look like an ID card at all.
///
/// On a card-shaped page: the card's number pattern plus a keyword or a date
/// (the keywords are often misread, the numbers rarely). Any other page needs
/// the number and two keywords. A card-shaped page with a date or an ID-like
/// number but no known type is an [IdCardType.other]; a page of paragraphs is
/// not a card.
IdCardInfo? classifyIdCard({required String text, required bool cardShaped}) {
  final lower = text.toLowerCase();
  final aadhaarHits = _hits(lower, _aadhaarWords), panHits = _hits(lower, _panWords);
  final aNum = aadhaarNumber.firstMatch(text), pNum = panNumber.firstMatch(text.toUpperCase());
  final hasDate = _date.hasMatch(text);
  final bool aadhaar, pan;
  if (cardShaped) {
    aadhaar = aNum != null && (aadhaarHits >= 1 || hasDate);
    pan = pNum != null && (panHits >= 1 || hasDate);
  } else {
    aadhaar = aNum != null && aadhaarHits >= 2;
    pan = pNum != null && panHits >= 2;
  }
  if (!aadhaar && !pan) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final idLike = hasDate || RegExp(r'[A-Z0-9]{6,}').hasMatch(text.toUpperCase().replaceAll(' ', ''));
    return cardShaped && words <= 40 && idLike && RegExp(r'\d{4}').hasMatch(text)
        ? const IdCardInfo(IdCardType.other)
        : null;
  }
  if (pan && !aadhaar) return IdCardInfo(IdCardType.pan, fields: _fields(text, pNum?.group(0)));
  if (aadhaar && !pan) {
    final n = aNum?.group(0)?.replaceAll(RegExp(r'\s'), '');
    return IdCardInfo(
      IdCardType.aadhaar,
      fields: _fields(text, n == null ? null : '${n.substring(0, 4)} ${n.substring(4, 8)} ${n.substring(8)}'),
    );
  }
  return cardShaped ? const IdCardInfo(IdCardType.other) : null; // both patterns: let the user pick
}

/// Name, date of birth and number from the card's text. The name is the
/// line just above the date of birth (Aadhaar) or below the PAN, whichever
/// looks like a name: two or more words of letters only, not a heading.
Map<String, String> _fields(String text, String? number) {
  final lines = [
    for (final l in text.split('\n')) l.replaceAll(RegExp(r'^[^\p{L}\d]+|[^\p{L}\d]+$', unicode: true), ''),
  ];
  final out = <String, String>{'number': ?number};
  final dobLine = lines.indexWhere(_date.hasMatch);
  if (dobLine >= 0) {
    final m = _date.firstMatch(lines[dobLine])!;
    out['dob'] = '${m.group(1)}/${m.group(2)}/${m.group(3)}';
  }
  bool isName(String l) {
    final lower = l.toLowerCase();
    return RegExp(r'^[A-Za-z][A-Za-z.]*( [A-Za-z][A-Za-z.]*)+$').hasMatch(l) &&
        ![..._aadhaarWords, ..._panWords, 'govt', 'card', 'male', 'female', 'signature', 'name'].any(lower.contains);
  }

  final numberLine = number == null
      ? -1
      : lines.indexWhere((l) => l.replaceAll(' ', '').contains(number.replaceAll(' ', '')));
  final candidates = [
    if (numberLine >= 0 && numberLine + 1 < lines.length) numberLine + 1, // PAN: name under the number
    if (dobLine > 0) dobLine - 1, // Aadhaar: name above the date of birth
    for (var i = 0; i < lines.length; i++) i,
  ];
  for (final i in candidates) {
    if (isName(lines[i])) {
      out['name'] = lines[i];
      break;
    }
  }
  return out;
}

/// Where the first 8 digits of an Aadhaar number sit in [lines] (boxes
/// normalised to the page), and the text with them masked, for export.
/// Positions inside a line are estimated from the characters' share of it.
({List<({double l, double t, double r, double b})> boxes, List<OcrLine> lines, String text}) maskAadhaarNumber(
  List<OcrLine> lines,
) {
  final boxes = <({double l, double t, double r, double b})>[];
  final masked = <OcrLine>[];
  for (final line in lines) {
    final m = aadhaarNumber.firstMatch(line.text);
    if (m == null) {
      masked.add(line);
      continue;
    }
    // Index just after the 8th digit of the match.
    var digits = 0, end = m.start;
    while (end < m.end && digits < 8) {
      if (RegExp(r'\d').hasMatch(line.text[end])) digits++;
      end++;
    }
    final n = line.text.length;
    boxes.add((
      l: line.left + line.width * m.start / n,
      t: line.top,
      r: line.left + line.width * end / n,
      b: line.top + line.height,
    ));
    final hidden = line.text.substring(m.start, end).replaceAll(RegExp(r'\d'), 'X');
    final text = line.text.replaceRange(m.start, end, hidden);
    masked.add(OcrLine(text, line.left, line.top, line.width, line.height, confidence: line.confidence));
  }
  return (boxes: boxes, lines: masked, text: masked.map((l) => l.text).join('\n'));
}

/// The card's name in titles (document names stay in English, like the
/// card's own printed name).
String idCardTypeName(IdCardType t) => switch (t) {
  IdCardType.aadhaar => 'Aadhaar Card',
  IdCardType.pan => 'PAN Card',
  IdCardType.other || IdCardType.none => 'ID Card',
};

/// The title for a recognised card, e.g. "Aadhaar Card – 26 Oct 2026".
String idCardTitle(String label, DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '$label – ${d.day} ${months[d.month - 1]} ${d.year}';
}
