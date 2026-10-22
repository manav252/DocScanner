// Recognised text of a page: read, select, copy.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document_controller.dart';
import 'ocr_runner.dart';

Future<void> showTextSheet(BuildContext context, {required String documentId, required String pageId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TextSheet(documentId: documentId, pageId: pageId),
    );

class _TextSheet extends ConsumerStatefulWidget {
  const _TextSheet({required this.documentId, required this.pageId});
  final String documentId, pageId;

  @override
  ConsumerState<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends ConsumerState<_TextSheet> {
  bool _running = false;
  String? _error;

  Future<void> _recognize() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await ref.read(ocrRunnerProvider).run(widget.documentId, pageIds: {widget.pageId});
    } catch (e) {
      _error = 'Text recognition failed: $e';
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final page = ref.read(documentProvider(widget.documentId)).value?.pages.where((p) => p.id == widget.pageId).firstOrNull;
      if (page != null && page.needsOcr && ref.read(ocrRunnerProvider).available) _recognize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(documentProvider(widget.documentId)).value;
    final page = doc?.pages.where((p) => p.id == widget.pageId).firstOrNull;
    final available = ref.read(ocrRunnerProvider).available;
    final text = page?.ocrText?.trim() ?? '';
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Text on this page', style: theme.textTheme.titleMedium)),
              IconButton(
                key: const ValueKey('copy-text'),
                tooltip: 'Copy all',
                onPressed: text.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied')));
                        }
                      },
                icon: const Icon(Icons.copy),
              ),
            ]),
            const SizedBox(height: 8),
            if (!available)
              const Text('Text recognition is not available on this device.')
            else if (_running || (page?.needsOcr ?? false))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Recognizing text…'),
                ]),
              )
            else if (text.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No text found on this page.'))
            else
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(text, key: const ValueKey('ocr-text'), style: theme.textTheme.bodyMedium),
                ),
              ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (available && !_running && page != null && !page.needsOcr)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref.read(documentProvider(widget.documentId).notifier).invalidateOcr(page.id);
                    await _recognize();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recognize again'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
