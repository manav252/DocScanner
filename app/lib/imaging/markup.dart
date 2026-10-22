// Markup (annotations) on a page: text boxes, pen, highlighter, signatures,
// rectangles, arrows, lines and whiteout boxes.
//
// Coordinates: positions are normalised to the rendered page (x / width,
// y / height, 0..1). Sizes (font size, stroke width, text box width, signature
// box) are in "units" = the page's shorter side, so a 90 degree rotation keeps
// every size unchanged. Items stay editable until export, where they are
// flattened into the page image.
import 'dart:math' as math;

import 'geometry.dart';

enum MarkupKind { text, pen, highlighter, signature, rect, arrow, line, whiteout }

enum TextBackground { none, white }

/// Named colours (every colour has a spoken name for screen readers).
enum MarkupColor {
  black('Black', 0xFF111111),
  blue('Blue', 0xFF1A4FD6),
  red('Red', 0xFFC62828),
  green('Green', 0xFF2E7D32),
  yellow('Yellow', 0xFFFFD400),
  white('White', 0xFFFFFFFF);

  const MarkupColor(this.label, this.argb);
  final String label;
  final int argb;

  static MarkupColor fromArgb(int v) => values.firstWhere((c) => c.argb == v, orElse: () => black);
}

sealed class MarkupItem {
  const MarkupItem(this.id);
  final String id;
  MarkupKind get kind;

  Map<String, Object?> toJson();

  /// Move by a normalised offset.
  MarkupItem translate(double dx, double dy);

  /// The same item after the page turns 90 degrees clockwise.
  MarkupItem rotatedClockwise();

  /// Re-express in a new crop of the same (rotated) page. [from]/[to] are the
  /// old and new crop rectangles (l, t, w, h); [unitScale] = old unit / new unit.
  MarkupItem recropped(List<double> from, List<double> to, double unitScale);

  /// Rough bounds in normalised page coordinates for hit testing (text boxes
  /// need their measured size in units, supplied by the painter).
  ({double l, double t, double r, double b}) bounds({double aspect = 1, double textHeight = 0, double textWidth = 0});

  static MarkupItem fromJson(Map<String, dynamic> j) {
    final kind = MarkupKind.values.byName(j['k'] as String);
    final id = j['id'] as String;
    double d(String k, [double def = 0]) => (j[k] as num?)?.toDouble() ?? def;
    List<Pt> pts(String k) {
      final v = (j[k] as List? ?? const []).cast<num>();
      return [for (var i = 0; i + 1 < v.length; i += 2) Pt(v[i].toDouble(), v[i + 1].toDouble())];
    }

    final color = (j['c'] as int?) ?? MarkupColor.black.argb;
    return switch (kind) {
      MarkupKind.text => TextMarkup(
          id: id,
          text: j['text'] as String? ?? '',
          x: d('x'),
          y: d('y'),
          width: d('w', 0.6),
          size: d('s', 0.04),
          color: color,
          bold: j['b'] as bool? ?? false,
          background: TextBackground.values.asNameMap()[j['bg']] ?? TextBackground.none,
          rotation: d('r'),
        ),
      MarkupKind.pen || MarkupKind.highlighter => StrokeMarkup(
          id: id,
          highlighter: kind == MarkupKind.highlighter,
          color: color,
          width: d('w', 0.006),
          points: pts('p'),
        ),
      MarkupKind.signature => SignatureMarkup(
          id: id,
          x: d('x'),
          y: d('y'),
          width: d('w', 0.4),
          height: d('h', 0.15),
          rotation: d('r'),
          color: color,
          strokes: [for (final s in (j['strokes'] as List? ?? const [])) _pts(s as List)],
        ),
      MarkupKind.rect || MarkupKind.arrow || MarkupKind.line || MarkupKind.whiteout => ShapeMarkup(
          id: id,
          kind: kind,
          color: color,
          width: d('w', 0.006),
          a: Pt(d('ax'), d('ay')),
          b: Pt(d('bx'), d('by')),
        ),
    };
  }

  static List<Pt> _pts(List v) =>
      [for (var i = 0; i + 1 < v.length; i += 2) Pt((v[i] as num).toDouble(), (v[i + 1] as num).toDouble())];
}

List<double> _flat(List<Pt> pts) => [for (final p in pts) ...[_r(p.x), _r(p.y)]];
double _r(double v) => (v * 10000).roundToDouble() / 10000;

