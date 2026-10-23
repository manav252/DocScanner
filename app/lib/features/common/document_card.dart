// A document in a list: thumbnail, name, pages, last modified, backup state,
// and labelled actions (no hidden menus).
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../data/models.dart';
import 'page_image.dart';

/// Where a document lives: on this device only, waiting to upload, or backed up.
class BackupBadge extends StatelessWidget {
  const BackupBadge({super.key, required this.doc});
  final ScanDocument doc;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = !doc.backup
        ? (Icons.phone_android, l.badgeDeviceOnly)
        : doc.needsSync
        ? (Icons.cloud_upload_outlined, l.badgeWaiting)
        : (Icons.cloud_done_outlined, l.badgeBackedUp);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.doc,
    required this.onOpen,
    this.onRename,
    this.onExport,
    this.onDelete,
    this.compact = false,
  });

  final ScanDocument doc;
  final VoidCallback onOpen;
  final VoidCallback? onRename, onExport, onDelete;

  /// Thumbnail + name only (recent scans strip).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final thumb = AspectRatio(
      aspectRatio: 3 / 4,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: doc.pages.isEmpty
            ? const Icon(Icons.description_outlined, size: 40)
            : Padding(
                padding: const EdgeInsets.all(6),
                child: StoredPageImage(page: doc.pages.first, label: doc.title),
              ),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(l.pageCount(doc.pages.length), style: theme.textTheme.bodySmall),
        Text(l.modified(shortDate(context, doc.updatedAt)), style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        BackupBadge(doc: doc),
      ],
    );
    return Card(
      key: ValueKey('doc-${doc.id}'),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '${doc.title}, ${l.pageCount(doc.pages.length)}',
        excludeSemantics: false,
        child: InkWell(
          onTap: onOpen,
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    thumb,
                    Padding(padding: const EdgeInsets.all(8), child: info),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: thumb),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            info,
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: onOpen,
                                  icon: const Icon(Icons.open_in_new),
                                  label: Text(l.open),
                                ),
                                if (onRename != null)
                                  TextButton.icon(
                                    onPressed: onRename,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: Text(l.rename),
                                  ),
                                if (onExport != null && doc.pages.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: onExport,
                                    icon: const Icon(Icons.ios_share),
                                    label: Text(l.export),
                                  ),
                                if (onDelete != null)
                                  TextButton.icon(
                                    onPressed: onDelete,
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(l.delete),
                                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
