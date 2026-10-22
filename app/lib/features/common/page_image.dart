import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../editor/document_controller.dart';

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
  String? _lastPageId;

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final bytes = ref.watch(pageImageProvider((pageId: p.id, kind: widget.kind, revision: p.revision)));
    if (_lastPageId != p.id) {
      _last = null;
      _lastPageId = p.id;
    }
    if (bytes case AsyncData(value: final b?)) _last = b;
    final shown = _last;
    if (shown != null) {
      return Stack(alignment: Alignment.center, children: [
        Image.memory(shown, fit: widget.fit, gaplessPlayback: true),
        if (bytes.isLoading) const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ]);
    }
    return switch (bytes) {
      AsyncError() => const Center(child: Icon(Icons.broken_image_outlined)),
      _ => const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    };
  }
}
