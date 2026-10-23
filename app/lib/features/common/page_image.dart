import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/models.dart';
import '../editor/document_controller.dart';
import '../markup/markup_painter.dart';

/// Shows a stored page image (thumb or full render), following re-renders.
/// While a new revision loads, the previous image stays on screen. If there is
/// no image, or storage does not answer in time, a placeholder (icon + [label])
/// is shown instead of an endless spinner. Large images are decoded at the size
/// they are shown, not at full resolution.
class StoredPageImage extends ConsumerStatefulWidget {
  const StoredPageImage({
    super.key,
    required this.page,
    this.kind = PageImage.thumb,
    this.fit = BoxFit.contain,
    this.label,
  });
  final ScanPage page;
  final PageImage kind;
  final BoxFit fit;

  /// Shown on the placeholder (e.g. the document name).
  final String? label;

  @override
  ConsumerState<StoredPageImage> createState() => _StoredPageImageState();
}

class _StoredPageImageState extends ConsumerState<StoredPageImage> {
  Uint8List? _last;
  ScanPage? _lastPage; // the page version [_last] belongs to (size, markup)
  String? _lastPageId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = widget.page;
    final bytes = ref.watch(pageImageProvider((pageId: p.id, kind: widget.kind, revision: p.revision)));
    if (_lastPageId != p.id) {
      _last = null;
      _lastPageId = p.id;
    }
    if (bytes case AsyncData(value: final b?)) {
      _last = b;
      _lastPage = p;
    }
    final shown = _last;
    if (shown != null) {
      return Semantics(
        image: true,
        label: l.pagePreview,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _withMarkup(shown, _lastPage ?? p),
            if (bytes.isLoading) const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      );
    }
    return switch (bytes) {
      // No image stored, or storage timed out / failed: never spin forever.
      AsyncData() || AsyncError() => _Placeholder(label: widget.label),
      _ => Semantics(
        label: l.pagePreviewLoading,
        child: const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    };
  }

  /// The image with the page's markup drawn on top (markup stays editable, so
  /// it is painted live rather than baked into the stored image).
  Widget _withMarkup(Uint8List bytes, ScanPage p) {
    if (widget.kind != PageImage.thumb) {
      // Decode at (about) the displayed size: a 2400x3200 page shown 400 px wide
      // would otherwise cost ~30 MB of decoded pixels and a long decode.
      return LayoutBuilder(
        builder: (context, c) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final want = c.hasBoundedWidth ? c.maxWidth * dpr : 2048.0;
          // Rounded up to 256 px steps so small layout changes do not re-decode.
          final cacheWidth = ((want / 256).ceil() * 256).clamp(256, 4096);
          return _decorated(bytes, p, cacheWidth: cacheWidth < p.renderWidth || p.renderWidth == 0 ? cacheWidth : null);
        },
      );
    }
    return _decorated(bytes, p);
  }

  Widget _decorated(Uint8List bytes, ScanPage p, {int? cacheWidth}) {
    final image = Image.memory(bytes, fit: widget.fit, gaplessPlayback: true, cacheWidth: cacheWidth);
    if (p.markup.isEmpty || p.renderWidth <= 0 || p.renderHeight <= 0) return image;
    final size = Size(p.renderWidth.toDouble(), p.renderHeight.toDouble());
    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true, cacheWidth: cacheWidth),
            CustomPaint(painter: MarkupPainter(p.markup)),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: l.previewUnavailable,
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 32, color: scheme.onSurfaceVariant),
              if (label != null) ...[
                const SizedBox(height: 4),
                Text(
                  label!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
