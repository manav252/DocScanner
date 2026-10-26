// ID card mode on the document page: what card this is (with a way to
// change it), its details (editable), and whether it is backed up: ID cards
// are only uploaded after the user agrees.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../data/id_card.dart';
import '../../data/models.dart';
import '../editor/document_controller.dart';

String idCardLabel(AppLocalizations l, IdCardType? t) => switch (t) {
  IdCardType.aadhaar => l.idAadhaar,
  IdCardType.pan => l.idPan,
  _ => l.idOther,
};

class IdCardBanner extends ConsumerWidget {
  const IdCardBanner({super.key, required this.doc});
  final ScanDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final known = doc.idCard == IdCardType.aadhaar || doc.idCard == IdCardType.pan;
    final signedIn = ref.watch(sessionProvider) != null;
    final backedUp = doc.idBackupApproved || doc.remoteId != null;
    return Card(
      key: const ValueKey('id-card-banner'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      idCardLabel(l, doc.idCard),
                      key: const ValueKey('id-card-label'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            if (!known) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.idOtherHint)),
            const SizedBox(height: 4),
            Text(
              signedIn && backedUp ? l.idBackedUp : l.idLocalOnly,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: const ValueKey('id-card-change'),
                  onPressed: () => _pickType(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(l.idChange),
                ),
                TextButton.icon(
                  key: const ValueKey('id-card-details'),
                  onPressed: () => _editDetails(context, ref),
                  icon: const Icon(Icons.edit_note),
                  label: Text(l.idDetails),
                ),
                if (signedIn && !backedUp)
                  TextButton.icon(
                    key: const ValueKey('id-card-backup'),
                    onPressed: () => _approveBackup(context, ref),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(l.idBackUp),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickType(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final type = await showModalBottomSheet<IdCardType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(header: true, child: Text(l.idPickTitle, style: Theme.of(context).textTheme.titleLarge)),
            ),
            for (final (t, label) in [
              (IdCardType.aadhaar, l.idAadhaar),
              (IdCardType.pan, l.idPan),
              (IdCardType.other, l.idOtherChoice),
              (IdCardType.none, l.idNotCard),
            ])
              ListTile(
                key: ValueKey('id-type-${t.wireName}'),
                title: Text(label),
                trailing: doc.idCard == t ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (type != null) await ref.read(documentProvider(doc.id).notifier).setIdCard(type);
  }

  Future<void> _editDetails(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final keys = ['name', 'dob', 'number'];
    final labels = [l.idName, l.idDob, l.idNumber];
    final controllers = [for (final k in keys) TextEditingController(text: doc.idFields[k] ?? '')];
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.idDetails),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.idDetailsHint),
              for (final (i, c) in controllers.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    key: ValueKey('id-field-${keys[i]}'),
                    controller: c,
                    decoration: InputDecoration(labelText: labels[i], border: const OutlineInputBorder()),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.save)),
        ],
      ),
    );
    if (save == true) {
      await ref.read(documentProvider(doc.id).notifier).setIdFields({
        for (final (i, c) in controllers.indexed)
          if (c.text.trim().isNotEmpty) keys[i]: c.text.trim(),
      });
    }
    for (final c in controllers) {
      c.dispose();
    }
  }

  Future<void> _approveBackup(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.idBackupTitle),
        content: Text(l.idBackupBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          FilledButton(
            key: const ValueKey('id-backup-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.idBackUp),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(documentProvider(doc.id).notifier).approveIdBackup();
  }
}