Pt _rotPt(Pt p) => Pt(1 - p.y, p.x);
Pt _recrop(Pt p, List<double> from, List<double> to) =>
    Pt((from[0] + p.x * from[2] - to[0]) / to[2], (from[1] + p.y * from[3] - to[1]) / to[3]);

class TextMarkup extends MarkupItem {
  const TextMarkup({
    required String id,
    required this.text,
    required this.x,
    required this.y,
    this.width = 0.6,
    this.size = 0.04,
    this.color = 0xFF111111,
    this.bold = false,
    this.background = TextBackground.none,
    this.rotation = 0,
  }) : super(id);

  final String text;

  /// Centre of the text box (normalised).
  final double x, y;

  /// Box width and font size in units of the page's shorter side.
  final double width, size;
  final int color;
  final bool bold;
  final TextBackground background;

  /// Radians, clockwise.
  final double rotation;

  @override
  MarkupKind get kind => MarkupKind.text;

  TextMarkup copyWith({
    String? text,
    double? x,
    double? y,
    double? width,
    double? size,
    int? color,
    bool? bold,
    TextBackground? background,
    double? rotation,
  }) =>
      TextMarkup(
        id: id,
        text: text ?? this.text,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        size: size ?? this.size,
        color: color ?? this.color,
        bold: bold ?? this.bold,
        background: background ?? this.background,
        rotation: rotation ?? this.rotation,
      );

  @override
  Map<String, Object?> toJson() => {
        'k': kind.name,
        'id': id,
        'text': text,
        'x': _r(x),
        'y': _r(y),
        'w': _r(width),
        's': _r(size),
        'c': color,
        'b': bold,
        'bg': background.name,
        'r': _r(rotation),
      };

  @override
  TextMarkup translate(double dx, double dy) => copyWith(x: x + dx, y: y + dy);

  @override
  TextMarkup rotatedClockwise() {
    final p = _rotPt(Pt(x, y));
    return copyWith(x: p.x, y: p.y, rotation: rotation + math.pi / 2);
  }

  @override
  TextMarkup recropped(List<double> from, List<double> to, double unitScale) {
    final p = _recrop(Pt(x, y), from, to);
    return copyWith(x: p.x, y: p.y, width: width * unitScale, size: size * unitScale);
  }

  @override
  ({double l, double t, double r, double b}) bounds({double aspect = 1, double textHeight = 0, double textWidth = 0}) {
    // aspect = width / height of the page; units -> normalised x/y.
    final ux = aspect >= 1 ? 1 / aspect : 1.0, uy = aspect >= 1 ? 1.0 : aspect;
    final hw = (textWidth > 0 ? textWidth : width) * ux / 2, hh = (textHeight > 0 ? textHeight : size * 1.4) * uy / 2;
    return (l: x - hw, t: y - hh, r: x + hw, b: y + hh);
  }
}

class StrokeMarkup extends MarkupItem {
  const StrokeMarkup({required String id, required this.highlighter, required this.color, required this.width, required this.points})
      : super(id);
  final bool highlighter;
  final int color;

  /// Stroke width in units of the page's shorter side.
  final double width;
  final List<Pt> points;

  @override
  MarkupKind get kind => highlighter ? MarkupKind.highlighter : MarkupKind.pen;

  StrokeMarkup withPoints(List<Pt> p) => StrokeMarkup(id: id, highlighter: highlighter, color: color, width: width, points: p);

  @override
  Map<String, Object?> toJson() => {'k': kind.name, 'id': id, 'c': color, 'w': _r(width), 'p': _flat(points)};

  @override
  StrokeMarkup translate(double dx, double dy) => withPoints([for (final p in points) Pt(p.x + dx, p.y + dy)]);

  @override
  StrokeMarkup rotatedClockwise() => withPoints([for (final p in points) _rotPt(p)]);

  @override
  StrokeMarkup recropped(List<double> from, List<double> to, double unitScale) => StrokeMarkup(
        id: id,
        highlighter: highlighter,
        color: color,
        width: width * unitScale,
        points: [for (final p in points) _recrop(p, from, to)],
      );

  @override
  ({double l, double t, double r, double b}) bounds({double aspect = 1, double textHeight = 0, double textWidth = 0}) {
    final xs = points.map((p) => p.x), ys = points.map((p) => p.y);
    return (l: xs.reduce(math.min), t: ys.reduce(math.min), r: xs.reduce(math.max), b: ys.reduce(math.max));
  }
}

