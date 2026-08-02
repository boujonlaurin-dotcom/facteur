import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../providers/essentiel_triage_provider.dart';
import '../utils/section_fit.dart';
import 'triage_swipe_card.dart';

/// La pile à trier de la carte « Ton Essentiel » (Story 33.1).
///
/// Un article à la fois : swipe droite « Je lis », swipe gauche « Pas pour
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

  /// Ouvre un article déjà gardé. La lecture vient **après** le tri : « Je lis »
  /// garde, il n'ouvre pas.
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

  @override
  void initState() {
    super.initState();
    // Point de départ de la mesure de latence du premier article.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(essentielTriageProvider.notifier).markShown();
    });
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
    // « Plus tard » sort du même côté que « Je lis » (c'est un choix positif),
    // mais la décision enregistrée reste `later`, et la modalité `button`.
    state.animateOut(
      toRight: decision != TriageDecision.pass,
      onDone: () => _decide(decision, TriageVia.button),
    );
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
            kept: triage.keptCount,
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
                      child: Opacity(
                        opacity: 0.5,
                        child: IgnorePointer(
                          child: _TriageArticleCard(article: next),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: TriageSwipeCard(
                    key: _cardKey,
                    height: kTriageCardHeight,
                    onKeep: () => _decide(TriageDecision.keep, TriageVia.swipe),
                    onPass: () => _decide(TriageDecision.pass, TriageVia.swipe),
                    child: _TriageArticleCard(article: current),
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

/// Un article gardé, en ligne compacte. Tappable : la lecture commence ici,
/// après le tri.
class _KeptRow extends StatelessWidget {
  final EssentielArticle article;
  final VoidCallback onTap;

  const _KeptRow({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
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
    );
  }
}

/// Barre de progression par segments + compteur des gardés.
class _ProgressBar extends StatelessWidget {
  final int total;
  final int decided;
  final int kept;
  final Color accent;

  const _ProgressBar({
    required this.total,
    required this.decided,
    required this.kept,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      height: kTriageProgressHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: FacteurDurations.fast,
                    height: 4,
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
          const SizedBox(height: 8),
          Text(
            kept == 0
                ? '$decided sur $total triés'
                : '$decided sur $total triés · $kept gardé${kept > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Barre d'actions compacte : ✕ · signet · bouton plein « Je lis ».
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
              label: 'Je lis',
              child: Material(
                color: colors.primary,
                borderRadius: BorderRadius.circular(FacteurRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  onTap: onKeep,
                  child: const SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        'Je lis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
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

/// Le contenu de la carte du dessus : source, titre, chapô. Volontairement
/// sobre — l'article se lit après, pas ici.
class _TriageArticleCard extends StatelessWidget {
  final EssentielArticle article;

  const _TriageArticleCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
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
          const SizedBox(height: 10),
          Text(
            article.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.fraunces(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: colors.textPrimary,
            ),
          ),
          if (article.description != null &&
              article.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              article.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
