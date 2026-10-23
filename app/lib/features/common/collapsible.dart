// Fades and folds a list item away (and back, for Undo) without rebuilding its
// neighbours. Instant when the system asks for reduced motion.
import 'package:flutter/material.dart';

class Collapsible extends StatelessWidget {
  const Collapsible({
    super.key,
    required this.hidden,
    required this.child,
    this.axis = Axis.vertical,
    this.onCollapsed,
  });

  final bool hidden;
  final Widget child;
  final Axis axis;

  /// Called when the item has finished folding away (the list can then drop it:
  /// a lazy list must not keep zero-height items, it would skip them on Undo).
  final VoidCallback? onCollapsed;

  static const duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final d = MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
    return ExcludeSemantics(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: d,
          curve: Curves.easeOut,
          onEnd: hidden ? onCollapsed : null,
          child: AnimatedSize(
            duration: d,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: hidden
                ? SizedBox(width: axis == Axis.vertical ? double.infinity : 0, height: axis == Axis.vertical ? 0 : null)
                : child,
          ),
        ),
      ),
    );
  }
}
