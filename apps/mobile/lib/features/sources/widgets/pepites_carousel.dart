import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import 'pepite_card.dart';
import 'pepite_preview_sheet.dart';

/// Carousel de recommandations de sources curées ("Pépites"), affiché dans
/// le feed pour aider à découvrir des sources de qualité. Visibilité gérée
/// côté backend (rate-limit + cool-down) : liste vide → SizedBox.shrink.
class PepitesCarousel extends ConsumerWidget {
  const PepitesCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final asyncPepites = ref.watch(pepitesProvider);

    return asyncPepites.when(
      data: (sources) {
        if (sources.isEmpty) return const SizedBox.shrink();
        return _buildCarousel(context, ref, colors, sources);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCarousel(
    BuildContext context,
    WidgetRef ref,
    FacteurColors colors,
    List<Source> sources,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Des sources à découvrir',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                _DismissButton(
                  onPressed: () =>
                      ref.read(pepitesProvider.notifier).dismiss(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: sources.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final source = sources[index];
                return PepiteCard(
                  source: source,
                  onFollow: () => _onFollow(context, ref, source),
                  onTap: () => _onTap(context, ref, source),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onFollow(
    BuildContext context,
    WidgetRef ref,
    Source source,
  ) async {
    ref.read(pepitesProvider.notifier).removeLocal(source.id);
    try {
      await ref.read(sourcesRepositoryProvider).trustSource(source.id);
      ref.invalidate(userSourcesProvider);
    } catch (_) {
      // silent : retry au prochain refresh
    }
  }

  void _onTap(BuildContext context, WidgetRef ref, Source source) {
    PepitePreviewSheet.show(
      context,
      source: source,
      onFollow: () => _onFollow(context, ref, source),
    );
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DismissButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      label: 'Masquer les recommandations',
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            PhosphorIcons.x(PhosphorIconsStyle.bold),
            size: 16,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
