// Edit / Markup: add text, pen, highlighter, eraser, signature, rectangle,
// arrow, line and whiteout to a page. Items stay editable until export.
// Every tool is a labelled button; selected items can be moved, resized,
// rotated and deleted with buttons or the keyboard as well as by dragging.
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/geometry.dart';
import '../../imaging/markup.dart';
import '../corners/corner_editor.dart' show fittedImageRect;
import '../editor/document_controller.dart';
import 'markup_model.dart';
import 'markup_painter.dart';
import 'signature_pad.dart';

enum MarkupTool { select, text, pen, highlighter, eraser, signature, rect, arrow, line, whiteout }

class MarkupEditorPage extends ConsumerStatefulWidget {
  const MarkupEditorPage({super.key, required this.documentId, required this.pageId});
  final String documentId, pageId;

  @override
  ConsumerState<MarkupEditorPage> createState() => MarkupEditorPageState();
}

@visibleForTesting
class MarkupEditorPageState extends ConsumerState<MarkupEditorPage> {
  MarkupHistory? history;
  Uint8List? _image;
  Size _pagePx = const Size(1000, 1414); // page aspect (render size)
  MarkupTool tool = MarkupTool.select;
  MarkupColor color = MarkupColor.black;
  int sizeStep = 1; // 0 small, 1 medium, 2 large
  bool bold = false;
  TextBackground background = TextBackground.none;
  String? selectedId;
  bool _saving = false;

  // Gesture state.
  Rect _pageRect = Rect.zero;
  List<MarkupItem>? _before;
  _Drag _drag = _Drag.none;
  Offset _lastScreen = Offset.zero;
  final _canvasFocus = FocusNode(debugLabel: 'markup canvas');

