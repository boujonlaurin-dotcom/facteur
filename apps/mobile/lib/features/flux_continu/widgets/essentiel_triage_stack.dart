import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../detail/content_preview_mapper.dart';
import '../../digest/widgets/divergence_inline_badge.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../models/flux_continu_models.dart';
import '../providers/essentiel_triage_provider.dart';
import '../services/preview_nudge_scheduler.dart';
import '../utils/section_fit.dart';
import 'auto_grow_pulse.dart';
import 'coverage_chip.dart';
import 'triage_swipe_card.dart';

/// La pile à trier de la carte « Ton Essentiel » (Story 33.1).
///
/// Un article à la fois : swipe droite « Je garde », swipe gauche « Pas pour
/// moi », bouton signet « Plus tard ». La liste des gardés se construit sous la
/// pile, dans le feed, sans écran supplémentaire.
///
/// **La carte épouse son contenu** (itération PO 33.1) : au lieu de réserver la
/// hauteur de pic (grand vide sous la pile), la colonne est dimensionnée par son
/// contenu et enveloppée d'un [AnimatedSize] aligné en haut → la kept-list
/// grandit **vers le bas, sous la barre d'actions**. La zone d'interaction
/// (progression + carte + actions) reste figée en haut, donc le feed ne saute
/// pas sous le doigt.
///
/// La carte du dessus prend l'une de **deux hauteurs discrètes**
/// ([triageCardHeightFor]) : avec image ([kTriageCardHeight]) ou texte seul
/// ([kTriageCardTextOnlyHeight]). Jamais du fit-to-content — la barre d'actions
/// glisse d'un article à l'autre (`AnimatedSize`), elle ne saute pas.
class EssentielTriageStack extends ConsumerStatefulWidget {
  /// Pool des articles adressables par la pile (le slate figé du jour + les
  /// articles injectés par « Voir d'autres articles »), indexé par `contentId`.
  final List<EssentielArticle> articles;
  final EssentielTriageState triage;

  /// Ouvre un article déjà gardé. La lecture vient **après** le tri : « Je
  /// garde » garde, il n'ouvre pas.
  final void Function(EssentielArticle article) onTapArticle;

  const EssentielTriageStack({
    super.key,
    required this.articles,
    required this.triage,
    required this.onTapArticle,
  });

  @override
  ConsumerState<EssentielTriageStack> createState() =>
      _EssentielTriageStackState();
}

class _EssentielTriageStackState extends ConsumerState<EssentielTriageStack> {
  final GlobalKey<TriageSwipeCardState> _cardKey = GlobalKey();

  /// Jeton de rejeu du pulse `AutoGrowPulse` — change pour rejouer.
  Object? _pulseToken;

  /// Le mini libellé « Appuie longuement pour un aperçu. » est-il visible ?
  bool _showPreviewHint = false;

  /// Une seule tentative de nudge par montage : sans ce verrou, un rebuild
  /// pendant que le `canTriggerNow()` asynchrone est en vol relancerait la
  /// séquence et le pulse se rejouerait en boucle sur la même carte.
  bool _nudgeAttempted = false;

  Timer? _hintTimer;

