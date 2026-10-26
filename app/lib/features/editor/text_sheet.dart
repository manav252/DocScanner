// Recognised text of a page: read, select, copy. Shows progress, clear errors,
// "No text found" (never random letters), and lets the user pick the language.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../settings/settings_page.dart' show ChoiceRow;
import 'document_controller.dart';
import 'ocr_runner.dart';

Future<void> showTextSheet(BuildContext context, {required String documentId, required String pageId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TextSheet(documentId: documentId, pageId: pageId),
    );

class TextSheet extends ConsumerStatefulWidget {
  const TextSheet({super.key, required this.documentId, required this.pageId});
  final String documentId, pageId;

  @override
  ConsumerState<TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends ConsumerState<TextSheet> {
  bool _running = false, _copied = false, _autoStarted = false;
  String? _error;

  Future<void> _recognize() async {
    setState(() {
      _running = true;
      _error = null;
      _copied = false;
    });
    try {
      await ref.read(ocrRunnerProvider).run(widget.documentId, pageIds: {widget.pageId});
    } catch (e) {
      _error = switch (e) {
        StateError(:final message) => message,
        UnsupportedError(:final message) => message ?? '$e',
        _ => '$e'.replaceFirst(RegExp(r'^\w*(Exception|Error): '), ''),
      };
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    SemanticsService.sendAnnouncement(View.of(context), context.l10n.copied, Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(appSettingsProvider);
    final lang = settings.ocrLanguage.code;
    final doc = ref.watch(documentProvider(widget.documentId)).value;
    final page = doc?.pages.where((p) => p.id == widget.pageId).firstOrNull;
    final available = ref.read(ocrRunnerProvider).available;
    final pending = _running || (page?.needsOcrIn(lang) ?? false);
    final text = page?.ocrText?.trim() ?? '';
    final theme = Theme.of(context);
    // Read the page as soon as it is loaded (once), if its text is missing or outdated.
    if (!_autoStarted && page != null && available && page.needsOcrIn(lang)) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _recognize() : null);
    }

    final Widget body;
    if (!available) {
      body = Text(l.ocrUnavailable);
    } else if (_error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.ocrFailed(_error!), style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _recognize, icon: const Icon(Icons.refresh), label: Text(l.tryAgain)),
        ],
      );
    } else if (pending) {
      body = Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const LinearProgressIndicator(), const SizedBox(height: 12), Text(l.recognisingText)],
        ),
      );
    } else if (text.isEmpty) {
      body = Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.noTextFound, key: const ValueKey('no-text'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(l.noTextFoundHint),
          ],
        ),
      );
    } else {
      body = Flexible(
        child: SingleChildScrollView(
          child: SelectableText(text, key: const ValueKey('ocr-text'), style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(l.textOnPage, style: theme.textTheme.titleLarge)),
              const SizedBox(height: 4),
              Row(
                key: const ValueKey('handwriting-note'),
                children: [
                  Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.handwritingNote,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              body,
              const SizedBox(height: 16),
              if (available) ...[
                Text(l.readAs, style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                ChoiceRow<OcrLanguage>(
                  values: OcrLanguage.values,
                  selected: settings.ocrLanguage,
                  label: (o) => o == OcrLanguage.english ? l.langEnglish : l.langHindi,
                  onSelected: (o) async {
                    await ref.read(appSettingsProvider.notifier).update(settings.copyWith(ocrLanguage: o));
                    await _recognize();
                  },
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (available && !pending && page != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(documentProvider(widget.documentId).notifier).invalidateOcr(page.id);
                        await _recognize();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(l.recogniseAgain),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('copy-text'),
                    onPressed: text.isEmpty || pending ? null : () => _copy(text),
                    icon: Icon(_copied ? Icons.check : Icons.copy),
                    label: Text(_copied ? l.copied : l.copyText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
