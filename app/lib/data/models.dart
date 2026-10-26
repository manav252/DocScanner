// Documents and pages. A page keeps its original photo + corners + edits, so
// every step (corners, filter, rotation, crop) stays editable; the rendered
// image is derived from them.
import '../imaging/geometry.dart';
import 'id_card.dart';
import '../imaging/markup.dart';
import '../imaging/page_edits.dart';

/// Images stored per page.
enum PageImage {
  /// The original photo / imported image.
  source,

  /// Perspective-corrected, unfiltered.
  flat,

  /// flat + edits (filter, rotation, crop): what is shown and exported.
  render,

  /// Small JPEG of [render] for lists.
  thumb,
}

class ScanPage {
  const ScanPage({
    required this.id,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.corners,
    this.edits = const PageEdits(),
    this.revision = 0,
    this.renderWidth = 0,
    this.renderHeight = 0,
    this.ocrText,
    this.sourceVersion = 0,
    this.ocrRevision = -1,
    this.ocrLanguage,
    this.markup = const [],
  });

  final String id;
  final int sourceWidth, sourceHeight;

  /// TL, TR, BR, BL in source pixels.
  final List<Pt> corners;
  final PageEdits edits;

  /// Bumped whenever the rendered image changes (cache key for the UI).
  final int revision;
  final int renderWidth, renderHeight;

  /// Recognised text (OCR), if any.
  final String? ocrText;

  /// Bumped when the photo is replaced (retake), so sync knows to re-upload it.
  final int sourceVersion;

  /// The [revision] that [ocrText] was recognised from (-1: never).
  final int ocrRevision;

  /// Language [ocrText] was read in ('eng' / 'hin').
  final String? ocrLanguage;

  /// Editable annotations (text, ink, signature, shapes), flattened on export.
  final List<MarkupItem> markup;

  /// OCR is missing or outdated (the page was re-rendered since).
  bool get needsOcr => ocrRevision != revision;

  /// OCR is missing, outdated, or was read in a different language.
  bool needsOcrIn(String language) => needsOcr || (ocrLanguage ?? 'eng') != language;

  ScanPage copyWith({
    List<Pt>? corners,
    PageEdits? edits,
    int? revision,
    int? renderWidth,
    int? renderHeight,
    Object? ocrText = _keep,
    int? ocrRevision,
    String? ocrLanguage,
    List<MarkupItem>? markup,
  }) => ScanPage(
    id: id,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    corners: corners ?? this.corners,
    edits: edits ?? this.edits,
    revision: revision ?? this.revision,
    renderWidth: renderWidth ?? this.renderWidth,
    renderHeight: renderHeight ?? this.renderHeight,
    ocrText: identical(ocrText, _keep) ? this.ocrText : ocrText as String?,
    sourceVersion: sourceVersion,
    ocrRevision: ocrRevision ?? this.ocrRevision,
    ocrLanguage: ocrLanguage ?? this.ocrLanguage,
    markup: markup ?? this.markup,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sw': sourceWidth,
    'sh': sourceHeight,
    'corners': [for (final p in corners) p.toJson()],
    'edits': edits.toJson(),
    'rev': revision,
    'rw': renderWidth,
    'rh': renderHeight,
    if (ocrText != null) 'ocr': ocrText,
    'srcVer': sourceVersion,
    'ocrRev': ocrRevision,
    if (ocrLanguage != null) 'ocrLang': ocrLanguage,
    if (markup.isNotEmpty) 'markup': markupToJson(markup),
  };

  static ScanPage fromJson(Map<String, dynamic> j) => ScanPage(
    id: j['id'] as String,
    sourceWidth: j['sw'] as int,
    sourceHeight: j['sh'] as int,
    corners: [for (final p in j['corners'] as List) Pt.fromJson(p as List)],
    edits: PageEdits.fromJson((j['edits'] as Map).cast<String, dynamic>()),
    revision: j['rev'] as int? ?? 0,
    renderWidth: j['rw'] as int? ?? 0,
    renderHeight: j['rh'] as int? ?? 0,
    ocrText: j['ocr'] as String?,
    sourceVersion: j['srcVer'] as int? ?? 0,
    ocrRevision: j['ocrRev'] as int? ?? -1,
    ocrLanguage: j['ocrLang'] as String?,
    markup: markupFromJson(j['markup'] as List?),
  );
}

const _keep = Object();

