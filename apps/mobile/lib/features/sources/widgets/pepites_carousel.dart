import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import 'pepite_card.dart';
import 'source_detail_modal.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/recos_facteur.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Recommandées par l'équipe",
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
                final isFollowing = ref.watch(userSourcesProvider).maybeWhen(
                      data: (list) =>
                          list.any((s) => s.id == source.id && s.isTrusted),
                      orElse: () => false,
                    );
                return PepiteCard(
                  source: source,
                  isFollowing: isFollowing,
                  onToggleFollow: () =>
                      _onToggleFollow(ref, source, isFollowing),
                  onTap: () => _onTap(context, ref, source),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onToggleFollow(
    WidgetRef ref,
    Source source,
    bool currentlyFollowing,
  ) async {
    await ref
        .read(userSourcesProvider.notifier)
        .toggleTrust(source.id, currentlyFollowing);
  }

  void _onTap(BuildContext context, WidgetRef ref, Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final live = ref.watch(userSourcesProvider).maybeWhen(
              data: (list) =>
                  list.where((s) => s.id == source.id).firstOrNull ?? source,
              orElse: () => source,
            );
        return SourceDetailModal(
          source: live,
          onToggleTrust: () => ref
              .read(userSourcesProvider.notifier)
              .toggleTrust(source.id, live.isTrusted),
        );
      },
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
