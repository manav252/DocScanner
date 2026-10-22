// Bottom sheet with a live preview of each filter for the current page.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';

/// Preview of [page] with [filter] (keeps its rotation and crop).
final filterPreviewProvider =
    FutureProvider.autoDispose.family<Uint8List, ({ScanPage page, PageFilter filter})>((ref, key) async {
  final flat = await ref.watch(documentRepositoryProvider).pageImage(key.page.id, PageImage.flat);
  if (flat == null) throw StateError('missing page image');
  return ref.watch(scanEngineProvider).processEncoded(flat, key.page.edits.copyWith(filter: key.filter), maxSide: 360);
});

Future<void> showFilterSheet(
  BuildContext context, {
  required ScanPage page,
  required ValueChanged<PageFilter> onSelected,
  required ValueChanged<PageFilter> onApplyAll,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FilterSheet(page: page, onSelected: onSelected, onApplyAll: onApplyAll),
    );

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.page, required this.onSelected, required this.onApplyAll});
  final ScanPage page;
  final ValueChanged<PageFilter> onSelected, onApplyAll;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late PageFilter _selected = widget.page.edits.filter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: Row(children: [
              for (final f in PageFilter.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      key: ValueKey('filter-${f.wireName}'),
                      onTap: () {
                        setState(() => _selected = f);
                        widget.onSelected(f);
                      },
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: f == _selected ? scheme.primary : scheme.outlineVariant,
                                width: f == _selected ? 3 : 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: switch (ref.watch(filterPreviewProvider((page: widget.page, filter: f)))) {
                              AsyncData(:final value) => Image.memory(value, fit: BoxFit.contain),
                              AsyncError() => const Icon(Icons.broken_image_outlined),
                              _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(f.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              widget.onApplyAll(_selected);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.done_all),
            label: Text('Apply ${_selected.label} to all pages'),
          ),
        ]),
      ),
    );
  }
}
