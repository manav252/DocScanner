import 'package:flutter/material.dart';

import '../../core/l10n.dart';

class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.initial});
  final String initial;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.renameTitle),
      content: TextField(
        key: const ValueKey('rename-field'),
        controller: _c,
        autofocus: true,
        maxLength: 120,
        decoration: InputDecoration(labelText: l.documentName),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton.icon(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close), label: Text(l.cancel)),
        FilledButton.icon(onPressed: () => Navigator.of(context).pop(_c.text), icon: const Icon(Icons.check), label: Text(l.save)),
      ],
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton.icon(onPressed: () => Navigator.of(c).pop(false), icon: const Icon(Icons.close), label: Text(c.l10n.cancel)),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.of(c).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text(c.l10n.delete),
          ),
        ],
      ),
    ) ??
    false;
