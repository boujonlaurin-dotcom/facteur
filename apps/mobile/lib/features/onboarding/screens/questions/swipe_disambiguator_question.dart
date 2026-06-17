import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/widgets/source_detail_modal.dart';
import '../../../sources/widgets/source_logo_avatar.dart';
import '../../../sources/widgets/source_type_badge.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';

/// Q9c : swipe de calibration (inconditionnel, cœur du parcours v7).
///
/// Présente un "spanning set" de ~8-10 sources étalées sur les axes
/// (fond / actu directe / indépendant / référence / perspective). Chaque swipe
/// est un vote *révélé* : droite = ça m'intéresse (liké + pré-coché au reveal),
/// gauche = pas pour moi. Le profil se construit en direct (chips sous le
/// compteur) et le signal par pôle repondère toutes les sources du pôle au
/// reveal (cf. [SourceRecommender]). À la fin,
/// [OnboardingNotifier.completeSwipe] enchaîne sur la page sources.
///
/// Physique : carte custom suivie au drag (rotation + translation), fling hors
/// écran si le seuil est dépassé, sinon retour élastique. Cartes cliquables
/// (→ [SourceDetailModal]) pour explorer avant de trancher.
class SwipeDisambiguatorQuestion extends ConsumerStatefulWidget {
  const SwipeDisambiguatorQuestion({super.key});

  @override
  ConsumerState<SwipeDisambiguatorQuestion> createState() =>
      _SwipeDisambiguatorQuestionState();
}

/// Intention de vote différée le temps de l'animation de fling.
class _VoteIntent {
  final SpanningSource card;
  final bool liked;
  const _VoteIntent(this.card, this.liked);
}

/// Vote déjà appliqué, utilisé pour restaurer exactement la dernière carte.
class _SwipeVote {
  final SpanningSource card;
  final bool liked;
  const _SwipeVote({required this.card, required this.liked});
}

