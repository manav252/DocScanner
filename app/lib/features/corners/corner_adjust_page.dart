// Confirm/adjust the page corners of a photo. Pops with a [CornerAdjustResult]
// (corners in pixels of the returned, possibly rotated, photo), or null for
// Cancel / Retake / back.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';

import '../../core/providers.dart';
import '../../imaging/geometry.dart';
import '../../imaging/page_edits.dart';
import 'corner_editor.dart';

class CornerAdjustResult {
  const CornerAdjustResult({
    required this.corners,
    required this.bytes,
    required this.width,
    required this.height,
    required this.rotated,
  });

  /// TL, TR, BR, BL in pixels of [bytes].
  final List<Pt> corners;
  final Uint8List bytes;
  final int width, height;

  /// True when the user rotated the photo (bytes differ from the input).
  final bool rotated;
}

/// Rotate a point 90 degrees clockwise inside an image of width [w], height [h].
@visibleForTesting
Pt rotatePointClockwise(Pt p, int w, int h) => Pt(h - 1 - p.y, p.x);

class CornerAdjustPage extends ConsumerStatefulWidget {
  const CornerAdjustPage({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.corners,
    this.detected = true,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Confirm',
  });

  /// An upright photo (see ScanEngine.normalizeEncoded).
  final Uint8List bytes;
  final int width, height;
  final List<Pt> corners;

  /// False when no page was found and [corners] are the full photo.
  final bool detected;
  final String cancelLabel, confirmLabel;

  static const noEdgesMessage = 'No page edges found. Adjust the corners or keep the full photo.';

  @override
  ConsumerState<CornerAdjustPage> createState() => _CornerAdjustPageState();
}

class _CornerAdjustPageState extends ConsumerState<CornerAdjustPage> {
  late Uint8List _bytes = widget.bytes;
  late int _w = widget.width, _h = widget.height;
  late List<Pt> _detected = widget.corners;
  late List<Pt> _corners = widget.corners;
  late MemoryImage _image = MemoryImage(_bytes);
  bool _rotated = false, _busy = false;
  final _editorFocus = FocusNode(debugLabel: 'corner editor');

  Size get _size => Size(_w.toDouble(), _h.toDouble());
  List<Pt> get _full => fullBounds(_w, _h);

  @override
  void dispose() {
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      final rotated = await ref
          .read(scanEngineProvider)
          .processEncoded(_bytes, const PageEdits(filter: PageFilter.original, quarterTurns: 1), quality: 95);
      List<Pt> turn(List<Pt> c) => orderCorners([for (final p in c) rotatePointClockwise(p, _w, _h)]);
      setState(() {
        _corners = turn(_corners);
        _detected = turn(_detected);
        final oldW = _w;
        _w = _h;
        _h = oldW;
        _bytes = rotated;
        _image = MemoryImage(rotated);
        _rotated = true;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.couldNotRotate)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirm() => Navigator.of(context).pop(CornerAdjustResult(
        corners: _corners,
        bytes: _bytes,
        width: _w,
        height: _h,
        rotated: _rotated,
      ));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final valid = isValidQuad(_corners, _size);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.adjustCorners)),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.detected)
            Semantics(
              liveRegion: true,
              child: MaterialBanner(
                key: const ValueKey('no-edges-banner'),
                content: Text(l.noEdgesFound),
                leading: const Icon(Icons.info_outline),
                actions: const [SizedBox.shrink()],
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF202124),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CornerEditor(
                  key: ValueKey('editor-$_w-$_h'),
                  image: _image,
                  imageSize: _size,
                  corners: _corners,
                  focusNode: _editorFocus,
                  onChanged: (c) => setState(() => _corners = c),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              valid ? l.cornersHint : l.cornersCrossed,
              style: TextStyle(color: valid ? null : scheme.error),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('cancel-corners'),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: Text(widget.cancelLabel),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('reset-corners'),
                  onPressed: _busy || listEquals(_corners, _detected) ? null : () => setState(() => _corners = _detected),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.resetCorners),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('full-photo'),
                  onPressed: _busy || listEquals(_corners, _full) ? null : () => setState(() => _corners = _full),
                  icon: const Icon(Icons.fullscreen),
                  label: Text(l.useFullPhoto),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('rotate-photo'),
                  onPressed: _busy ? null : _rotate,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.rotate_right),
                  label: Text(l.rotate),
                ),
                FilledButton.icon(
                  key: const ValueKey('confirm-corners'),
                  onPressed: valid && !_busy ? _confirm : null,
                  icon: const Icon(Icons.check),
                  label: Text(widget.confirmLabel),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
