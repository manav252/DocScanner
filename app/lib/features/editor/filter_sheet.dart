// Filters: a large preview of the chosen look with a before/after compare,
// and a labelled preview card for each filter.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';

/// Preview of [page] with [filter] (keeps its rotation and crop).
final filterPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List, ({ScanPage page, PageFilter filter, int maxSide})>((ref, key) async {
      final flat = await ref.watch(documentRepositoryProvider).pageImage(key.page.id, PageImage.flat);
      if (flat == null) throw StateError('missing page image');
      return ref
          .watch(scanEngineProvider)
          .processEncoded(flat, key.page.edits.copyWith(filter: key.filter), maxSide: key.maxSide);
    });

String filterLabel(BuildContext context, PageFilter f) {
  final l = context.l10n;
  return switch (f) {
    PageFilter.original => l.filterOriginal,
    PageFilter.grayscale => l.filterGrayscale,
    PageFilter.bw => l.filterBw,
    PageFilter.magicColor => l.filterMagic,
  };
}

Future<void> showFilterSheet(
  BuildContext context, {
  required ScanPage page,
  required Future<void> Function(PageFilter) onSelected,
  required Future<void> Function(PageFilter) onApplyAll,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => FilterSheet(page: page, onSelected: onSelected, onApplyAll: onApplyAll),
);

class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key, required this.page, required this.onSelected, required this.onApplyAll});
  final ScanPage page;
  final Future<void> Function(PageFilter) onSelected, onApplyAll;

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late PageFilter _selected = widget.page.edits.filter;
  bool _compare = false;
  bool _applying = false;

  Future<void> _apply(Future<void> Function() op) async {
    setState(() => _applying = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Widget _preview(PageFilter f, int maxSide, {BoxFit fit = BoxFit.contain}) =>
      switch (ref.watch(filterPreviewProvider((page: widget.page, filter: f, maxSide: maxSide)))) {
        AsyncData(:final value) => Image.memory(value, fit: fit, gaplessPlayback: true),
        AsyncError() => Center(child: Text(context.l10n.previewFailed, textAlign: TextAlign.center)),
        _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = _compare ? PageFilter.original : _selected;
    // Load the "before" image up front so Compare switches instantly.
    ref.watch(filterPreviewProvider((page: widget.page, filter: PageFilter.original, maxSide: 900)));
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(l.toolFilters, style: theme.textTheme.titleLarge)),
            const SizedBox(height: 12),
            // Large preview with a Before/After label (not colour alone).
            SizedBox(
              height: (height * 0.38).clamp(180.0, 420.0),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      image: true,
                      label: '${_compare ? l.before : l.after}: ${filterLabel(context, shown)}',
                      child: _preview(shown, 900),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(_compare ? l.before : l.after, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                  if (_applying)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(6)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 8),
                              Text(l.applying),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('compare-original'),
                avatar: const Icon(Icons.compare, size: 18),
                label: Text(l.showOriginal),
                selected: _compare,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (v) => setState(() => _compare = v),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final f in PageFilter.values)
                  _FilterCard(
                    key: ValueKey('filter-${f.wireName}'),
                    label: filterLabel(context, f),
                    selected: f == _selected,
                    preview: _preview(f, 240, fit: BoxFit.cover),
                    onTap: _applying
                        ? null
                        : () {
                            setState(() {
                              _selected = f;
                              _compare = false;
                            });
                            _apply(() => widget.onSelected(f));
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('apply-all'),
                  onPressed: _applying
                      ? null
                      : () async {
                          await _apply(() => widget.onApplyAll(_selected));
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.done_all),
                  label: Text(l.applyToAll(filterLabel(context, _selected))),
                ),
                FilledButton.icon(
                  key: const ValueKey('filters-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: Text(l.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    super.key,
    required this.label,
    required this.selected,
    required this.preview,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Widget preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: 112,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 3 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 120,
                  child: ClipRRect(borderRadius: BorderRadius.circular(4), child: preview),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // A check mark as well as the border: selection is not shown by colour alone.
                    if (selected) ...[
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                      const SizedBox(width: 4),
                    ],
                    Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