  /// Avancée du geste en cours (0..1), remontée par [TriageSwipeCard]. Pilote la
  /// **promotion continue** de la carte du dessous : elle atteint son échelle et
  /// son opacité pleines *pendant* la sortie de la carte du dessus, au lieu de
  /// claquer de 0.96/0.5 à 1.0/1.0 quand elle devient carte du dessus.
  ///
  /// Un `ValueNotifier` plutôt qu'un `setState` : seule la carte du dessous doit
  /// se rebuilder à chaque frame de geste, pas la pile entière.
  final ValueNotifier<double> _promotion = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    // Point de départ de la mesure de latence du premier article.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(essentielTriageProvider.notifier).markShown();
    });
    // Cold-boot en plein tri : la pile peut se monter directement sur la carte
    // du nudge.
    unawaited(_maybeTriggerPreviewNudge());
  }

  @override
  void didUpdateWidget(EssentielTriageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.triage.index != widget.triage.index) {
      // La carte promue devient carte du dessus : la promotion repart de zéro
      // pour la nouvelle carte du dessous, qui elle n'a pas encore été touchée.
      _promotion.value = 0;
      unawaited(_maybeTriggerPreviewNudge());
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _promotion.dispose();
    super.dispose();
  }

  void _decide(TriageDecision decision, TriageVia via) {
    ref.read(essentielTriageProvider.notifier).decide(decision, via: via);
  }

  /// Depuis la barre d'actions : rejoue la sortie physique du swipe pour que
  /// les deux modalités rendent le même mouvement.
  void _decideFromButton(TriageDecision decision) {
    final state = _cardKey.currentState;
    if (state == null) {
      _decide(decision, TriageVia.button);
      return;
    }
    // « Plus tard » sort du même côté que « Je garde » (c'est un choix
    // positif), mais la décision enregistrée reste `later`, et la modalité
    // `button`.
    state.animateOut(
      toRight: decision != TriageDecision.pass,
      onDone: () => _decide(decision, TriageVia.button),
    );
  }

  /// Joue une fois le nudge « aperçu au long-press » sur la 2ᵉ carte de la pile
  /// (la 1ʳᵉ appartient à la découverte du swipe). Silencieux si le scheduler
  /// refuse : déjà montré aujourd'hui, ou aperçu déjà découvert.
  Future<void> _maybeTriggerPreviewNudge() async {
    if (_nudgeAttempted) return;
    if (widget.triage.index != kTriagePreviewNudgeCardIndex) return;
    _nudgeAttempted = true;

    final scheduler = ref.read(triagePreviewNudgeSchedulerProvider);
    if (!await scheduler.canTriggerNow()) return;
    if (!mounted) return;
    await scheduler.recordTriggered();
    if (!mounted) return;

    setState(() {
      _pulseToken = Object();
      _showPreviewHint = true;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(kTriagePreviewHintDuration, () {
      if (mounted) setState(() => _showPreviewHint = false);
    });
  }

  /// Un vrai long-press : l'aperçu est découvert. Le nudge s'éteint à vie et le
  /// libellé en cours disparaît immédiatement — il a fait son travail.
  void _markPreviewDiscovered() {
    unawaited(ref.read(triagePreviewNudgeSchedulerProvider).markDiscovered());
    _hintTimer?.cancel();
    if (_showPreviewHint) setState(() => _showPreviewHint = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final triage = widget.triage;
    final currentId = triage.currentContentId;
    if (currentId == null) return const SizedBox.shrink();

    final byId = {for (final a in widget.articles) a.contentId: a};
    final current = byId[currentId];
    if (current == null) return const SizedBox.shrink();

    // Article suivant, rendu en dessous pour donner l'épaisseur de pile.
    final nextIndex = triage.index + 1;
    final next = nextIndex < triage.slate.length
        ? byId[triage.slate[nextIndex]]
        : null;

    // Un seul point de lecture de l'état des sources : les cartes et les lignes
    // gardées restent des `StatelessWidget` et reçoivent un `InterestState`.
    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    InterestState? sourceStateOf(EssentielArticle a) {
      final id = a.sourceId;
      if (sourcesState == null || id == null) {
        // Repli sur le drapeau déjà porté par le modèle : au cold-boot, une
        // source suivie doit montrer sa coche sans attendre le réseau.
        return a.isFollowedSource ? InterestState.followed : null;
      }
      return sourcesState.stateOf(id);
    }

    // Hauteur du slot : deux valeurs discrètes (avec / sans image), décidée à la
    // composition et non pendant le geste — une carte ne se replie jamais sous
    // le doigt.
    final cardHeight = triageCardHeightFor(current.thumbnailUrl);

    // La carte épouse son contenu : croissance animée **vers le bas** (alignée
    // en haut) quand la kept-list s'allonge, zone d'action figée au-dessus.
    return AnimatedSize(
      duration: FacteurDurations.medium,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressBar(
            total: triage.slate.length,
            decided: triage.decisions.length,
            accent: colors.sectionEssentiel,
          ),
          // La bascule carte-image ↔ carte-texte glisse au lieu de sauter : la
          // barre d'actions se déplace de façon lisible sous le pouce.
          AnimatedSize(
            duration: FacteurDurations.medium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                // Clés fixes sur les trois slots : l'appariement d'un build à
                // l'autre se fait alors **par clé**, jamais par position. Sans
                // elles, le nombre d'enfants changeait (3 → 2 sur la dernière
                // carte) et un élément glissait d'un slot à l'autre le temps
                // d'une frame — d'où le tampon apparemment déjà posé sur la
                // carte fraîche. Le slot arrière est toujours rendu, vide s'il
                // n'y a plus d'article dessous.
                children: [
                  Positioned.fill(
                    key: const ValueKey('triage-back'),
                    child: next == null
                        ? const SizedBox.shrink()
                        : ValueListenableBuilder<double>(
                            valueListenable: _promotion,
                            builder: (context, p, child) => Transform.scale(
                              scale: lerpDouble(0.96, 1.0, p)!,
                              // Ancrée en haut, jamais centrée : centrée, elle
                              // était rognée sur les quatre côtés pendant toute
                              // la sortie de la carte du dessus (« carte
                              // légèrement déplacée »). `topCenter` aligne aussi
                              // correctement deux cartes de hauteurs
                              // différentes (image / texte).
                              alignment: Alignment.topCenter,
                              // `RepaintBoundary` **sous** l'`Opacity` : avec un
                              // enfant déjà composité, `RenderOpacity` pousse un
                              // calque au compositeur au lieu de passer par
                              // `saveLayer` (un tampon hors écran réalloué à
                              // chaque peinture, donc à chaque frame de swipe).
                              child: Opacity(
                                opacity: lerpDouble(0.5, 1.0, p)!,
                                child: child,
                              ),
                            ),
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: _TriageArticleCard(
                                  article: next,
                                  sourceState: sourceStateOf(next),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Positioned.fill(
                    key: const ValueKey('triage-top'),
                    child: AutoGrowPulse(
                      playToken: _pulseToken,
                      child: TriageSwipeCard(
                        key: _cardKey,
                        // Jeton de « carte fraîche » : quand l'article du dessus
                        // change, le State réutilisé (GlobalKey) repart d'un
                        // geste propre au lieu de fuir le drag/anim du précédent.
                        articleId: currentId,
                        height: cardHeight,
                        onGestureProgress: (p) => _promotion.value = p,
                        onKeep: () =>
                            _decide(TriageDecision.keep, TriageVia.swipe),
                        onPass: () =>
                            _decide(TriageDecision.pass, TriageVia.swipe),
                        // L'aperçu est monté **dans** la carte qui swipe, pas
                        // autour : l'arène de gestes départage alors un drag
                        // horizontal (qui gagne dès le slop franchi) d'un appui
                        // maintenu, au lieu de voir le parent capter les deux.
                        child: ArticlePreviewGesture(
                          contentBuilder: () => current.toPreviewContent(),
                          onLongPressStart: _markPreviewDiscovered,
                          child: _TriageArticleCard(
                            article: current,
                            sourceState: sourceStateOf(current),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Le libellé du nudge flotte au bas de la carte : le rendre
                  // dans la colonne coûterait une ligne de hauteur permanente
                  // pour un message qui vit 2,4 s.
                  Positioned(
                    key: const ValueKey('triage-hint'),
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _showPreviewHint ? 1 : 0,
                        duration: FacteurDurations.medium,
                        child: const Center(child: _PreviewHint()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ActionBar(
            onPass: () => _decideFromButton(TriageDecision.pass),
            onLater: () => _decideFromButton(TriageDecision.later),
            onKeep: () => _decideFromButton(TriageDecision.keep),
          ),
          // La liste des gardés se construit sous la pile. Volontairement en
          // lignes compactes et non en `_LeadTile`/`_MediumTile` (les tuiles
          // pleines reviennent une fois le tri terminé, quand la carte reprend
          // sa liste habituelle).
          //
          // Dimensionnée par son contenu (`shrinkWrap`), mais **bornée** : si la
          // kept-list dépasse la moitié du viewport (slate étendu tout gardé sur
          // petit écran), elle défile en interne au lieu de pousser la carte
          // hors de l'écran. En deçà, rien à faire défiler → le geste passe au
          // feed.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              children: [
                // Plus de compteur « N sur M triés » en pied de liste (décision
                // PO) : la barre de progression segmentée porte déjà
                // l'avancement, et les lignes gardées sont juste au-dessus.
                for (final id in triage.keptContentIds)
                  if (byId[id] != null)
                    _KeptRow(
                      key: ValueKey('triage-kept-row-$id'),
                      article: byId[id]!,
                      sourceState: sourceStateOf(byId[id]!),
                      onTap: () => widget.onTapArticle(byId[id]!),
                      onPreviewStart: _markPreviewDiscovered,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini libellé du nudge : dit le geste, rien d'autre. Fond opaque pour rester
/// lisible par-dessus le pied de carte qu'il recouvre le temps de son passage.
class _PreviewHint extends StatelessWidget {
  const _PreviewHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        'Appuie longuement pour un aperçu.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// Un article gardé, en ligne compacte. Tappable : la lecture commence ici,
/// après le tri. Le long-press ouvre le même aperçu que les autres cartes.
class _KeptRow extends StatelessWidget {
  final EssentielArticle article;

  /// État d'intérêt de la source, pour la coche/étoile posée à droite du nom.
  /// `null` ⇒ aucun signal (source neutre, masquée, ou état pas encore chargé).
  final InterestState? sourceState;

  final VoidCallback onTap;
  final VoidCallback onPreviewStart;

  const _KeptRow({
    super.key,
    required this.article,
    required this.sourceState,
    required this.onTap,
    required this.onPreviewStart,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return ArticlePreviewGesture(
      contentBuilder: () => article.toPreviewContent(),
      onLongPressStart: onPreviewStart,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kTriageKeptSlotHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                PhosphorIcons.check(),
                size: 14,
                color: colors.sectionEssentiel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            article.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        _SourceStateMark(state: sourceState),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre de progression par segments. Le segment **en cours de décision** est
/// épaissi (4 → 7 px) : le grossissement porte sur l'épaisseur, jamais sur la
/// longueur — les `Expanded` gardent des segments de largeur égale, sans quoi
/// la barre respirerait horizontalement à chaque geste.
class _ProgressBar extends StatelessWidget {
  final int total;
  final int decided;
  final Color accent;

  const _ProgressBar({
    required this.total,
    required this.decided,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      height: kTriageProgressHeight,
      child: Align(
        alignment: Alignment.topCenter,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: FacteurDurations.fast,
                  height: i == decided ? 7 : 4,
                  decoration: BoxDecoration(
                    color: i < decided ? accent : colors.border,
                    borderRadius: BorderRadius.circular(FacteurRadius.full),
                  ),
                ),
              ),
              if (i < total - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// Coche « suivie » / étoile « favorite » posée à droite du nom de source.
///
/// Réutilise l'idiome visuel canonique des intérêts ([InterestStateVisuals]) au
/// lieu d'en réinventer un : même icône et même accent que les pastilles de
/// « Mes intérêts ». Ne rend **que** `followed` et `favorite` — un état neutre
/// ou masqué n'a rien à signaler sur une carte à trier.
class _SourceStateMark extends StatelessWidget {
  final InterestState? state;

  const _SourceStateMark({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s != InterestState.followed && s != InterestState.favorite) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        label: s!.label,
        child: Icon(s.iconData, size: 12, color: s.accent(colors)),
      ),
    );
  }
}

/// Barre d'actions compacte : ✕ · signet · bouton plein « Je garde ».
///
/// Doublon volontaire du geste : le tri doit rester possible **sans swipe**
/// (accessibilité, et utilisateurs qui ne découvrent pas le geste).
class _ActionBar extends StatelessWidget {
  final VoidCallback onPass;
  final VoidCallback onLater;
  final VoidCallback onKeep;

  const _ActionBar({
    required this.onPass,
    required this.onLater,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      height: kTriageActionBarHeight,
      child: Row(
        children: [
          _RoundButton(
            icon: PhosphorIcons.x(),
            semanticLabel: 'Pas pour moi',
            color: colors.textSecondary,
            onTap: onPass,
          ),
          const SizedBox(width: 10),
          _RoundButton(
            icon: PhosphorIcons.bookmarkSimple(),
            semanticLabel: 'Plus tard',
            color: colors.textSecondary,
            onTap: onLater,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Je garde',
              child: Material(
                color: colors.primary,
                borderRadius: BorderRadius.circular(FacteurRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  onTap: onKeep,
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.checkCircle(
                              PhosphorIconsStyle.fill,
                            ),
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Je garde',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: colors.backgroundSecondary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// Le contenu de la carte du dessus : bandeau image (quand il y en a une),
/// source, titre, puis un pied qui dit d'où vient l'article (couverture) et
/// comment il est traité (polarisation). Pas de chapô : à ce stade on choisit,
/// on ne lit pas encore.
class _TriageArticleCard extends StatelessWidget {
  final EssentielArticle article;

  /// État d'intérêt de la source (coche/étoile à droite du nom). `null` ⇒ rien
  /// à signaler.
  final InterestState? sourceState;

  const _TriageArticleCard({required this.article, required this.sourceState});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final showCoverage = article.coverageCount >= kCoverageChipMinSources;
    // Décidé à la composition, jamais pendant le geste : la carte ne se replie
    // pas sous le doigt si l'image échoue en cours de route (l'échec est mis en
    // cache et prendra effet au rendu suivant).
    final hasImage = triageCardHasImage(article.thumbnailUrl);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pas de bandeau du tout sans image (décision PO) : plus d'aplat
          // gris imposé. La carte texte est simplement plus courte
          // ([kTriageCardTextOnlyHeight]) et son titre respire sur 6 lignes.
          if (hasImage) _TriageCardBanner(imageUrl: article.thumbnailUrl),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          article.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      _SourceStateMark(state: sourceState),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: hasImage ? 4 : 6,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  // Mêmes gardes et même ordre que le pied des cartes du flux
                  // (`flux_continu_article_card`) : la polarisation d'abord,
                  // la couverture ensuite.
                  if (article.divergenceLevel != null || showCoverage) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (article.divergenceLevel != null)
                          DivergenceInlineBadge(
                            divergenceLevel: article.divergenceLevel,
                            iconOnly: true,
                          ),
                        if (article.divergenceLevel != null && showCoverage)
                          const SizedBox(width: 8),
                        if (showCoverage)
                          CoverageChip(
                            key: const Key('triage-coverage-chip'),
                            sourceCount: article.coverageCount,
                            sources: article.perspectiveSources,
                            colors: colors,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'article porte-t-il une image exploitable ? `false` ⇒ carte texte, plus
/// courte, **sans bandeau du tout**.
///
/// `FacteurThumbnail.failedUrls` est le cache d'URLs mortes de la session : une
/// URL déjà perdue vaut absence d'image, sans nouvelle tentative.
///
/// Vit ici et non dans `section_fit.dart`, qui est délibérément de
/// l'arithmétique pure sans binding Flutter — seule la constante y est exposée.
bool triageCardHasImage(String? url) =>
    url != null && url.isNotEmpty && !FacteurThumbnail.failedUrls.contains(url);

/// Laquelle des **deux hauteurs discrètes** ce slot de carte prend.
double triageCardHeightFor(String? url) =>
    triageCardHasImage(url) ? kTriageCardHeight : kTriageCardTextOnlyHeight;

/// Bandeau image en tête de carte, rendu **uniquement quand il y a une image**
/// ([triageCardHasImage]) : plus d'aplat de secours imposé (décision PO), une
/// carte sans image est une carte texte plus courte.
///
/// Le slot garde une hauteur fixe [kTriageCardImageHeight] : une image qui
/// échoue *en cours de chargement* laisse un vide transparent et se replie au
/// **rendu suivant** (via `FacteurThumbnail.markFailed`), jamais au milieu du
/// geste.
class _TriageCardBanner extends StatelessWidget {
  final String? imageUrl;

  const _TriageCardBanner({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return const SizedBox.shrink();

    return SizedBox(
      key: const Key('triage-card-banner'),
      height: kTriageCardImageHeight,
      width: double.infinity,
      child: FacteurImage(
        imageUrl: url,
        fit: BoxFit.cover,
        height: kTriageCardImageHeight,
        memCacheWidth: (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round(),
        placeholder: (_) => const SizedBox.shrink(),
        errorWidget: (_) {
          FacteurThumbnail.markFailed(url);
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