class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pages = const [],
    this.revision = 0,
    this.remoteId,
    this.syncedRevision = -1,
    this.serverVersion,
    this.deleted = false,
    bool? backup,
    this.idCard,
    this.idFields = const {},
    this.idBackupApproved = false,
  }) : backup = backup ?? remoteId != null;

  final String id;
  final String title;
  final DateTime createdAt, updatedAt;
  final List<ScanPage> pages;

  /// Local change counter; the document needs uploading when it differs from [syncedRevision].
  final int revision;

  /// Server id once synced (Stage 5).
  final String? remoteId;
  final int syncedRevision;

  /// Server version this copy is based on (sent as base_version); null = never uploaded.
  final int? serverVersion;

  /// Tombstone kept until the deletion has been synced.
  final bool deleted;

  /// Back this document up to the signed-in account. Off for documents made as a
  /// guest until the user chooses to upload them (documents already on the
  /// server stay backed up).
  final bool backup;

  /// What kind of ID card this is (recognised or picked by the user); null =
  /// not decided yet, [IdCardType.none] = the user said it is not one.
  final IdCardType? idCard;

  /// Card details (name, dob, number), editable; kept on this device only.
  final Map<String, String> idFields;

  /// The user agreed to back this ID card up to their account.
  final bool idBackupApproved;

  /// Treated as an ID card: recognised or picked as one, or (not decided yet)
  /// every page has an ID card's shape. ID cards are never backed up without asking.
  bool get isIdCard => switch (idCard) {
    IdCardType.none => false,
    null =>
      pages.isNotEmpty &&
          pages.length <= 2 &&
          pages.every((p) {
            final (w, h) = flatSize(p.corners);
            return hasCardShape(w, h);
          }),
    _ => true,
  };

  bool get needsSync => revision != syncedRevision;

  /// Copy with a change: bumps [revision] and [updatedAt].
  ScanDocument edit({
    String? title,
    List<ScanPage>? pages,
    bool? deleted,
    DateTime? now,
    bool? backup,
    IdCardType? idCard,
    Map<String, String>? idFields,
    bool? idBackupApproved,
  }) => ScanDocument(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: now ?? DateTime.now(),
    pages: pages ?? this.pages,
    revision: revision + 1,
    remoteId: remoteId,
    syncedRevision: syncedRevision,
    serverVersion: serverVersion,
    deleted: deleted ?? this.deleted,
    backup: backup ?? this.backup,
    idCard: idCard ?? this.idCard,
    idFields: idFields ?? this.idFields,
    idBackupApproved: idBackupApproved ?? this.idBackupApproved,
  );

  /// Record that local [revision] is on the server at [serverVersion].
  ScanDocument markSynced({required String remoteId, required int revision, int? serverVersion}) => ScanDocument(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pages: pages,
    revision: this.revision,
    remoteId: remoteId,
    syncedRevision: revision,
    serverVersion: serverVersion ?? this.serverVersion,
    deleted: deleted,
    backup: true,
    idCard: idCard,
    idFields: idFields,
    idBackupApproved: idBackupApproved,
  );

  /// Forget everything about the server (e.g. a different account signed in);
  /// the user is asked again before it is uploaded anywhere.
  ScanDocument unsynced() => ScanDocument(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pages: pages,
    revision: revision,
    syncedRevision: -1,
    deleted: deleted,
    backup: false,
    idCard: idCard,
    idFields: idFields,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'created': createdAt.toUtc().toIso8601String(),
    'updated': updatedAt.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    'rev': revision,
    'remoteId': remoteId,
    'syncedRev': syncedRevision,
    if (serverVersion != null) 'serverVer': serverVersion,
    'deleted': deleted,
    'backup': backup,
    if (idCard != null) 'idCard': idCard!.wireName,
    if (idFields.isNotEmpty) 'idFields': idFields,
    if (idBackupApproved) 'idBackupOk': true,
  };

  static ScanDocument fromJson(Map<String, dynamic> j) => ScanDocument(
    id: j['id'] as String,
    title: j['title'] as String,
    createdAt: DateTime.parse(j['created'] as String).toLocal(),
    updatedAt: DateTime.parse(j['updated'] as String).toLocal(),
    pages: [for (final p in j['pages'] as List) ScanPage.fromJson((p as Map).cast<String, dynamic>())],
    revision: j['rev'] as int? ?? 0,
    remoteId: j['remoteId'] as String?,
    syncedRevision: j['syncedRev'] as int? ?? -1,
    serverVersion: j['serverVer'] as int?,
    deleted: j['deleted'] as bool? ?? false,
    backup: j['backup'] as bool?,
    idCard: IdCardType.fromWire(j['idCard'] as String?),
    idFields: {for (final e in ((j['idFields'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    idBackupApproved: j['idBackupOk'] as bool? ?? false,
  );

  /// Default title, e.g. "Scan 2026-10-22 18:30".
  static String defaultTitle(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
