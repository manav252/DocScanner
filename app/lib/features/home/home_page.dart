// Home: what the app does, Scan / Import / Documents, recent scans and status.
// Works entirely without an account.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../data/sync/sync_controller.dart';
import '../capture/capture_page.dart';
import '../common/document_card.dart';
import '../editor/document_editor_page.dart';
import '../library/documents_page.dart';
import '../library/import_ui.dart';
import '../../data/models.dart';
import '../library/delete_controller.dart';
import '../library/library_controller.dart';
import '../settings/settings_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const recentCount = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final all = ref.watch(libraryProvider);
    // Rebuild for a delete only if it concerns a document this screen shows (a few
    // beyond the recent cards, which move up when one is hidden). A string key:
    // Riverpod compares selected values with ==.
    final shownIds = [for (final d in all.value ?? const <ScanDocument>[]) d.id].take(recentCount + 8).toList();
    final hiddenKey = ref.watch(pendingDeletesProvider.select((s) => shownIds.where(s.contains).join(',')));
    final hidden = hiddenKey.isEmpty ? const <String>{} : hiddenKey.split(',').toSet();
    final docs = all.whenData(
      (l) => [
        for (final d in l)
          if (!hidden.contains(d.id)) d,
      ],
    );
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const ValueKey('open-settings'),
              onPressed: () => push(const SettingsPage()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.settings),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(l.appPurpose, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                const _StatusLine(),
                const SizedBox(height: 20),
                SizedBox(
                  height: 72,
                  child: FilledButton.icon(
                    key: const ValueKey('scan-document'),
                    style: FilledButton.styleFrom(textStyle: theme.textTheme.titleMedium),
                    onPressed: () => push(const CapturePage()),
                    icon: const Icon(Icons.document_scanner_outlined, size: 28),
                    label: Text(l.scanDocument),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('import-photos'),
                      onPressed: () => importIntoNewDocument(context, ref, ImportKind.photos),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l.importPhotos),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('import-pdf'),
                      onPressed: () => importIntoNewDocument(context, ref, ImportKind.pdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l.importPdf),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('view-documents'),
                      onPressed: () => push(const DocumentsPage()),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(l.viewDocuments),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(header: true, child: Text(l.recentScans, style: theme.textTheme.titleLarge)),
                    ),
                    if (docs.value?.isNotEmpty ?? false)
                      TextButton.icon(
                        key: const ValueKey('see-all'),
                        onPressed: () => push(const DocumentsPage()),
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(l.seeAllDocuments),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                switch (docs) {
                  AsyncData(value: final list) when list.isEmpty => const _FirstTimeCard(),
                  AsyncData(value: final list) => LayoutBuilder(
                    builder: (context, c) {
                      // Fixed-width cards that grow with their text (no clipped titles at large text sizes).
                      const gap = 12.0;
                      final perRow = ((c.maxWidth + gap) / (160 + gap)).floor().clamp(2, 6);
                      final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final d in list.take(recentCount))
                            SizedBox(
                              key: ValueKey(d.id), // keeps each card's loaded thumbnail when the list changes
                              width: width,
                              child: DocumentCard(
                                doc: d,
                                compact: true,
                                onOpen: () => push(DocumentEditorPage(documentId: d.id)),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  AsyncError(:final error) => Text('$error'),
                  _ => const Center(
                    child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where scans are stored and, when signed in, how backup is doing. Only real states.
class _StatusLine extends ConsumerWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final signedIn = ref.watch(sessionProvider) != null;
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(backupSummaryProvider).value?.pending ?? 0;
    final (icon, text) = !signedIn
        ? (Icons.phone_android, l.statusLocalOnly)
        : switch (sync.phase) {
            SyncPhase.syncing => (Icons.cloud_sync_outlined, l.statusSyncing),
            SyncPhase.waking => (Icons.hourglass_top, l.serverWaking),
            SyncPhase.offline => (Icons.cloud_off_outlined, l.statusOffline),
            SyncPhase.error => (Icons.sync_problem, l.statusSyncError(sync.message ?? '')),
            _ when pending > 0 => (Icons.cloud_upload_outlined, l.pendingChanges(pending)),
            _ => (Icons.cloud_done_outlined, l.statusSynced),
          };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, key: const ValueKey('home-status'))),
        ],
      ),
    );
  }
}

class _FirstTimeCard extends StatelessWidget {
  const _FirstTimeCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text('$n')),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Card(
      key: const ValueKey('first-time'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(l.noScansYet, style: theme.textTheme.titleMedium)),
            const SizedBox(height: 4),
            Text(l.noScansHint),
            const SizedBox(height: 12),
            Text(l.howItWorksTitle, style: theme.textTheme.titleSmall),
            step(1, l.howItWorksStep1),
            step(2, l.howItWorksStep2),
            step(3, l.howItWorksStep3),
          ],
        ),
      ),
    );
  }
}
