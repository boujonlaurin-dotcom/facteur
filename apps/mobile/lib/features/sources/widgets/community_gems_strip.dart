import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';

class CommunityGemsStrip extends ConsumerWidget {
  final void Function(Source source) onSourceTap;
  final void Function(String sourceId)? onGemTap;

  const CommunityGemsStrip({
    super.key,
    required this.onSourceTap,
    this.onGemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final trendingAsync = ref.watch(trendingSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIcons.fire(PhosphorIconsStyle.regular),
                size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'Pepites de la communaute',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        trendingAsync.when(
          data: (sources) {
            if (sources.isEmpty) {
              return Text(
                'Aucune pepite pour le moment.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textTertiary),
              );
            }
            return SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) =>
                    _buildGemItem(context, sources[index]),
              ),
            );
          },
          loading: () => SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => _buildPlaceholder(context),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildGemItem(BuildContext context, Source source) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: () {
        onGemTap?.call(source.id);
        onSourceTap(source);
      },
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildLogo(source, colors),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              source.getThemeLabel(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (source.followerCount > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(PhosphorIcons.users(PhosphorIconsStyle.regular),
                      size: 10, color: colors.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    '${source.followerCount}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(Source source, FacteurColors colors) {
    if (source.logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          source.logoUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLogoFallback(colors),
        ),
      );
    }
    return _buildLogoFallback(colors);
  }

  Widget _buildLogoFallback(FacteurColors colors) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
          size: 16, color: colors.primary),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 60,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 50,
            height: 10,
            decoration: BoxDecoration(
              color: colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
