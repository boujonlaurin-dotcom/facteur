import 'dart:async';

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
/// La hauteur est **imposée par l'appelant** ([reservedHeight], calculée par
/// `triageReservedHeight`) et ne dépend pas du nombre d'articles restants :
/// c'est ce qui empêche la carte de grandir ou de rétrécir sous le doigt et
/// donc le feed de sauter.
class EssentielTriageStack extends ConsumerStatefulWidget {
  final List<EssentielArticle> articles;
  final EssentielTriageState triage;
  final double reservedHeight;

  /// Ouvre un article déjà gardé. La lecture vient **après** le tri : « Je
  /// garde » garde, il n'ouvre pas.
  final void Function(EssentielArticle article) onTapArticle;

  const EssentielTriageStack({
    super.key,
    required this.articles,
    required this.triage,
    required this.reservedHeight,
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
      unawaited(_maybeTriggerPreviewNudge());
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
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

    return SizedBox(
      height: widget.reservedHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressBar(
            total: triage.slate.length,
            decided: triage.decisions.length,
            accent: colors.sectionEssentiel,
          ),
          SizedBox(
            height: kTriageCardHeight,
            child: Stack(
              children: [
                if (next != null)
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 0.96,
                      // `RepaintBoundary` **sous** l'`Opacity` : avec un enfant
                      // déjà composité, `RenderOpacity` pousse un calque au
                      // compositeur au lieu de passer par `saveLayer` (un
                      // tampon hors écran réalloué à chaque peinture, donc à
                      // chaque frame de swipe).
                      child: Opacity(
                        opacity: 0.5,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: _TriageArticleCard(article: next),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: AutoGrowPulse(
                    playToken: _pulseToken,
                    child: TriageSwipeCard(
                      key: _cardKey,
                      height: kTriageCardHeight,
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
                        child: _TriageArticleCard(article: current),
                      ),
                    ),
                  ),
                ),
                // Le libellé du nudge flotte au bas de la carte : le rendre
                // dans la colonne coûterait une ligne de hauteur permanente
                // pour un message qui vit 2,4 s.
                Positioned(
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
          _ActionBar(
            onPass: () => _decideFromButton(TriageDecision.pass),
            onLater: () => _decideFromButton(TriageDecision.later),
            onKeep: () => _decideFromButton(TriageDecision.keep),
          ),
          // La liste des gardés se construit sous la pile. Volontairement en
          // lignes compactes et non en `_LeadTile`/`_MediumTile` : à pleine
          // taille, la hauteur à réserver dépasserait le viewport et le fit
          // rabattrait le slate à 1 article. Les tuiles pleines reviennent une
          // fois le tri terminé, quand la carte reprend sa liste habituelle.
          Expanded(
            child: ClipRect(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final id in triage.keptContentIds)
                    if (byId[id] != null)
                      _KeptRow(
                        article: byId[id]!,
                        onTap: () => widget.onTapArticle(byId[id]!),
                        onPreviewStart: _markPreviewDiscovered,
                      ),
                  // Le compteur ferme la liste : il se lit là où l'œil finit sa
                  // course, sous ce qu'on vient de garder, plutôt qu'en tête de
                  // carte où il concurrençait l'article à trier.
                  _TriageCounter(
                    total: triage.slate.length,
                    decided: triage.decisions.length,
                    kept: triage.keptCount,
                  ),
                ],
              ),
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
  final VoidCallback onTap;
  final VoidCallback onPreviewStart;

  const _KeptRow({
    required this.article,
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
                    Text(
                      article.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
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

/// Compteur de fin de liste : « N sur M triés · K gardés ».
class _TriageCounter extends StatelessWidget {
  final int total;
  final int decided;
  final int kept;

  const _TriageCounter({
    required this.total,
    required this.decided,
    required this.kept,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      height: kTriageCounterHeight,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          kept == 0
              ? '$decided sur $total triés'
              : '$decided sur $total triés · $kept gardé${kept > 1 ? 's' : ''}',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
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

/// Le contenu de la carte du dessus : bandeau image, source, titre, puis un
/// pied qui dit d'où vient l'article (couverture) et comment il est traité
/// (polarisation). Pas de chapô : à ce stade on choisit, on ne lit pas encore.
class _TriageArticleCard extends StatelessWidget {
  final EssentielArticle article;

  const _TriageArticleCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final showCoverage = article.coverageCount >= kCoverageChipMinSources;
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
          _TriageCardBanner(imageUrl: article.thumbnailUrl),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: 4,
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

/// Bandeau image en tête de carte. **Slot de hauteur fixe** :
/// [kTriageCardImageHeight] est réservé même sans image ou en cas d'erreur de
/// chargement — un aplat teinté prend alors la place. Sans cette garantie, la
/// carte changerait de taille d'un article à l'autre et le feed sauterait sous
/// le doigt, ce que tout le budget de fit s'emploie à empêcher.
class _TriageCardBanner extends StatelessWidget {
  final String? imageUrl;

  const _TriageCardBanner({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final url = imageUrl;
    // Aplat repris de `_buildImageOnTopBody` : même teinte de secours partout.
    final flat = Container(color: colors.primary.withValues(alpha: 0.06));
    // `FacteurThumbnail.failedUrls` est le cache d'URLs mortes de la session :
    // on le partage pour ne pas retenter un chargement déjà perdu.
    final isDead =
        url == null || url.isEmpty || FacteurThumbnail.failedUrls.contains(url);

    return SizedBox(
      key: const Key('triage-card-banner'),
      height: kTriageCardImageHeight,
      width: double.infinity,
      child: isDead
          ? flat
          : FacteurImage(
              imageUrl: url,
              fit: BoxFit.cover,
              height: kTriageCardImageHeight,
              memCacheWidth: (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
              placeholder: (_) => flat,
              errorWidget: (_) {
                FacteurThumbnail.markFailed(url);
                return flat;
              },
            ),
    );
  }
}
