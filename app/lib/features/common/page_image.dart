import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../editor/document_controller.dart';
import '../markup/markup_painter.dart';

/// Shows a stored page image (thumb or full render), following re-renders.
/// While a new revision loads, the previous image stays on screen.
class StoredPageImage extends ConsumerStatefulWidget {
  const StoredPageImage({super.key, required this.page, this.kind = PageImage.thumb, this.fit = BoxFit.contain});
  final ScanPage page;
  final PageImage kind;
  final BoxFit fit;

  @override
  ConsumerState<StoredPageImage> createState() => _StoredPageImageState();
}

class _StoredPageImageState extends ConsumerState<StoredPageImage> {
  Uint8List? _last;
  ScanPage? _lastPage; // the page version [_last] belongs to (size, markup)
  String? _lastPageId;

  @override
  Widget build(BuildContext context) {
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
      return Stack(
        alignment: Alignment.center,
        children: [
          _withMarkup(shown, _lastPage ?? p),
          if (bytes.isLoading) const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      );
    }
    return switch (bytes) {
      AsyncError() => const Center(child: Icon(Icons.broken_image_outlined)),
      _ => const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    };
  }

  /// The image with the page's markup drawn on top (markup stays editable, so
  /// it is painted live rather than baked into the stored image).
  Widget _withMarkup(Uint8List bytes, ScanPage p) {
    final image = Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
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
            Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
            CustomPaint(painter: MarkupPainter(p.markup)),
          ],
        ),
      ),
    );
  }
}
