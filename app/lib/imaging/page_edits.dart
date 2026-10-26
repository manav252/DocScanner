// Non-destructive per-page edits, applied to the flattened page in this order:
// filter -> rotate -> crop. Wire names match scanner_core (Python) and scanner.js.

enum PageFilter {
  original('original', 'Original'),
  grayscale('grayscale', 'Grayscale'),
  bw('bw', 'B&W'),
  magicColor('magic_color', 'Magic Color');

  const PageFilter(this.wireName, this.label);
  final String wireName;
  final String label;

  static PageFilter fromWire(String? s) => values.firstWhere((f) => f.wireName == s, orElse: () => magicColor);
}

/// Crop rectangle in normalised [0, 1] coordinates of the rotated page.
class CropRect {
  const CropRect(this.left, this.top, this.width, this.height)
    : assert(left >= 0 && top >= 0 && width > 0 && height > 0);

  static const full = CropRect(0, 0, 1, 1);

  final double left, top, width, height;

  bool get isFull => left <= 0.0005 && top <= 0.0005 && width >= 0.999 && height >= 0.999;

  /// Clamp into the unit square with a minimum size.
  CropRect normalized({double minSize = 0.05}) {
    final l = left.clamp(0.0, 1 - minSize), t = top.clamp(0.0, 1 - minSize);
    return CropRect(l, t, width.clamp(minSize, 1 - l), height.clamp(minSize, 1 - t));
  }

  /// The same region after the page is rotated a further 90 degrees clockwise.
  CropRect rotatedClockwise() => CropRect(1 - top - height, left, height, width);

  List<double> toJson() => [left, top, width, height];
  static CropRect fromJson(List<dynamic> j) =>
      CropRect((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is CropRect && other.left == left && other.top == top && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(left, top, width, height);
}

class PageEdits {
  const PageEdits({
    this.filter = PageFilter.magicColor,
    this.quarterTurns = 0,
    this.crop = CropRect.full,
    this.idCard = false,
  });

  static const none = PageEdits(filter: PageFilter.original);

  final PageFilter filter;

  /// Clockwise quarter turns (0-3).
  final int quarterTurns;
  final CropRect crop;

  /// The page is an ID card: B&W keeps the photo/signature strip grey, and the
  /// page is saved at a higher JPEG quality.
  final bool idCard;

  PageEdits copyWith({PageFilter? filter, int? quarterTurns, CropRect? crop, bool? idCard}) => PageEdits(
    filter: filter ?? this.filter,
    quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
    crop: crop ?? this.crop,
    idCard: idCard ?? this.idCard,
  );

  /// Rotate 90 degrees clockwise, keeping the same cropped region.
  PageEdits rotatedClockwise() => copyWith(quarterTurns: quarterTurns + 1, crop: crop.rotatedClockwise());

  Map<String, Object> toJson() => {
    'filter': filter.wireName,
    'turns': quarterTurns,
    'crop': crop.toJson(),
    if (idCard) 'card': true,
  };
  static PageEdits fromJson(Map<String, dynamic> j) => PageEdits(
    filter: PageFilter.fromWire(j['filter'] as String?),
    quarterTurns: (j['turns'] as int? ?? 0) % 4,
    crop: j['crop'] == null ? CropRect.full : CropRect.fromJson(j['crop'] as List),
    idCard: j['card'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is PageEdits &&
      other.filter == filter &&
      other.quarterTurns == quarterTurns &&
      other.crop == crop &&
      other.idCard == idCard;
  @override
  int get hashCode => Object.hash(filter, quarterTurns, crop, idCard);
}
