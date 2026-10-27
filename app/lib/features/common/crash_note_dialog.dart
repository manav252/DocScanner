// "The app closed unexpectedly": shown once after a launch that follows a
// page that died during a step (see core/crash_note.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/crash_note.dart';
import '../../core/l10n.dart';

/// The page closed during a step last time: say so, and offer the details.
Future<void> showCrashNote(BuildContext context, CrashNote crash) => showDialog<void>(
  context: context,
  builder: (context) {
    final l = context.l10n;
    return AlertDialog(
      key: const ValueKey('crash-note'),
      title: Text(l.crashTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.crashBody(crash.step)),
            const SizedBox(height: 12),
            SelectableText(crash.details, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: crash.details)),
          child: Text(l.copyDetails),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.done)),
      ],
    );
  },
);
