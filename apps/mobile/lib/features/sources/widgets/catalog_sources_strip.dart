import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import 'source_logo_avatar.dart';
import 'theme_filter_chips.dart';

class CatalogSourcesStrip extends ConsumerStatefulWidget {
  final void Function(Source source) onSourceTap;

  const CatalogSourcesStrip({super.key, required this.onSourceTap});

  @override
  ConsumerState<CatalogSourcesStrip> createState() =>
      _CatalogSourcesStripState();
}

class _CatalogSourcesStripState extends ConsumerState<CatalogSourcesStrip> {
  bool _expanded = false;
  String? _selectedTheme;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, colors),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _buildExpanded(context, colors)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FacteurColors colors) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  PhosphorIcons.bookOpen(PhosphorIconsStyle.regular),
                  size: 17,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toutes les sources déjà ajoutées',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Parcourez le catalogue Facteur par thème',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, FacteurColors colors) {
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: sourcesAsync.when(
        data: (sources) {
          final curated =
              sources
                  .where(
                    (s) =>
                        s.isCurated &&
                        (_selectedTheme == null ||
                            s.theme?.toLowerCase() == _selectedTheme),
                  )
                  .toList()
                ..sort((a, b) {
                  final themeCompare = a.getThemeLabel().compareTo(
                    b.getThemeLabel(),
                  );
                  if (themeCompare != 0) return themeCompare;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 12),
              ThemeFilterChips(
                selectedTheme: _selectedTheme,
                onSelected: (key) => setState(() => _selectedTheme = key),
              ),
              const SizedBox(height: 10),
              if (curated.isEmpty)
                Text(
                  'Aucune source dans ce thème.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                )
              else
                SizedBox(
                  height: math.min(336, curated.length * 58).toDouble(),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: curated.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: colors.border),
                    itemBuilder: (_, index) =>
                        _buildCatalogTile(context, colors, curated[index]),
                  ),
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, __) => Text(
          'Impossible de charger le catalogue.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }

  Widget _buildCatalogTile(
    BuildContext context,
    FacteurColors colors,
    Source source,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onSourceTap(source),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SourceLogoAvatar(source: source, size: 36, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    source.getThemeLabel(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

}
