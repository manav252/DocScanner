// Shows a photo with 4 draggable corner handles (+ 4 edge handles that move a
// whole side) and a magnifier loupe. Keyboard: Tab / Shift+Tab picks a corner,
// arrow keys move it (Shift = fine steps). Screen readers get named actions.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../imaging/geometry.dart';

/// Whether [corners] (TL, TR, BR, BL in handle order) form a usable page outline.
bool isValidQuad(List<Pt> corners, Size imageSize) =>
    isConvex(corners) && polygonArea(corners) >= 0.01 * imageSize.width * imageSize.height;

const cornerNames = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];

/// Where an image of [imageSize] is drawn inside [box]: scaled to fit
/// entirely ("contain") and centred. Shared by painting and hit testing so the
/// handles always sit exactly on the image pixels they represent.
Rect fittedImageRect(Size imageSize, Size box) {
  final fitted = applyBoxFit(BoxFit.contain, imageSize, box).destination;
  return Alignment.center.inscribe(fitted, Offset.zero & box);
}

/// Image pixel -> screen position inside a box laid out with [fittedImageRect].
Offset imageToScreen(Pt p, Rect imageRect, Size imageSize) =>
    imageRect.topLeft + Offset(p.x * imageRect.width / imageSize.width, p.y * imageRect.height / imageSize.height);

/// Screen position -> image pixel (clamped to the image).
Pt screenToImage(Offset o, Rect imageRect, Size imageSize) => Pt(
  ((o.dx - imageRect.left) * imageSize.width / imageRect.width).clamp(0, imageSize.width - 1).toDouble(),
  ((o.dy - imageRect.top) * imageSize.height / imageRect.height).clamp(0, imageSize.height - 1).toDouble(),
);

class CornerEditor extends StatefulWidget {
  const CornerEditor({
    super.key,
    required this.image,
    required this.imageSize,
    required this.corners,
    required this.onChanged,
    this.focusNode,
  });

  final ImageProvider image;
  final Size imageSize;

  /// TL, TR, BR, BL in image pixels.
  final List<Pt> corners;
  final ValueChanged<List<Pt>> onChanged;
  final FocusNode? focusNode;

  @override
  State<CornerEditor> createState() => CornerEditorState();
}

@visibleForTesting
class CornerEditorState extends State<CornerEditor> {
  static const hitRadius = 36.0;
  static const loupeSize = 116.0;
  static const loupeGap = 84.0;

  /// 0-3 = corner, 4-7 = midpoint of side (i-4, i-3).
  int? activeHandle;

  /// Corner picked for keyboard moves (stays selected after a drag).
  int selectedCorner = 0;
  bool _focused = false;

  /// Last input was the keyboard: keep the loupe on the selected corner.
  bool _keyboard = false;
  Rect _imageRect = Rect.zero;

  /// Handle position minus finger position at touch-down, so the handle keeps
  /// its offset from the finger (and follows it exactly, slop included).
  Offset _grab = Offset.zero;

  late final FocusNode _focus = widget.focusNode ?? FocusNode(debugLabel: 'corner editor');

  /// The corners as they are on screen. While a handle is dragged only this
  /// changes (repainting just the outline, handles and loupe); the parent hears
  /// about the new corners once, when the finger lifts.
  late final _live = ValueNotifier<List<Pt>>(widget.corners);

  /// The photo for the loupe, decoded at most [loupeMaxSide] px (sharper than
  /// magnifying the screen, and works the same on web, where backdrop magnifiers
  /// do not). A full 12 MP decode would cost ~48 MB.
  static const loupeMaxSide = 2048;
  ui.Image? _decoded;
  ImageStream? _stream;
  late final _listener = ImageStreamListener((info, _) {
    if (mounted) setState(() => _decoded = info.image);
  });

  void _resolve() {
    _stream?.removeListener(_listener);
    _stream = _fit(widget.image, loupeMaxSide).resolve(ImageConfiguration.empty)..addListener(_listener);
  }

