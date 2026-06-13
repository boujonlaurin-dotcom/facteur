import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import 'pepite_card.dart';
import 'source_detail_modal.dart';

/// Carousel de recommandations de sources curées ("Pépites"), affiché dans
/// le feed pour aider à découvrir des sources de qualité. Visibilité gérée
/// côté backend (rate-limit + cool-down) : liste vide → SizedBox.shrink.
class PepitesCarousel extends ConsumerWidget {
  final bool alwaysVisible;

  const PepitesCarousel({super.key, this.alwaysVisible = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final asyncPepites = alwaysVisible
        ? ref.watch(pepitesAlwaysProvider)
        : ref.watch(pepitesProvider);

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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/recos_facteur.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Recos. de l'équipe Facteur",
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!alwaysVisible)
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
                final state = ref.watch(userSourcesStateProvider).valueOrNull;
                final legacyFollowing = ref
                    .watch(userSourcesProvider)
                    .maybeWhen(
                      data: (list) =>
                          list.any((s) => s.id == source.id && s.isTrusted),
                      orElse: () => source.isTrusted,
                    );
                final isFollowing =
                    _isFollowedSourceState(state?.stateOf(source.id)) ||
                    legacyFollowing;
                return PepiteCard(
                  source: source.copyWith(isTrusted: isFollowing),
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
    if (currentlyFollowing) return;

    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(source.id, InterestState.followed);
      ref.invalidate(userSourcesProvider);
    } catch (_) {
      // Rollback is handled by userSourcesStateProvider's optimistic notifier.
    }
  }

  void _onTap(BuildContext context, WidgetRef ref, Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final state = ref.watch(userSourcesStateProvider).valueOrNull;
        final live = ref
            .watch(userSourcesProvider)
            .maybeWhen(
              data: (list) =>
                  list.where((s) => s.id == source.id).firstOrNull ?? source,
              orElse: () => source,
            );
        final stateFollowing = _isFollowedSourceState(
          state?.stateOf(source.id),
        );
        final display = live.copyWith(
          isTrusted: stateFollowing || live.isTrusted,
        );
        return SourceDetailModal(
          source: display,
          onToggleTrust: () async {
            final next = display.isTrusted
                ? InterestState.unfollowed
                : InterestState.followed;
            try {
              await ref
                  .read(userSourcesStateProvider.notifier)
                  .setSourceState(source.id, next);
              ref.invalidate(userSourcesProvider);
            } catch (_) {
              // Optimistic rollback is handled by the canonical notifier.
            }
          },
        );
      },
    );
  }
}

bool _isFollowedSourceState(InterestState? state) =>
    state == InterestState.followed || state == InterestState.favorite;

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