  static const _sizeFactor = [0.7, 1.0, 1.5];
  double get _k => _sizeFactor[sizeStep];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _canvasFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final doc = await ref.read(documentProvider(widget.documentId).future);
    final page = doc.pages.firstWhere((p) => p.id == widget.pageId);
    final bytes = await ref.read(documentRepositoryProvider).pageImage(page.id, PageImage.render);
    if (!mounted) return;
    setState(() {
      history = MarkupHistory(page.markup);
      _image = bytes;
      if (page.renderWidth > 0 && page.renderHeight > 0) {
        _pagePx = Size(page.renderWidth.toDouble(), page.renderHeight.toDouble());
      }
    });
  }

  List<MarkupItem> get items => history?.items ?? const [];
  MarkupItem? get selected => selectedId == null ? null : items.where((i) => i.id == selectedId).firstOrNull;

  // ---------- coordinates ----------

  Pt _norm(Offset o) => Pt(
    ((o.dx - _pageRect.left) / _pageRect.width).clamp(0.0, 1.0),
    ((o.dy - _pageRect.top) / _pageRect.height).clamp(0.0, 1.0),
  );

  Size get _shownSize => _pageRect.size;

  // ---------- edits ----------

  void _commit(List<MarkupItem> next, {String? select}) {
    setState(() {
      history!.commit(next);
      if (select != null) selectedId = select;
    });
  }

  void _announce(String msg) => SemanticsService.sendAnnouncement(View.of(context), msg, Directionality.of(context));

  String _newId() => const Uuid().v4();

  Future<String?> _askText({String initial = ''}) => showDialog<String>(
    context: context,
    builder: (c) {
      final ctl = TextEditingController(text: initial);
      final l = c.l10n;
      return AlertDialog(
        title: Text(l.typeText),
        content: TextField(
          key: const ValueKey('markup-text-field'),
          controller: ctl,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: InputDecoration(labelText: l.typeText),
        ),
        actions: [
          TextButton.icon(onPressed: () => Navigator.of(c).pop(), icon: const Icon(Icons.close), label: Text(l.cancel)),
          FilledButton.icon(
            key: const ValueKey('markup-text-ok'),
            onPressed: () => Navigator.of(c).pop(ctl.text),
            icon: const Icon(Icons.check),
            label: Text(l.done),
          ),
        ],
      );
    },
  );

  Future<void> addText(Pt at) async {
    final text = await _askText();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final item = TextMarkup(
      id: _newId(),
      text: text.trim(),
      x: at.x,
      y: at.y,
      size: 0.045 * _k,
      width: 0.6,
      color: color.argb,
      bold: bold,
      background: background,
    );
    _commit([...items, item], select: item.id);
    tool = MarkupTool.select;
  }

  Future<void> addSignature(Pt at) async {
    var sig = await ref.read(savedSignatureProvider.future);
    if (!mounted) return;
    sig ??= await drawSignature(context, ref);
    if (sig == null || !mounted) return;
    final w = 0.35 * _k;
    final item = SignatureMarkup(
      id: _newId(),
      x: at.x,
      y: at.y,
      width: w,
      height: w / sig.aspect,
      strokes: sig.strokes,
      color: color == MarkupColor.black ? MarkupColor.blue.argb : color.argb,
    );
    _commit([...items, item], select: item.id);
    tool = MarkupTool.select;
  }

  /// Shapes added with a button (no drag): a sensible box in the middle.
  void addShapeInMiddle(MarkupKind kind) {
    final dx = 0.2, dy = 0.08;
    final a = kind == MarkupKind.line || kind == MarkupKind.arrow ? Pt(0.5 - dx, 0.5) : Pt(0.5 - dx, 0.5 - dy);
    final b = kind == MarkupKind.line || kind == MarkupKind.arrow ? Pt(0.5 + dx, 0.5) : Pt(0.5 + dx, 0.5 + dy);
    final item = ShapeMarkup(id: _newId(), kind: kind, color: color.argb, width: 0.006 * _k, a: a, b: b);
    _commit([...items, item], select: item.id);
  }

  void updateSelected(MarkupItem Function(MarkupItem) f) {
    final id = selectedId;
    if (id == null) return;
    _commit(history!.replace(id, f));
  }

  void moveSelected(double dx, double dy) => updateSelected((i) => i.translate(dx, dy));

  void scaleSelected(double f) => updateSelected(
    (i) => switch (i) {
      TextMarkup t => t.copyWith(size: (t.size * f).clamp(0.01, 0.3), width: (t.width * f).clamp(0.05, 2.0)),
      SignatureMarkup s => s.copyWith(width: (s.width * f).clamp(0.05, 2.0), height: (s.height * f).clamp(0.02, 2.0)),
      ShapeMarkup s => _scaleShape(s, f),
      StrokeMarkup s => _scaleStroke(s, f),
    },
  );

  ShapeMarkup _scaleShape(ShapeMarkup s, double f) {
    final c = Pt((s.a.x + s.b.x) / 2, (s.a.y + s.b.y) / 2);
    Pt sc(Pt p) => Pt(c.x + (p.x - c.x) * f, c.y + (p.y - c.y) * f);
    return s.copyWith(a: sc(s.a), b: sc(s.b));
  }

  StrokeMarkup _scaleStroke(StrokeMarkup s, double f) {
    final b = s.bounds();
    final c = Pt((b.l + b.r) / 2, (b.t + b.b) / 2);
    return s.withPoints([for (final p in s.points) Pt(c.x + (p.x - c.x) * f, c.y + (p.y - c.y) * f)]);
  }

  void rotateSelected(double radians) => updateSelected(
    (i) => switch (i) {
      TextMarkup t => t.copyWith(rotation: t.rotation + radians),
      SignatureMarkup s => s.copyWith(rotation: s.rotation + radians),
      _ => i,
    },
  );

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    _commit(history!.without(id));
    setState(() => selectedId = null);
  }

  Future<void> editSelectedText() async {
    final t = selected;
    if (t is! TextMarkup) return;
    final text = await _askText(initial: t.text);
    if (text == null || text.trim().isEmpty) return;
    updateSelected((i) => (i as TextMarkup).copyWith(text: text.trim()));
  }

  void undo() => setState(() {
    history!.undo();
    if (selected == null) selectedId = null;
  });

  void redo() => setState(history!.redo);

  Future<void> save() async {
    setState(() => _saving = true);
    await ref.read(documentProvider(widget.documentId).notifier).setMarkup(widget.pageId, items);
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- gestures ----------

  Offset _toScreen(Pt p) => _pageRect.topLeft + Offset(p.x * _pageRect.width, p.y * _pageRect.height);

  ({Offset resize, Offset? rotate})? _handlesFor(MarkupItem item) {
    final b = _boundsOf(item);
    final br = _toScreen(Pt(b.r, b.b));
    final rotatable = item is TextMarkup || item is SignatureMarkup;
    return (resize: br, rotate: rotatable ? _toScreen(Pt((b.l + b.r) / 2, b.t)) - const Offset(0, 28) : null);
  }

  ({double l, double t, double r, double b}) _boundsOf(MarkupItem item) => markupBounds(item, _shownSize);

  void _onPanStart(DragStartDetails d) {
    _canvasFocus.requestFocus();
    final h = history;
    if (h == null) return;
    _before = h.items;
    _lastScreen = d.localPosition;
    final p = _norm(d.localPosition);
    switch (tool) {
      case MarkupTool.pen:
      case MarkupTool.highlighter:
        final hl = tool == MarkupTool.highlighter;
        final s = StrokeMarkup(
          id: _newId(),
          highlighter: hl,
          color: hl && color == MarkupColor.black ? MarkupColor.yellow.argb : color.argb,
          width: (hl ? 0.03 : 0.007) * _k,
          points: [p],
        );
        setState(() => h.preview([...h.items, s]));
        _drag = _Drag.draw;
      case MarkupTool.rect:
      case MarkupTool.arrow:
      case MarkupTool.line:
      case MarkupTool.whiteout:
        final kind = MarkupKind.values.byName(tool.name);
        final s = ShapeMarkup(id: _newId(), kind: kind, color: color.argb, width: 0.006 * _k, a: p, b: p);
        setState(() => h.preview([...h.items, s]));
        _drag = _Drag.shape;
      case MarkupTool.eraser:
        _erase(p);
        _drag = _Drag.erase;
      case MarkupTool.select:
        final sel = selected;
        final handles = sel == null ? null : _handlesFor(sel);
        if (handles != null && (handles.resize - d.localPosition).distance < 28) {
          _drag = _Drag.resize;
        } else if (handles?.rotate != null && (handles!.rotate! - d.localPosition).distance < 28) {
          _drag = _Drag.rotate;
        } else {
          final hit = hitTestMarkup(h.items, p, _shownSize);
          setState(() => selectedId = hit?.id);
          _drag = hit == null ? _Drag.none : _Drag.move;
        }
      default:
        _drag = _Drag.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final h = history;
    if (h == null) return;
    final p = _norm(d.localPosition);
    switch (_drag) {
      case _Drag.draw:
        final s = h.items.last as StrokeMarkup;
        setState(
          () => h.preview([
            ...h.items.take(h.items.length - 1),
            s.withPoints([...s.points, p]),
          ]),
        );
      case _Drag.shape:
        final s = h.items.last as ShapeMarkup;
        setState(() => h.preview([...h.items.take(h.items.length - 1), s.copyWith(b: p)]));
      case _Drag.erase:
        _erase(p);
      case _Drag.move:
        final delta = d.localPosition - _lastScreen;
        setState(
          () => h.preview(
            h.replace(selectedId!, (i) => i.translate(delta.dx / _pageRect.width, delta.dy / _pageRect.height)),
          ),
        );
      case _Drag.resize:
        final sel = selected!;
        final b = _boundsOf(sel);
        final c = _toScreen(Pt((b.l + b.r) / 2, (b.t + b.b) / 2));
        final before = (_lastScreen - c).distance, after = (d.localPosition - c).distance;
        if (before > 4) {
          final f = (after / before).clamp(0.8, 1.25);
          setState(() => h.preview(h.replace(sel.id, (i) => _scaledForDrag(i, f))));
        }
      case _Drag.rotate:
        final sel = selected!;
        final b = _boundsOf(sel);
        final c = _toScreen(Pt((b.l + b.r) / 2, (b.t + b.b) / 2));
        final a0 = math.atan2(_lastScreen.dy - c.dy, _lastScreen.dx - c.dx);
        final a1 = math.atan2(d.localPosition.dy - c.dy, d.localPosition.dx - c.dx);
        setState(
          () => h.preview(
            h.replace(
              sel.id,
              (i) => switch (i) {
                TextMarkup t => t.copyWith(rotation: t.rotation + a1 - a0),
                SignatureMarkup s => s.copyWith(rotation: s.rotation + a1 - a0),
                _ => i,
              },
            ),
          ),
        );
      case _Drag.none:
        break;
    }
    _lastScreen = d.localPosition;
  }

  MarkupItem _scaledForDrag(MarkupItem i, double f) => switch (i) {
    TextMarkup t => t.copyWith(size: (t.size * f).clamp(0.01, 0.3), width: (t.width * f).clamp(0.05, 2.0)),
    SignatureMarkup s => s.copyWith(width: (s.width * f).clamp(0.05, 2.0), height: (s.height * f).clamp(0.02, 2.0)),
    ShapeMarkup s => _scaleShape(s, f),
    StrokeMarkup s => _scaleStroke(s, f),
  };

  void _onPanEnd([Object? _]) {
    final h = history, before = _before;
    if (h == null || before == null) return;
    if (_drag == _Drag.shape) {
      final s = h.items.last as ShapeMarkup;
      if (s.a.distanceTo(s.b) < 0.01) {
        h.preview(before); // a tap, not a drag: nothing to add
      } else {
        selectedId = s.id;
      }
    }
    setState(() => h.commitFrom(before));
    _before = null;
    _drag = _Drag.none;
  }

  void _erase(Pt p) {
    final h = history!;
    final hit = eraseAt(h.items, p, _shownSize).toSet();
    if (hit.isNotEmpty) {
      setState(() => h.preview([for (final i in h.items) if (!hit.contains(i.id)) i]));
    }
  }

  void _onTapUp(TapUpDetails d) {
    _canvasFocus.requestFocus();
    final p = _norm(d.localPosition);
    switch (tool) {
      case MarkupTool.text:
        addText(p);
      case MarkupTool.signature:
        addSignature(p);
      case MarkupTool.select:
        setState(() => selectedId = hitTestMarkup(items, p, _shownSize)?.id);
      case MarkupTool.eraser:
        final before = items;
        _erase(p);
        setState(() => history!.commitFrom(before));
      default:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final cmd = keys.isControlPressed || keys.isMetaPressed;
    if (cmd && e.logicalKey == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? redo() : undo();
      return KeyEventResult.handled;
    }
    if (cmd && e.logicalKey == LogicalKeyboardKey.keyY) {
      redo();
      return KeyEventResult.handled;
    }
    if (selectedId == null) return KeyEventResult.ignored;
    final step = keys.isShiftPressed ? 0.002 : 0.01;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        moveSelected(-step, 0);
      case LogicalKeyboardKey.arrowRight:
        moveSelected(step, 0);
      case LogicalKeyboardKey.arrowUp:
        moveSelected(0, -step);
      case LogicalKeyboardKey.arrowDown:
        moveSelected(0, step);
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        deleteSelected();
      case LogicalKeyboardKey.escape:
        setState(() => selectedId = null);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------- UI ----------

  String _toolLabel(MarkupTool t) {
    final l = context.l10n;
    return switch (t) {
      MarkupTool.select => l.toolSelect,
      MarkupTool.text => l.toolText,
      MarkupTool.pen => l.toolPen,
      MarkupTool.highlighter => l.toolHighlighter,
      MarkupTool.eraser => l.toolEraser,
      MarkupTool.signature => l.toolSignature,
      MarkupTool.rect => l.toolRect,
      MarkupTool.arrow => l.toolArrow,
      MarkupTool.line => l.toolLine,
      MarkupTool.whiteout => l.toolWhiteout,
    };
  }

  static const _toolIcons = {
    MarkupTool.select: Icons.near_me_outlined,
    MarkupTool.text: Icons.text_fields,
    MarkupTool.pen: Icons.edit_outlined,
    MarkupTool.highlighter: Icons.border_color_outlined,
    MarkupTool.eraser: Icons.auto_fix_normal_outlined,
    MarkupTool.signature: Icons.draw_outlined,
    MarkupTool.rect: Icons.crop_square,
    MarkupTool.arrow: Icons.north_east,
    MarkupTool.line: Icons.horizontal_rule,
    MarkupTool.whiteout: Icons.rectangle,
  };

  String itemLabel(MarkupItem i) {
    final l = context.l10n;
    return switch (i) {
      TextMarkup t => l.itemText(t.text),
      StrokeMarkup s => s.highlighter ? l.itemHighlighter : l.itemPen,
      SignatureMarkup _ => l.itemSignature,
      ShapeMarkup s => switch (s.kind) {
        MarkupKind.rect => l.itemRect,
        MarkupKind.arrow => l.itemArrow,
        MarkupKind.line => l.itemLine,
        _ => l.itemWhiteout,
      },
    };
  }

  Future<bool> _confirmDiscard() async {
    final l = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l.discardChanges),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(c).pop(false),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l.keepEditing),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(c).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: Text(l.discard),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.watch(documentProvider(widget.documentId)); // keep the document loaded until saved
    final h = history;
    final simple = ref.watch(appSettingsProvider).simpleMode;
    final tools = simple
        ? const [
            MarkupTool.select,
            MarkupTool.text,
            MarkupTool.pen,
            MarkupTool.signature,
            MarkupTool.whiteout,
            MarkupTool.eraser,
          ]
        : MarkupTool.values;
    final sel = selected;

    return PopScope(
      canPop: !(h?.dirty ?? false) || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _saving = true); // allow the pop
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.markupTitle),
          actions: [
            TextButton.icon(
              key: const ValueKey('markup-undo'),
              onPressed: h?.canUndo ?? false ? undo : null,
              icon: const Icon(Icons.undo),
              label: Text(l.undo),
            ),
            TextButton.icon(
              key: const ValueKey('markup-redo'),
              onPressed: h?.canRedo ?? false ? redo : null,
              icon: const Icon(Icons.redo),
              label: Text(l.redo),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('markup-save'),
                onPressed: h == null || _saving ? null : save,
                icon: const Icon(Icons.check),
                label: Text(l.done),
              ),
            ),
          ],
        ),
        body: h == null || _image == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 900;
                  final canvas = _buildCanvas(context);
                  final panel = _buildPanel(context, tools, sel, simple);
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: canvas),
                            SizedBox(width: 360, child: panel),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(flex: 3, child: canvas),
                            Expanded(flex: 2, child: panel),
                          ],
                        );
                },
              ),
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    final l = context.l10n;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            _pageRect = fittedImageRect(_pagePx, c.biggest);
            return Focus(
              focusNode: _canvasFocus,
              onKeyEvent: _onKey,
              child: Semantics(
                label: '${l.markupTitle}. ${l.markupHint}',
                child: GestureDetector(
                  key: const ValueKey('markup-canvas'),
                dragStartBehavior: DragStartBehavior.down, // strokes start where the finger went down
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onPanCancel: _onPanEnd,
                  onTapUp: _onTapUp,
                  child: SizedBox.fromSize(
                    size: c.biggest,
                    child: Stack(
                      children: [
                        Positioned.fromRect(
                          rect: _pageRect,
                          child: Image.memory(_image!, fit: BoxFit.fill, gaplessPlayback: true),
                        ),
                        Positioned.fromRect(
                          rect: _pageRect,
                          child: ClipRect(child: CustomPaint(painter: MarkupPainter(items))),
                        ),
                        Positioned.fill(child: CustomPaint(painter: _SelectionPainter(this))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, List<MarkupTool> tools, MarkupItem? sel, bool simple) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    final placeable = {
      MarkupTool.text,
      MarkupTool.signature,
      MarkupTool.rect,
      MarkupTool.arrow,
      MarkupTool.line,
      MarkupTool.whiteout,
    };
    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tools)
                ChoiceChip(
                  key: ValueKey('tool-${t.name}'),
                  avatar: Icon(_toolIcons[t], size: 18),
                  label: Text(_toolLabel(t)),
                  selected: tool == t,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() {
                    tool = t;
                    if (t != MarkupTool.select) selectedId = null;
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.markupHint, style: theme.textTheme.bodySmall),
          ),
          if (placeable.contains(tool))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('add-in-middle'),
                    onPressed: () => switch (tool) {
                      MarkupTool.text => addText(const Pt(0.5, 0.5)),
                      MarkupTool.signature => addSignature(const Pt(0.5, 0.75)),
                      _ => addShapeInMiddle(MarkupKind.values.byName(tool.name)),
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l.addInMiddle),
                  ),
                  if (tool == MarkupTool.signature)
                    OutlinedButton.icon(
                      onPressed: () => drawSignature(context, ref),
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(l.changeSignature),
                    ),
                ],
              ),
            ),
          label(l.colour),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in MarkupColor.values)
                if (c != MarkupColor.white)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: Color(c.argb), radius: 8),
                    label: Text(c.label),
                    selected: color == c,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) {
                      setState(() => color = c);
                      if (sel != null) {
                        updateSelected(
                          (i) => switch (i) {
                            TextMarkup t => t.copyWith(color: c.argb),
                            ShapeMarkup s when s.kind != MarkupKind.whiteout => s.copyWith(color: c.argb),
                            SignatureMarkup s => s.copyWith(color: c.argb),
                            _ => i,
                          },
                        );
                      }
                    },
                  ),
            ],
          ),
          label(l.size),
          Wrap(
            spacing: 8,
            children: [
              for (final (i, name) in [(0, 'S'), (1, 'M'), (2, 'L')])
                ChoiceChip(
                  label: Text(name, semanticsLabel: '${l.size} $name'),
                  selected: sizeStep == i,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() => sizeStep = i),
                ),
            ],
          ),
          if (tool == MarkupTool.text || sel is TextMarkup) ...[
            label(l.toolText),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  key: const ValueKey('text-bold'),
                  label: Text(l.bold),
                  selected: sel is TextMarkup ? sel.bold : bold,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (v) {
                    setState(() => bold = v);
                    if (sel is TextMarkup) updateSelected((i) => (i as TextMarkup).copyWith(bold: v));
                  },
                ),
                for (final b in TextBackground.values)
                  ChoiceChip(
                    label: Text('${l.background}: ${b == TextBackground.none ? l.bgNone : l.bgWhite}'),
                    selected: (sel is TextMarkup ? sel.background : background) == b,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) {
                      setState(() => background = b);
                      if (sel is TextMarkup) updateSelected((i) => (i as TextMarkup).copyWith(background: b));
                    },
                  ),
              ],
            ),
          ],
          if (sel != null) ...[
            const Divider(height: 28),
            Semantics(
              liveRegion: true,
              child: Text('${itemLabel(sel)} (${l.selected})', style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (sel is TextMarkup)
                  FilledButton.tonalIcon(
                    key: const ValueKey('edit-text'),
                    onPressed: editSelectedText,
                    icon: const Icon(Icons.edit_note),
                    label: Text(l.editText),
                  ),
                OutlinedButton.icon(
                  onPressed: () => scaleSelected(1.15),
                  icon: const Icon(Icons.zoom_in),
                  label: Text(l.bigger),
                ),
                OutlinedButton.icon(
                  onPressed: () => scaleSelected(1 / 1.15),
                  icon: const Icon(Icons.zoom_out),
                  label: Text(l.smaller),
                ),
                if (sel is TextMarkup || sel is SignatureMarkup) ...[
                  OutlinedButton.icon(
                    onPressed: () => rotateSelected(-math.pi / 12),
                    icon: const Icon(Icons.rotate_left),
                    label: Text(l.rotateLeft),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => rotateSelected(math.pi / 12),
                    icon: const Icon(Icons.rotate_right),
                    label: Text(l.rotateRight),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () => moveSelected(-0.02, 0),
                  icon: const Icon(Icons.west),
                  label: Text(l.moveLeft),
                ),
                OutlinedButton.icon(
                  onPressed: () => moveSelected(0.02, 0),
                  icon: const Icon(Icons.east),
                  label: Text(l.moveRight),
                ),
                OutlinedButton.icon(
                  onPressed: () => moveSelected(0, -0.02),
                  icon: const Icon(Icons.north),
                  label: Text(l.moveUp),
                ),
                OutlinedButton.icon(
                  onPressed: () => moveSelected(0, 0.02),
                  icon: const Icon(Icons.south),
                  label: Text(l.moveDown),
                ),
                FilledButton.icon(
                  key: const ValueKey('delete-item'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () {
                    deleteSelected();
                    _announce(l.deleteItem);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.deleteItem),
                ),
              ],
            ),
          ],
          const Divider(height: 28),
          Semantics(header: true, child: Text('${l.itemsOnPage} (${items.length})', style: theme.textTheme.titleSmall)),
          if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.noItems)),
          for (final i in items.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: i.id == selectedId,
              leading: Icon(i.id == selectedId ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(itemLabel(i), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => setState(() {
                tool = MarkupTool.select;
                selectedId = i.id;
              }),
            ),
        ],
      ),
    );
  }
}

enum _Drag { none, draw, shape, erase, move, resize, rotate }

/// Selection box with resize (bottom-right) and rotate (top) handles.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.s);
  final MarkupEditorPageState s;

  @override
  void paint(Canvas canvas, Size size) {
    final sel = s.selected;
    if (sel == null) return;
    final b = s._boundsOf(sel);
    final r = Rect.fromPoints(s._toScreen(Pt(b.l, b.t)), s._toScreen(Pt(b.r, b.b))).inflate(6);
    final color = Colors.blue.shade700;
    final dash = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, dash);
    final handles = s._handlesFor(sel)!;
    canvas.drawCircle(handles.resize, 10, Paint()..color = Colors.white);
    canvas.drawCircle(handles.resize, 8, Paint()..color = color);
    if (handles.rotate != null) {
      canvas.drawLine(Offset(r.center.dx, r.top), handles.rotate!, dash);
      canvas.drawCircle(handles.rotate!, 10, Paint()..color = Colors.white);
      canvas.drawCircle(handles.rotate!, 8, Paint()..color = color);
      canvas.drawCircle(handles.rotate!, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}