  /// [image] decoded with its long side at most [maxSide] px.
  ImageProvider _fit(ImageProvider image, int maxSide) =>
      ResizeImage(image, width: maxSide, height: maxSide, policy: ResizeImagePolicy.fit);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CornerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _decoded = null;
      _resolve();
    }
    if (activeHandle == null && !listEquals(oldWidget.corners, widget.corners)) _live.value = widget.corners;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _live.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  Offset _toScreen(Pt p) => imageToScreen(p, _imageRect, widget.imageSize);

  List<Offset> _handles() {
    final c = [for (final p in _live.value) _toScreen(p)];
    return [...c, for (var i = 0; i < 4; i++) (c[i] + c[(i + 1) % 4]) / 2];
  }

  /// Handle the loupe magnifies (dragged handle, or the keyboard-selected corner).
  int? get _loupeHandle => activeHandle ?? (_focused && _keyboard ? selectedCorner : null);

  Offset? get _focusPoint => _loupeHandle == null ? null : _handles()[_loupeHandle!];

  /// Image-pixel position of handle [h].
  Pt _handleImagePoint(int h) {
    final c = _live.value;
    if (h < 4) return c[h];
    final a = c[h - 4], b = c[(h - 3) % 4];
    return Pt((a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  int? _handleAt(Offset p) {
    final hs = _handles();
    int? best;
    var bestDist = hitRadius;
    for (var i = 0; i < hs.length; i++) {
      // Corners win ties over midpoints.
      final dist = (hs[i] - p).distance - (i < 4 ? 6 : 0);
      if (dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    return best;
  }

  void _onPanStart(DragStartDetails d) {
    final best = _handleAt(d.localPosition);
    if (best != null) {
      HapticFeedback.selectionClick();
      _grab = _handles()[best] - d.localPosition;
      setState(() {
        activeHandle = best;
        if (best < 4) selectedCorner = best;
      });
    }
  }

  /// Move handle [h] so it ends up at screen position [target] (whole edge for midpoints).
  void _moveHandle(int h, Offset target) {
    final delta = (target - _handles()[h]);
    final sx = widget.imageSize.width / _imageRect.width, sy = widget.imageSize.height / _imageRect.height;
    _moveByImageDelta(h, Offset(delta.dx * sx, delta.dy * sy));
  }

  void _moveByImageDelta(int h, Offset delta) {
    final w = widget.imageSize.width - 1, ht = widget.imageSize.height - 1;
    final next = [..._live.value];
    var d = delta;
    if (h >= 4) {
      // Moving an edge: limit the shift so neither end leaves the image.
      final a = next[h - 4], b = next[(h - 3) % 4];
      d = Offset(
        d.dx.clamp(-math.min(a.x, b.x), w - math.max(a.x, b.x)).toDouble(),
        d.dy.clamp(-math.min(a.y, b.y), ht - math.max(a.y, b.y)).toDouble(),
      );
    }
    Pt move(Pt p) => Pt((p.x + d.dx).clamp(0, w).toDouble(), (p.y + d.dy).clamp(0, ht).toDouble());
    if (h < 4) {
      next[h] = move(next[h]);
    } else {
      final i = h - 4;
      next[i] = move(next[i]);
      next[(i + 1) % 4] = move(next[(i + 1) % 4]);
    }
    _live.value = next;
    if (activeHandle == null) widget.onChanged(next); // keyboard / screen reader step
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final h = activeHandle;
    if (h == null) return;
    _moveHandle(h, d.localPosition + _grab);
  }

  void _onPanEnd([Object? _]) {
    if (activeHandle == null) return;
    setState(() => activeHandle = null);
    if (!listEquals(_live.value, widget.corners)) widget.onChanged(_live.value);
  }

  /// Keyboard / screen-reader step: 1% of the image (0.2% with Shift).
  void nudge(Offset direction, {bool fine = false}) {
    final step = math.max(widget.imageSize.width, widget.imageSize.height) * (fine ? 0.002 : 0.01);
    _moveByImageDelta(selectedCorner, direction * step);
  }

  void selectCorner(int i) => setState(() => selectedCorner = i % 4);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_keyboard) setState(() => _keyboard = true);
    final fine = HardwareKeyboard.instance.isShiftPressed;
    final dir = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (dir != null) {
      nudge(dir, fine: fine);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.tab && e is KeyDownEvent) {
      // Cycle corners; leave the editor after the last one (normal focus order).
      final next = selectedCorner + (fine ? -1 : 1);
      if (next < 0 || next > 3) return KeyEventResult.ignored;
      selectCorner(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(List<Pt> corners) => isValidQuad(corners, widget.imageSize) ? scheme.primary : scheme.error;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final l = context.l10n;
    final name = [l.cornerTopLeft, l.cornerTopRight, l.cornerBottomRight, l.cornerBottomLeft][selectedCorner];
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Semantics(
        label: l.cornersSemantics(name),
        customSemanticsActions: {
          CustomSemanticsAction(label: l.nextCorner): () => selectCorner(selectedCorner + 1),
          CustomSemanticsAction(label: l.moveCornerLeft): () => nudge(const Offset(-1, 0)),
          CustomSemanticsAction(label: l.moveCornerRight): () => nudge(const Offset(1, 0)),
          CustomSemanticsAction(label: l.moveCornerUp): () => nudge(const Offset(0, -1)),
          CustomSemanticsAction(label: l.moveCornerDown): () => nudge(const Offset(0, 1)),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = constraints.biggest;
            _imageRect = fittedImageRect(widget.imageSize, box);
            // The photo at screen resolution (rounded up, so small layout changes
            // reuse the same decode), not the full 12 MP.
            final screenSide = ((_imageRect.longestSide * dpr / 256).ceil() * 256).clamp(256, 4096);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Pick the handle under the finger-down point, not where the drag slop ended.
              dragStartBehavior: DragStartBehavior.down,
              onTapDown: (d) {
                _keyboard = false;
                _focus.requestFocus();
                final h = _handleAt(d.localPosition);
                if (h != null && h < 4) selectCorner(h);
              },
              onPanStart: (d) {
                _keyboard = false;
                _focus.requestFocus();
                _onPanStart(d);
              },
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: _onPanEnd,
              child: SizedBox.fromSize(
                size: box,
                child: Stack(
                  children: [
                    // Separate layers: dragging repaints the outline and the loupe,
                    // never the photo.
                    Positioned.fromRect(
                      rect: _imageRect,
                      child: RepaintBoundary(
                        child: Image(
                          key: const ValueKey('corner-editor-image'),
                          image: _fit(widget.image, screenSide),
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _EditorPainter(
                            _live,
                            toScreen: _toScreen,
                            imageRect: _imageRect,
                            colorFor: colorFor,
                            active: activeHandle,
                            selected: _focused && _keyboard ? selectedCorner : null,
                            focusRing: _focused ? scheme.tertiary : null,
                          ),
                        ),
                      ),
                    ),
                    if (_loupeHandle != null)
                      ValueListenableBuilder(
                        valueListenable: _live,
                        builder: (context, corners, _) {
                          // Above the finger; flip below when too close to the top edge.
                          final focus = _focusPoint!;
                          final above = focus.dy - loupeGap - loupeSize / 2 >= 0;
                          final center = Offset(
                            focus.dx.clamp(loupeSize / 2, math.max(loupeSize / 2, box.width - loupeSize / 2)),
                            above ? focus.dy - loupeGap : focus.dy + loupeGap,
                          );
                          return Positioned(
                            key: const ValueKey('loupe'),
                            left: center.dx - loupeSize / 2,
                            top: center.dy - loupeSize / 2,
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: const Size.square(loupeSize),
                                  painter: _LoupePainter(
                                    image: _decoded,
                                    imageSize: widget.imageSize,
                                    center: _handleImagePoint(_loupeHandle!),
                                    // 2.5x the on-screen size of the photo.
                                    imagePxPerLoupePx: widget.imageSize.width / _imageRect.width / 2.5,
                                    corners: corners,
                                    color: colorFor(corners),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Outline and handles. Repaints on its own (no rebuild) whenever [live] changes.
class _EditorPainter extends CustomPainter {
  _EditorPainter(
    this.live, {
    required this.toScreen,
    required this.imageRect,
    required this.colorFor,
    this.active,
    this.selected,
    this.focusRing,
  }) : super(repaint: live);
  final ValueNotifier<List<Pt>> live;
  final Offset Function(Pt) toScreen;
  final Rect imageRect;
  final Color Function(List<Pt>) colorFor;
  final int? active, selected;
  final Color? focusRing;

  @override
  void paint(Canvas canvas, Size size) {
    final color = colorFor(live.value);
    final corners = [for (final p in live.value) toScreen(p)];
    final handles = [...corners, for (var i = 0; i < 4; i++) (corners[i] + corners[(i + 1) % 4]) / 2];
    // Dim the photo outside the page (only over the image, not the letterbox).
    canvas.save();
    canvas.clipRect(imageRect);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(imageRect)
        ..addPolygon(corners, true),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.restore();
    if (focusRing != null) {
      canvas.drawRect(
        imageRect.inflate(3),
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < handles.length; i++) {
      final isCorner = i < 4, isActive = i == active || i == selected;
      final r = isCorner ? (isActive ? 14.0 : 11.0) : (isActive ? 9.0 : 7.0);
      canvas.drawCircle(handles[i], r + 2, Paint()..color = Colors.white);
      canvas.drawCircle(
        handles[i],
        r,
        Paint()..color = isActive ? Colors.white : color.withValues(alpha: isCorner ? 0.9 : 0.6),
      );
      if (i == selected) {
        // Non-colour cue for the selected corner: a ring.
        canvas.drawCircle(
          handles[i],
          r + 6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.live != live ||
      old.imageRect != imageRect ||
      old.active != active ||
      old.selected != selected ||
      old.focusRing != focusRing ||
      old.colorFor(live.value) != colorFor(live.value);
}

/// Circular magnifier drawn from the photo's own pixels around [center].
class _LoupePainter extends CustomPainter {
  _LoupePainter({
    required this.image,
    required this.imageSize,
    required this.center,
    required this.imagePxPerLoupePx,
    required this.corners,
    required this.color,
  });
  final ui.Image? image;
  final Size imageSize;
  final Pt center;
  final double imagePxPerLoupePx;
  final List<Pt> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.drawShadow(Path()..addOval(circle), Colors.black, 6, false);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawRect(circle, Paint()..color = const Color(0xFF202124));
    Offset toLoupe(Pt p) => c + Offset((p.x - center.x) / imagePxPerLoupePx, (p.y - center.y) / imagePxPerLoupePx);
    final img = image;
    if (img != null) {
      // The decoded image may be smaller than the declared size (e.g. downsampled); scale accordingly.
      final sx = img.width / imageSize.width, sy = img.height / imageSize.height;
      final half = r * imagePxPerLoupePx;
      final src = Rect.fromLTRB(
        (center.x - half) * sx,
        (center.y - half) * sy,
        (center.x + half) * sx,
        (center.y + half) * sy,
      );
      canvas.drawImageRect(img, src, circle, Paint()..filterQuality = FilterQuality.medium);
    }
    canvas.drawPath(
      Path()..addPolygon([for (final p in corners) toLoupe(p)], true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Crosshair on the exact handle position.
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const arm = 10.0;
    canvas.drawLine(c - const Offset(arm, 0), c + const Offset(arm, 0), p);
    canvas.drawLine(c - const Offset(0, arm), c + const Offset(0, arm), p);
    canvas.restore();
    canvas.drawCircle(
      c,
      r - 1.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LoupePainter old) =>
      old.image != image ||
      old.center != center ||
      old.imagePxPerLoupePx != imagePxPerLoupePx ||
      old.corners != corners ||
      old.color != color;
}
