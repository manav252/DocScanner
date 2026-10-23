// Settings › Storage and backup: privacy note, space used, export everything as
// a ZIP and import it again (a backup that needs no account).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cancel.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/backup.dart';
import '../../services/export/share_service.dart';

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final usage = ref.watch(storageUsageProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(l.privacyNote, key: const ValueKey('privacy-note'))),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          switch (usage) {
            AsyncData(value: (bytes: final b?, :final documents, :final pages)) => l.storageUsed(
              formatBytes(b),
              documents,
              pages,
            ),
            AsyncData(value: (bytes: null, :final documents, :final pages)) => l.storageUnknown(documents, pages),
            _ => '…',
          },
          key: const ValueKey('storage-used'),
        ),
        const SizedBox(height: 12),
        Text(l.exportAllHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('export-all'),
              onPressed: () => _exportAll(context, ref),
              icon: const Icon(Icons.archive_outlined),
              label: Text(l.exportAll),
            ),
            OutlinedButton.icon(
              key: const ValueKey('import-backup'),
              onPressed: () => _importBackup(context, ref),
              icon: const Icon(Icons.unarchive_outlined),
              label: Text(l.importBackup),
            ),
          ],
        ),
      ],
    );
  }

  /// Progress dialog with Cancel around [task].
  static Future<T?> _withProgress<T>(
    BuildContext context,
    String title,
    Future<T> Function(CancelToken cancel, void Function(int, int) progress) task,
  ) async {
    final l = context.l10n;
    final cancel = CancelToken();
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (_, v, _) => LinearProgressIndicator(value: v),
          ),
          actions: [
            TextButton.icon(onPressed: cancel.cancel, icon: const Icon(Icons.close), label: Text(l.cancel)),
          ],
        ),
      ),
    );
    try {
      return await task(cancel, (done, total) => progress.value = total == 0 ? null : done / total);
    } finally {
      navigator.pop();
      progress.dispose();
    }
  }

  Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final zip = await _withProgress(
        context,
        l.makingBackup,
        (cancel, progress) => ref.read(backupServiceProvider).exportAll(cancel: cancel, onProgress: progress),
      );
      if (zip == null) return;
      final d = DateTime.now();
      final name = 'DocScanner backup ${d.year}-${_two(d.month)}-${_two(d.day)}.zip';
      final file = ExportFile(name, zip, 'application/zip');
      final share = ref.read(shareServiceProvider);
      if (share.canDownload) {
        await share.download([file]);
      } else {
        await share.share([file], subject: name);
      }
      messenger.showSnackBar(SnackBar(content: Text(l.backupSaved(name))));
    } on Cancelled {
      messenger.showSnackBar(SnackBar(content: Text(l.exportCancelled)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.backupFailed('$e'))));
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(importServiceProvider).pickBackup();
      if (file == null || !context.mounted) return;
      final r = await _withProgress(
        context,
        l.restoringBackup,
        (cancel, progress) =>
            ref.read(backupServiceProvider).importZip(file.bytes, cancel: cancel, onProgress: progress),
      );
      if (r == null) return;
      ref.invalidate(storageUsageProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.backupRestored(r.added, r.updated, r.skipped))));
    } on Cancelled {
      messenger.showSnackBar(SnackBar(content: Text(l.importCancelled)));
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.backupFailed(e.message))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.backupFailed('$e'))));
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