class _SwipeDisambiguatorQuestionState
    extends ConsumerState<SwipeDisambiguatorQuestion>
    with SingleTickerProviderStateMixin {
  /// File des cartes restantes : le **dernier** élément est la carte du dessus.
  List<SpanningSource>? _queue;

  /// Libellé d'en-tête (groupe) par id de source : l'en-tête affiche celui de la
  /// carte du dessus et change quand on passe d'un bloc à l'autre.
  final Map<String, String> _groupLabelById = {};
  int _total = 0;
  final List<String> _liked = [];
  final List<String> _disliked = [];
  final List<_SwipeVote> _voteHistory = [];

  /// Score net par pôle (alimente les chips de profil en direct).
  final Map<SwipeAxisPole, int> _poleScore = {};

  bool _completed = false;
  bool _hasInteracted = false;
  bool _finishedSwipe = false;

  /// Moment « on affine vos sources » en fin de tri (overlay + délai).
  bool _refining = false;
  Timer? _refineTimer;

  /// Micro-indice « On affine… » qui apparaît brièvement après chaque vote.
  bool _hintVisible = false;
  Timer? _hintTimer;

  // ── Physique du drag ────────────────────────────────────────────────────
  late final AnimationController _slideController;
  Offset _dragOffset = Offset.zero;
  Offset _animFrom = Offset.zero;
  Offset _animTo = Offset.zero;
  Curve _animCurve = Curves.easeOut;
  _VoteIntent? _pendingVote;

  /// Largeur de la carte du dessus (capturée au build) : sert au fling
  /// programmatique déclenché par les boutons d'action.
  double _cardWidth = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )
      ..addListener(() {
        setState(() {
          final t = _animCurve.transform(_slideController.value);
          _dragOffset = Offset.lerp(_animFrom, _animTo, t)!;
        });
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        final vote = _pendingVote;
        _pendingVote = null;
        // Remet l'ancrage à zéro pour la prochaine carte sans saut visuel.
        _animFrom = Offset.zero;
        _animTo = Offset.zero;
        _slideController.reset();
        if (vote != null) {
          _vote(vote.card, liked: vote.liked);
        }
      });
  }

  @override
  void dispose() {
    _refineTimer?.cancel();
    _hintTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  void _ensureBuilt(List<Source> sources) {
    if (_queue != null) return;
    final answers = ref.read(onboardingProvider).answers;
    // Groupes contigus par pôle, ordonnés par les prefs déclarées (le set de
    // cartes est inchangé ⇒ même calibration), chaque carte portant le libellé
    // d'en-tête de son groupe.
    final groups = SourceRecommender.buildSpanningGroups(
      selectedThemes: answers.themes ?? const [],
      selectedSubtopics: answers.subtopics ?? const [],
      allSources: sources,
      independencePref: answers.independencePref,
      depthPref: answers.approach,
    );
    final flat = <SpanningSource>[];
    for (final group in groups) {
      for (final card in group.cards) {
        flat.add(card);
        _groupLabelById[card.source.id] = group.label;
      }
    }
    _queue = flat.reversed.toList(); // dernier = première carte montrée
    _total = flat.length;
    _preloadTopProfiles();

    // Rien à montrer (catalogue indisponible / thèmes trop pauvres) → on saute
    // l'étape sans bloquer le parcours.
    if (flat.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  void _complete() {
    if (_completed || !mounted) return;
    _completed = true; // anti-réentrance dès l'entrée

    // Set vide : on saute l'étape sans loader (préserve le parcours minimal).
    if (_total == 0) {
      _finishSwipe();
      return;
    }

    // Tri terminé : moment « on affine vos sources » (~1,4 s) avant de basculer.
    setState(() => _refining = true);
    _refineTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _finishSwipe();
    });
  }

  void _finishSwipe() {
    _finishedSwipe = true;
    ref
        .read(onboardingProvider.notifier)
        .completeSwipe(List.of(_liked), List.of(_disliked));
  }

  void _vote(SpanningSource card, {required bool liked}) {
    HapticFeedback.lightImpact();
    setState(() {
      _hasInteracted = true;
      _voteHistory.add(_SwipeVote(card: card, liked: liked));
      (liked ? _liked : _disliked).add(card.source.id);
      _poleScore[card.pole] = (_poleScore[card.pole] ?? 0) + (liked ? 1 : -1);
      _queue!.removeLast();
      _dragOffset = Offset.zero;
    });
    _preloadTopProfiles();
    _flashCalibratingHint();
    if (_queue!.isEmpty) _complete();
  }

  bool get _canUndoSwipe => _voteHistory.isNotEmpty && !_finishedSwipe;

  void _undoLastSwipe() {
    if (!_canUndoSwipe) return;
    HapticFeedback.selectionClick();

    if (_slideController.isAnimating) {
      _slideController.stop();
    }
    _slideController.reset();
    _pendingVote = null;
    _animFrom = Offset.zero;
    _animTo = Offset.zero;
    _refineTimer?.cancel();
    _hintTimer?.cancel();

    final vote = _voteHistory.removeLast();
    final votedIds = vote.liked ? _liked : _disliked;
    final index = votedIds.lastIndexOf(vote.card.source.id);
    if (index != -1) {
      votedIds.removeAt(index);
    }

    final reversedDelta = vote.liked ? -1 : 1;
    final nextScore = (_poleScore[vote.card.pole] ?? 0) + reversedDelta;
    if (nextScore == 0) {
      _poleScore.remove(vote.card.pole);
    } else {
      _poleScore[vote.card.pole] = nextScore;
    }

    setState(() {
      _completed = false;
      _refining = false;
      _hintVisible = false;
      _dragOffset = Offset.zero;
      _queue ??= <SpanningSource>[];
      _queue!.add(vote.card);
    });
    _preloadTopProfiles();
  }

  void _preloadTopProfiles() {
    final queue = _queue;
    if (queue == null || queue.isEmpty) return;
    for (final card in queue.reversed.take(3)) {
      ref.read(sourceProfileProvider(card.source.id).future).ignore();
    }
  }

  /// Fait apparaître brièvement le micro-indice « On affine… » après un vote.
  void _flashCalibratingHint() {
    _hintTimer?.cancel();
    setState(() => _hintVisible = true);
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _hintVisible = false);
    });
  }

  /// Anime la carte du dessus vers [target] ; si [commit] est fourni, valide le
  /// vote à la fin de l'animation (fling hors écran).
  void _animateTo(Offset target, Curve curve, {_VoteIntent? commit}) {
    _animFrom = _dragOffset;
    _animTo = target;
    _animCurve = curve;
    _pendingVote = commit;
    _slideController
      ..reset()
      ..forward();
  }

  /// Largeur de référence pour les seuils / la sortie d'écran.
  double get _refWidth =>
      _cardWidth > 0 ? _cardWidth : MediaQuery.of(context).size.width;

  void _onPanStart(DragStartDetails _) {
    if (!_hasInteracted) setState(() => _hasInteracted = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_slideController.isAnimating) return;
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails details, SpanningSource card) {
    if (_slideController.isAnimating) return;
    final dx = _dragOffset.dx;
    final vx = details.velocity.pixelsPerSecond.dx;
    final threshold = _refWidth * 0.28;
    final passed = dx.abs() > threshold || vx.abs() > 900;
    if (passed) {
      final liked = (dx.abs() < 1 ? vx : dx) > 0;
      _flingOut(card, liked: liked, fromDy: _dragOffset.dy);
    } else {
      _animateTo(Offset.zero, Curves.easeOutBack);
    }
  }

  /// Projette la carte hors écran dans la direction du vote puis valide.
  void _flingOut(
    SpanningSource card, {
    required bool liked,
    double fromDy = -40,
  }) {
    if (_slideController.isAnimating) return;
    final dir = liked ? 1.0 : -1.0;
    _animateTo(
      Offset(dir * _refWidth * 1.4, fromDy),
      Curves.easeOut,
      commit: _VoteIntent(card, liked),
    );
  }

  void _showSourceDetail(SpanningSource card) {
    setState(() => _hasInteracted = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceDetailModal(
        source: card.source,
        selectLabel: OnboardingStrings.swipeLikeHint,
        isSelectedOverride: _liked.contains(card.source.id),
        articleOpener: openSourceArticleOnRootNavigator,
        onToggleTrust: () {
          _flingOut(card, liked: true);
        },
      ),
    );
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
        final groupLabel =
            queue.isNotEmpty ? (_groupLabelById[queue.last.source.id] ?? '') : '';

        final content = Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FacteurSpacing.space4),
              // En-tête dynamique : libellé du groupe de la carte du dessus
              // (remplace l'ancien titre statique), animé au changement de bloc.
              if (groupLabel.isNotEmpty)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    groupLabel,
                    key: ValueKey(groupLabel),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                OnboardingStrings.swipeSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space2),
              if (remaining > 0)
                Text(
                  _humanizedProgress(current, _total),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              _buildCalibratingHint(context),
              // Deck centré verticalement dans l'espace restant, avec l'indice
              // « toucher » directement sous la carte (B.1 + B.3).
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: _buildCardArea(context, queue)),
                    _buildTapHint(context, isFirstCard: remaining == _total),
                  ],
                ),
              ),
              if (remaining > 0) ...[
                _buildProfileInline(context),
                _buildActions(context, queue.last),
                const SizedBox(height: FacteurSpacing.space4),
              ],
            ],
          ),
        );

        return Stack(
          children: [
            content,
            if (_refining) _buildRefiningOverlay(context),
          ],
        );
      },
    );
  }

  /// Compteur humanisé à 3 paliers selon l'avancement (current/total) : libellés
  /// plus présents qu'un sec « Carte X sur Y », sans em-dash (règle PO).
  String _humanizedProgress(int current, int total) {
    final ratio = total > 0 ? current / total : 0.0;
    final String template;
    if (ratio <= 0.3) {
      template = OnboardingStrings.swipeProgressStart;
    } else if (ratio >= 0.7) {
      template = OnboardingStrings.swipeProgressEnd;
    } else {
      template = OnboardingStrings.swipeProgressMiddle;
    }
    return template.replaceFirst('%d', '$current').replaceFirst('%d', '$total');
  }

  /// Phrase inline « ce qu'on retient » placée *sous* le deck (au-dessus des
  /// actions) : libellés des pôles net-positifs joints par virgules. Masquée
  /// tant qu'aucun pôle n'est net-positif.
  Widget _buildProfileInline(BuildContext context) {
    final colors = context.facteurColors;
    final activePoles =
        SwipeAxisPole.values.where((p) => (_poleScore[p] ?? 0) > 0).toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: activePoles.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
              child: Text(
                OnboardingStrings.swipeProfileInline +
                    activePoles.map(_poleLabel).join(', '),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
    );
  }

  /// Micro-indice « On affine… » qui pulse brièvement après chaque vote.
  Widget _buildCalibratingHint(BuildContext context) {
    final colors = context.facteurColors;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: _hintVisible ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.only(top: FacteurSpacing.space2),
        child: Text(
          OnboardingStrings.swipeCalibratingHint,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Overlay plein cadre « on affine vos sources » en fin de tri (~1,4 s).
  Widget _buildRefiningOverlay(BuildContext context) {
    final colors = context.facteurColors;
    return Positioned.fill(
      child: ColoredBox(
        color: colors.backgroundPrimary.withOpacity(0.96),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: FacteurSpacing.space6),
            Text(
              OnboardingStrings.swipeRefiningTitle,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space6,
              ),
              child: Text(
                OnboardingStrings.swipeRefiningSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            if (_canUndoSwipe) ...[
              const SizedBox(height: FacteurSpacing.space6),
              TextButton.icon(
                onPressed: _undoLastSwipe,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text(OnboardingStrings.swipeUndoLabel),
              ),
            ],
          ],
        ),
      ),
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
          _cardWidth = constraints.maxWidth;
          final backCards = <Widget>[];
          Widget? topCard;
          for (var i = 0; i < queue.length; i++) {
            final card = queue[i];
            final depth = queue.length - 1 - i; // 0 = carte du dessus
            if (depth > 2)
              continue; // ne rend que le dessus + 2 cartes derrière
            final visual = SizedBox(
              width: constraints.maxWidth,
              child: _cardVisual(context, card),
            );
            if (depth == 0) {
              topCard = _buildTopCard(context, card, visual);
            } else {
              final colors = context.facteurColors;
              backCards.add(
                Transform.translate(
                  offset: Offset(0, depth * 12.0),
                  child: Transform.scale(
                    scale: 1 - depth * 0.04,
                    child: IgnorePointer(
                      // Voile type modal appliqué *à la carte du dessous*
                      // (épouse sa forme), pas à toute la zone : la carte
                      // suivante reste suggérée sans être lisible.
                      child: Stack(
                        children: [
                          visual,
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.scrim,
                                borderRadius: BorderRadius.circular(
                                  FacteurRadius.large,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          }
          return Stack(
            alignment: Alignment.center,
            children: [...backCards, if (topCard != null) topCard],
          );
        },
      ),
    );
  }

  /// Carte du dessus : suit le drag (translation + rotation), tampon
  /// directionnel, tap → fiche source.
  Widget _buildTopCard(
    BuildContext context,
    SpanningSource card,
    Widget visual,
  ) {
    final threshold = _refWidth * 0.28;
    final ratio =
        threshold == 0 ? 0.0 : (_dragOffset.dx / threshold).clamp(-1.0, 1.0);
    final angle = (_dragOffset.dx / _refWidth) * 0.18;

    return GestureDetector(
      onTap: () => _showSourceDetail(card),
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (d) => _onPanEnd(d, card),
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            alignment: Alignment.center,
            children: [
              visual,
              // Tampon unique ancré à droite : son libellé/couleur basculent
              // selon le sens du drag (vert « Ça m'intéresse » / neutre « Pas
              // pour moi »), opacité proportionnelle à la progression.
              Positioned(
                top: FacteurSpacing.space4,
                right: FacteurSpacing.space4,
                child: _swipeBadge(
                  context,
                  liked: ratio >= 0,
                  opacity: ratio.abs().clamp(0.0, 1.0),
                ),
              ),
            ],
          ),
        ),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      source.getThemeLabel(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
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
          // Bloc d'infos intrinsèques explicites (display-only) : format dérivé
          // du tier, tendance politique, fiabilité reformulée localement.
          Row(
            children: [
              _formatChip(context, source),
              if (source.getTypeIcon() != null) ...[
                const SizedBox(width: FacteurSpacing.space2),
                SourceTypeBadge(source: source),
              ],
            ],
          ),
          const SizedBox(height: FacteurSpacing.space3),
          _infoRow(
            context,
            icon: Icons.balance_outlined,
            label: OnboardingStrings.swipeBiasPrefix,
            value: source.getBiasLabel(),
            valueColor: source.getBiasColor(),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          _infoRow(
            context,
            icon: Icons.shield_outlined,
            label: OnboardingStrings.swipeReliabilityPrefix,
            value: _reliabilityLabel(source.reliabilityScore),
            valueColor: source.getReliabilityColor(),
          ),
        ],
      ),
    );
  }

  /// Chip « format » discret dérivé du tier de la source (display-only). Partage
  /// le chassis [IconLabelPill] avec le badge format ([SourceTypeBadge]).
  Widget _formatChip(BuildContext context, Source source) {
    final isDeep = source.sourceTier == 'deep';
    return IconLabelPill(
      icon: isDeep ? Icons.menu_book_outlined : Icons.bolt_outlined,
      label: isDeep
          ? OnboardingStrings.swipePoleDeep
          : OnboardingStrings.swipePoleMainstream,
    );
  }

  /// Ligne « icône + préfixe + valeur colorée » pour Tendance / Fiabilité.
  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: FacteurSpacing.space2),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Wording fiabilité local à l'écran de swipe (évite « Controversé »).
  String _reliabilityLabel(String reliabilityScore) {
    switch (reliabilityScore) {
      case 'high':
        return OnboardingStrings.swipeReliabilityHigh;
      case 'medium':
      case 'mixed':
        return OnboardingStrings.swipeReliabilityMedium;
      case 'low':
        return OnboardingStrings.swipeReliabilityLow;
      default:
        return OnboardingStrings.swipeReliabilityUnknown;
    }
  }

  /// Badge directionnel affiché pendant le drag (opacité ∝ progression).
  Widget _swipeBadge(
    BuildContext context, {
    required bool liked,
    required double opacity,
  }) {
    final colors = context.facteurColors;
    final color = liked ? colors.success : colors.textSecondary;
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: -0.12, // tilt léger constant (plus de miroir gauche/droite)
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          child: Text(
            liked
                ? OnboardingStrings.swipeLikeHint
                : OnboardingStrings.swipeSkipHint,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }

  /// Indice discret « Touchez pour explorer » placé *sous* la carte (jamais
  /// par-dessus le texte) : visible seulement sur la 1ère carte avant tout
  /// geste, il se replie en douceur dès la 1ère interaction.
  Widget _buildTapHint(BuildContext context, {required bool isFirstCard}) {
    final colors = context.facteurColors;
    final show = isFirstCard && !_hasInteracted;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: FacteurSpacing.space2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    OnboardingStrings.swipeTapHint,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
    );
  }

  /// Diamètre extérieur du bouton « revenir » secondaire (et de son placeholder
  /// symétrique) : garde (X)/(V) centrés que l'undo soit visible ou non.
  static const double _undoButtonSize = 44;

  Widget _buildActions(BuildContext context, SpanningSource top) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // « Revenir au média précédent » discret, à gauche de (X)/(V). Réserve
        // toujours sa place (placeholder) pour ne pas décaler le centre.
        SizedBox(
          width: _undoButtonSize,
          height: _undoButtonSize,
          child: _canUndoSwipe ? _undoButton(context) : null,
        ),
        const SizedBox(width: FacteurSpacing.space6),
        _actionButton(
          context,
          icon: Icons.close_rounded,
          color: colors.textSecondary,
          tooltip: OnboardingStrings.swipeSkipHint,
          onTap: () => _flingOut(top, liked: false),
        ),
        const SizedBox(width: FacteurSpacing.space8),
        _actionButton(
          context,
          icon: Icons.favorite_rounded,
          color: colors.success,
          tooltip: OnboardingStrings.swipeLikeHint,
          onTap: () => _flingOut(top, liked: true),
        ),
        const SizedBox(width: FacteurSpacing.space6),
        // Placeholder symétrique (équilibre l'undo de gauche).
        const SizedBox(width: _undoButtonSize, height: _undoButtonSize),
      ],
    );
  }

  /// Bouton circulaire secondaire « revenir au média précédent » : plus petit et
  /// plus discret que (X)/(V), icône `undo_rounded` en teinte tertiaire.
  Widget _undoButton(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: OnboardingStrings.swipeUndoLabel,
      child: Material(
        color: colors.surface,
        shape: CircleBorder(side: BorderSide(color: colors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _undoLastSwipe,
          child: Padding(
            padding: const EdgeInsets.all(FacteurSpacing.space3),
            child: Icon(
              Icons.undo_rounded,
              color: colors.textTertiary,
              size: 20,
            ),
          ),
        ),
      ),
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
