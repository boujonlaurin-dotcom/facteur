import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/widgets/source_logo_avatar.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';

/// Q9c bis : swipe désambiguateur (parcours « curieux »).
///
/// Présente un "spanning set" de quelques sources étalées sur les axes
/// (fond / actu directe / indépendant / référence / perspective). Chaque swipe
/// est un vote *révélé* : droite = ça m'intéresse (liké + pré-coché au reveal),
/// gauche = pas pour moi. À la fin, [OnboardingNotifier.completeSwipe] enchaîne
/// sur la page sources.
class SwipeDisambiguatorQuestion extends ConsumerStatefulWidget {
  const SwipeDisambiguatorQuestion({super.key});

  @override
  ConsumerState<SwipeDisambiguatorQuestion> createState() =>
      _SwipeDisambiguatorQuestionState();
}

class _SwipeDisambiguatorQuestionState
    extends ConsumerState<SwipeDisambiguatorQuestion> {
  /// File des cartes restantes : le **dernier** élément est la carte du dessus.
  List<SpanningSource>? _queue;
  int _total = 0;
  final List<String> _liked = [];
  final List<String> _disliked = [];
  bool _completed = false;

  void _ensureBuilt(List<Source> sources) {
    if (_queue != null) return;
    final answers = ref.read(onboardingProvider).answers;
    final set = SourceRecommender.buildSpanningSet(
      selectedThemes: answers.themes ?? const [],
      selectedSubtopics: answers.subtopics ?? const [],
      allSources: sources,
    );
    _queue = set.reversed.toList(); // dernier = première carte montrée
    _total = set.length;

    // Rien à montrer (catalogue indisponible / thèmes trop pauvres) → on saute
    // l'étape sans bloquer le parcours.
    if (set.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  void _complete() {
    if (_completed || !mounted) return;
    _completed = true;
    ref
        .read(onboardingProvider.notifier)
        .completeSwipe(List.of(_liked), List.of(_disliked));
  }

  void _vote(SpanningSource card, {required bool liked}) {
    HapticFeedback.lightImpact();
    setState(() {
      (liked ? _liked : _disliked).add(card.source.id);
      _queue!.removeLast();
    });
    if (_queue!.isEmpty) _complete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return sourcesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          OnboardingStrings.q9LoadingError,
          style: TextStyle(color: colors.textSecondary),
        ),
      ),
      data: (sources) {
        _ensureBuilt(sources);
        final queue = _queue ?? const <SpanningSource>[];
        final remaining = queue.length;
        final current = _total - remaining + 1;

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                OnboardingStrings.swipeTitle,
                style: Theme.of(context).textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                OnboardingStrings.swipeSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space2),
              if (remaining > 0)
                Text(
                  OnboardingStrings.swipeProgress
                      .replaceFirst('%d', '$current')
                      .replaceFirst('%d', '$_total'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textTertiary),
                  textAlign: TextAlign.center,
                ),

              Expanded(child: _buildCardArea(context, queue)),

              if (remaining > 0) ...[
                _buildActions(context, queue.last),
                const SizedBox(height: FacteurSpacing.space4),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardArea(BuildContext context, List<SpanningSource> queue) {
    if (queue.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final children = <Widget>[];
          for (var i = 0; i < queue.length; i++) {
            final card = queue[i];
            final depth = queue.length - 1 - i; // 0 = carte du dessus
            if (depth > 2) continue; // ne rend que le dessus + 2 cartes derrière
            final visual = SizedBox(
              width: constraints.maxWidth,
              child: _cardVisual(context, card),
            );
            if (depth == 0) {
              children.add(
                Dismissible(
                  key: ValueKey('swipe_${card.source.id}'),
                  background: _swipeHint(context, liked: true),
                  secondaryBackground: _swipeHint(context, liked: false),
                  onDismissed: (dir) =>
                      _vote(card, liked: dir == DismissDirection.startToEnd),
                  child: visual,
                ),
              );
            } else {
              children.add(
                Transform.translate(
                  offset: Offset(0, depth * 12.0),
                  child: Transform.scale(
                    scale: 1 - depth * 0.04,
                    child: IgnorePointer(child: visual),
                  ),
                ),
              );
            }
          }
          return Stack(alignment: Alignment.center, children: children);
        },
      ),
    );
  }

  Widget _cardVisual(BuildContext context, SpanningSource card) {
    final colors = context.facteurColors;
    final source = card.source;
    final desc = source.description;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceLogoAvatar(source: source, size: 44, radius: 22),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      source.getThemeLabel(),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              desc,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: FacteurSpacing.space4),
          Wrap(
            spacing: FacteurSpacing.space2,
            runSpacing: FacteurSpacing.space2,
            children: [
              _chip(context, _poleLabel(card.pole), color: colors.primary),
              _chip(context, source.getBiasLabel(), color: source.getBiasColor()),
              _chip(
                context,
                source.getReliabilityLabel(),
                color: source.getReliabilityColor(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  /// Fond affiché pendant le drag : vert (like) à droite, neutre à gauche.
  Widget _swipeHint(BuildContext context, {required bool liked}) {
    final colors = context.facteurColors;
    final color = liked ? colors.success : colors.textTertiary;
    return Container(
      alignment: liked ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Icon(
        liked ? Icons.favorite_rounded : Icons.close_rounded,
        color: color,
        size: 40,
      ),
    );
  }

  Widget _buildActions(BuildContext context, SpanningSource top) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionButton(
          context,
          icon: Icons.close_rounded,
          color: colors.textSecondary,
          tooltip: OnboardingStrings.swipeSkipHint,
          onTap: () => _vote(top, liked: false),
        ),
        const SizedBox(width: FacteurSpacing.space8),
        _actionButton(
          context,
          icon: Icons.favorite_rounded,
          color: colors.success,
          tooltip: OnboardingStrings.swipeLikeHint,
          onTap: () => _vote(top, liked: true),
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: colors.surface,
        shape: CircleBorder(side: BorderSide(color: colors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
      ),
    );
  }

  String _poleLabel(SwipeAxisPole pole) {
    switch (pole) {
      case SwipeAxisPole.deep:
        return OnboardingStrings.swipePoleDeep;
      case SwipeAxisPole.mainstream:
        return OnboardingStrings.swipePoleMainstream;
      case SwipeAxisPole.independent:
        return OnboardingStrings.swipePoleIndependent;
      case SwipeAxisPole.established:
        return OnboardingStrings.swipePoleEstablished;
      case SwipeAxisPole.perspective:
        return OnboardingStrings.swipePolePerspective;
    }
  }
}
