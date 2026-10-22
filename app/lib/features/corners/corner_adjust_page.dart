// Confirm/adjust the page corners of a photo. Pops with the corners (TL, TR,
// BR, BL in photo pixels), or null for "Retake"/back.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../imaging/geometry.dart';
import 'corner_editor.dart';

class CornerAdjustPage extends StatefulWidget {
  const CornerAdjustPage({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.corners,
    this.detected = true,
    this.cancelLabel = 'Retake',
    this.confirmLabel = 'Continue',
  });

  final Uint8List bytes;
  final int width, height;
  final List<Pt> corners;

  /// False when the corners are a fallback (full photo): shows a hint.
  final bool detected;
  final String cancelLabel, confirmLabel;

  @override
  State<CornerAdjustPage> createState() => _CornerAdjustPageState();
}

class _CornerAdjustPageState extends State<CornerAdjustPage> {
  late List<Pt> _corners = widget.corners;
  late final _image = MemoryImage(widget.bytes);

  Size get _size => Size(widget.width.toDouble(), widget.height.toDouble());
  List<Pt> get _full => fullBounds(widget.width, widget.height);
  bool get _isFullFrame => listEquals(_corners, _full);

  @override
  Widget build(BuildContext context) {
    final valid = isValidQuad(_corners, _size);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Adjust corners'),
      ),
      body: Column(children: [
        if (!widget.detected)
          const MaterialBanner(
            content: Text("Couldn't find the page edges. Drag the corners onto the page."),
            leading: Icon(Icons.info_outline),
            actions: [SizedBox.shrink()],
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CornerEditor(
              image: _image,
              imageSize: _size,
              corners: _corners,
              onChanged: (c) => setState(() => _corners = c),
            ),
          ),
        ),
        if (!valid)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('The corners cross over. Drag them back around the page.',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.replay),
                label: Text(widget.cancelLabel),
              ),
              const Spacer(),
              IconButton(
                color: Colors.white,
                tooltip: _isFullFrame ? 'Use detected edges' : 'Use whole photo',
                onPressed: () => setState(() => _corners = _isFullFrame ? widget.corners : _full),
                icon: Icon(_isFullFrame ? Icons.crop_free : Icons.fullscreen),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('confirm-corners'),
                onPressed: valid ? () => Navigator.of(context).pop(_corners) : null,
                icon: const Icon(Icons.check),
                label: Text(widget.confirmLabel),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
