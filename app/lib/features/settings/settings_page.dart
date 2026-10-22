// Settings: Simple Mode, appearance, language, scanning, text recognition,
// optional backup (sign-in), help.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../data/sync/sync_controller.dart';
import '../account/account_page.dart';
import '../diagnostics/detector_diagnostics_page.dart';
import '../library/library_controller.dart';
import '../onboarding/onboarding_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(appSettingsProvider);
    void update(AppSettings next) => ref.read(appSettingsProvider.notifier).update(next);

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Switch(
                key: const ValueKey('simple-mode'),
                title: l.simpleMode,
                subtitle: l.simpleModeHint,
                value: s.simpleMode,
                onChanged: (v) => update(s.copyWith(simpleMode: v)),
              ),
              _Section(l.appearance),
              _Label(l.theme),
              ChoiceRow<ThemeChoice>(
                values: ThemeChoice.values,
                selected: s.theme,
                label: (t) => switch (t) {
                  ThemeChoice.system => l.themeSystem,
                  ThemeChoice.light => l.themeLight,
                  ThemeChoice.dark => l.themeDark,
                },
                onSelected: (t) => update(s.copyWith(theme: t)),
              ),
              _Switch(
                key: const ValueKey('high-contrast'),
                title: l.highContrast,
                subtitle: l.highContrastHint,
                value: s.highContrast,
                onChanged: (v) => update(s.copyWith(highContrast: v)),
              ),
              _Label(l.textSize),
              ChoiceRow<double>(
                values: AppSettings.textScales,
                selected: s.textScale,
                label: (v) => '${(v * 100).round()}%',
                onSelected: (v) => update(s.copyWith(textScale: v)),
              ),
              _Section(l.language),
              ChoiceRow<String?>(
                values: const [null, 'en', 'hi'],
                selected: s.localeCode,
                label: (c) => switch (c) {
                  'en' => 'English',
                  'hi' => 'हिन्दी',
                  _ => l.languageSystem,
                },
                onSelected: (c) => update(s.copyWith(localeCode: c)),
              ),
              _Section(l.scanning),
              _Switch(
                key: const ValueKey('spoken-guidance'),
                title: l.spokenGuidance,
                subtitle: l.spokenGuidanceHint,
                value: s.spokenGuidance,
                onChanged: (v) => update(s.copyWith(spokenGuidance: v)),
              ),
              _Section(l.textRecognition),
              _Switch(
                key: const ValueKey('auto-ocr'),
                title: l.autoOcr,
                subtitle: l.autoOcrHint,
                value: s.autoOcr,
                onChanged: (v) => update(s.copyWith(autoOcr: v)),
              ),
              _Label(l.ocrLanguage),
              ChoiceRow<OcrLanguage>(
                values: OcrLanguage.values,
                selected: s.ocrLanguage,
                label: (o) => o == OcrLanguage.english ? l.langEnglish : l.langHindi,
                onSelected: (o) => update(s.copyWith(ocrLanguage: o)),
              ),
              _Section(l.backupSync),
              const _BackupCard(),
              _Section(l.help),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('show-guide'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const OnboardingPage(popOnFinish: true))),
                  icon: const Icon(Icons.school_outlined),
                  label: Text(l.showGuide),
                ),
              ),
              if (!s.simpleMode) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const DetectorDiagnosticsPage())),
                    icon: const Icon(Icons.biotech_outlined),
                    label: Text(l.diagnostics),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = ref.watch(sessionProvider);
    final status = ref.watch(syncControllerProvider);
    final summary = ref.watch(backupSummaryProvider).value;
    void openAccount() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPage()));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (session == null) ...[
            Text(l.backupSyncHint),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('open-backup'),
              onPressed: openAccount,
              icon: const Icon(Icons.cloud_outlined),
              label: Text(l.backupSync),
            ),
          ] else ...[
            Text(l.signedInAs(session.email)),
            const SizedBox(height: 8),
            Row(children: [
              SyncIcon(status: status),
              const SizedBox(width: 8),
              Expanded(child: Text(describeSync(context, status))),
            ]),
            if ((summary?.pending ?? 0) > 0) ...[const SizedBox(height: 4), Text(l.pendingChanges(summary!.pending))],
            if (status.conflicts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(l.conflictsResolved(status.conflicts.length, status.conflicts.join(', '))),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: openAccount, icon: const Icon(Icons.manage_accounts_outlined), label: Text(l.backupSync)),
              if ((summary?.localOnly ?? 0) > 0)
                FilledButton.tonalIcon(
                  key: const ValueKey('upload-local'),
                  onPressed: () async {
                    final actions = ref.read(libraryActionsProvider);
                    await actions.backUp(await actions.localOnly());
                    ref.read(syncControllerProvider.notifier).syncNow();
                  },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text('${l.uploadLocalDocs} (${summary!.localOnly})'),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(text, style: Theme.of(context).textTheme.labelLarge));
}

class _Switch extends StatelessWidget {
  const _Switch({super.key, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}

/// Single choice shown as labelled chips that wrap (works at 200% text size).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.values, required this.selected, required this.label, required this.onSelected});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onSelected(v),
          ),
      ]);
}
