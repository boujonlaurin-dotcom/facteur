import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';

class CommunityGemsStrip extends ConsumerStatefulWidget {
  final void Function(Source source) onSourceTap;
  final void Function(String sourceId)? onGemTap;

  const CommunityGemsStrip({
    super.key,
    required this.onSourceTap,
    this.onGemTap,
  });

  @override
  ConsumerState<CommunityGemsStrip> createState() => _CommunityGemsStripState();
}

class _CommunityGemsStripState extends ConsumerState<CommunityGemsStrip> {
  bool _expanded = false;

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
              Icon(PhosphorIcons.fire(PhosphorIconsStyle.regular),
                  size: 20, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pépites de la communauté',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Les sources favorites de la communauté Facteur',
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
    final trendingAsync = ref.watch(trendingSourcesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: trendingAsync.when(
        data: (sources) {
          if (sources.isEmpty) {
            return Text(
              'Aucune pépite pour le moment.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textTertiary),
            );
          }
          return Column(
            children: [
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 8),
              ...sources.map((s) => _buildGemTile(context, colors, s)),
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
          'Impossible de charger les pépites.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }

  Widget _buildGemTile(
      BuildContext context, FacteurColors colors, Source source) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        widget.onGemTap?.call(source.id);
        widget.onSourceTap(source);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            _buildLogo(source, colors),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.getThemeLabel(),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (source.followerCount > 0) ...[
                        const SizedBox(width: 8),
                        Icon(PhosphorIcons.users(PhosphorIconsStyle.regular),
                            size: 11, color: colors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          '${source.followerCount}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
                size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(Source source, FacteurColors colors) {
    if (source.logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          source.logoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLogoFallback(colors),
        ),
      );
    }
    return _buildLogoFallback(colors);
  }

  Widget _buildLogoFallback(FacteurColors colors) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
          size: 18, color: colors.primary),
    );
  }
}