class ShapeMarkup extends MarkupItem {
  const ShapeMarkup({required String id, required this.kind, required this.color, required this.width, required this.a, required this.b})
      : super(id);
  @override
  final MarkupKind kind;
  final int color;
  final double width;

  /// Start/end (line, arrow) or opposite corners (rect, whiteout), normalised.
  final Pt a, b;

  ShapeMarkup copyWith({Pt? a, Pt? b, int? color, double? width}) =>
      ShapeMarkup(id: id, kind: kind, color: color ?? this.color, width: width ?? this.width, a: a ?? this.a, b: b ?? this.b);

  @override
  Map<String, Object?> toJson() =>
      {'k': kind.name, 'id': id, 'c': color, 'w': _r(width), 'ax': _r(a.x), 'ay': _r(a.y), 'bx': _r(b.x), 'by': _r(b.y)};

  @override
  ShapeMarkup translate(double dx, double dy) => copyWith(a: Pt(a.x + dx, a.y + dy), b: Pt(b.x + dx, b.y + dy));

  @override
  ShapeMarkup rotatedClockwise() => copyWith(a: _rotPt(a), b: _rotPt(b));

  @override
  ShapeMarkup recropped(List<double> from, List<double> to, double unitScale) =>
      copyWith(a: _recrop(a, from, to), b: _recrop(b, from, to), width: width * unitScale);

  @override
  ({double l, double t, double r, double b}) bounds({double aspect = 1, double textHeight = 0, double textWidth = 0}) =>
      (l: math.min(a.x, b.x), t: math.min(a.y, b.y), r: math.max(a.x, b.x), b: math.max(a.y, b.y));
}

class SignatureMarkup extends MarkupItem {
  const SignatureMarkup({
    required String id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.strokes,
    this.rotation = 0,
    this.color = 0xFF1A4FD6,
  }) : super(id);

  /// Centre, normalised.
  final double x, y;

  /// Box size in units of the page's shorter side.
  final double width, height;
  final double rotation;
  final int color;

  /// Ink strokes inside the box, each point 0..1 of the box.
  final List<List<Pt>> strokes;

  SignatureMarkup copyWith({double? x, double? y, double? width, double? height, double? rotation, int? color}) =>
      SignatureMarkup(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        color: color ?? this.color,
        strokes: strokes,
      );

  @override
  MarkupKind get kind => MarkupKind.signature;

  @override
  Map<String, Object?> toJson() => {
        'k': kind.name,
        'id': id,
        'x': _r(x),
        'y': _r(y),
        'w': _r(width),
        'h': _r(height),
        'r': _r(rotation),
        'c': color,
        'strokes': [for (final s in strokes) _flat(s)],
      };

  @override
  SignatureMarkup translate(double dx, double dy) => copyWith(x: x + dx, y: y + dy);

  @override
  SignatureMarkup rotatedClockwise() {
    final p = _rotPt(Pt(x, y));
    return copyWith(x: p.x, y: p.y, rotation: rotation + math.pi / 2);
  }

  @override
  SignatureMarkup recropped(List<double> from, List<double> to, double unitScale) {
    final p = _recrop(Pt(x, y), from, to);
    return copyWith(x: p.x, y: p.y, width: width * unitScale, height: height * unitScale);
  }

  @override
  ({double l, double t, double r, double b}) bounds({double aspect = 1, double textHeight = 0, double textWidth = 0}) {
    final ux = aspect >= 1 ? 1 / aspect : 1.0, uy = aspect >= 1 ? 1.0 : aspect;
    return (l: x - width * ux / 2, t: y - height * uy / 2, r: x + width * ux / 2, b: y + height * uy / 2);
  }
}

List<Map<String, Object?>> markupToJson(List<MarkupItem> items) => [for (final i in items) i.toJson()];

List<MarkupItem> markupFromJson(List<dynamic>? j) => [
      for (final m in j ?? const [])
        if (m is Map) _tryParse(m.cast<String, dynamic>()),
    ].whereType<MarkupItem>().toList();

MarkupItem? _tryParse(Map<String, dynamic> m) {
  try {
    return MarkupItem.fromJson(m);
  } catch (_) {
    return null; // skip items from a newer app version
  }
}
