import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/theme.dart';
import '../../feed/widgets/feed_carousel.dart';
import '../../feed/widgets/feedback_inline.dart';
import '../models/flux_continu_models.dart';
import 'alerts_section_card.dart';
import 'article_impression_tracker.dart';
import 'essentiel_hi_fi_card.dart';
import 'etoffer_theme_footer.dart';
import 'flux_continu_article_card.dart';
import 'section_banner.dart';
import 'veille_group_header.dart';

/// Identifies which chip the user picked on a [FeedbackInline] banner.
enum FluxFeedbackChip { source, topic, alreadySeen }

/// Composes one section of the Flux Continu V1.8: banner cliquable → cards.
/// Le banner porte la navigation « tout lire » (Story 10.1) — le CTA de bas
/// de section a disparu.
///
/// For [DigestTopicSection], the section renders one card per topic, the
/// lead article being picked by [pickTopicLead]. For [FeedThemeSection],
/// one card per feed item.
class SectionBlock extends StatelessWidget {
  final FluxSection section;
  final void Function(Object article) onTapArticle;
  final ValueChanged<String>? onDismissArticle;

  /// Opens the dedicated full-page view for the section. Wired by the
  /// flux_continu screen ; rendu comme tap sur le banner (+ chevron / « +X »).
  final VoidCallback? onSeeAll;

  /// IDs of articles currently in the inline-feedback pending state. When
  /// non-empty, the matching cards are swapped for a [FeedbackInline] at the
  /// same position.
  final Set<String> pendingFeedbackIds;
  final void Function(String contentId, FluxFeedbackChip chip)?
  onSelectFeedbackChip;
  final ValueChanged<String>? onResolveFeedback;
  final ValueChanged<String>? onUndoFeedback;

  /// When true, the section's first article plays the one-shot swipe-left
  /// hint animation. Only the first section on screen should set this.
  final bool enableSwipeHintOnFirstCard;
  final VoidCallback? onSwipeHintComplete;
  final GlobalKey? firstSwipeableCardAnchor;
  final VoidCallback? onSwipeConversion;
  final VoidCallback? onLongPressConversion;

  /// Optional — when set, the banner renders a small "favorite" star at the
  /// end of its title. Only wired for user-favorite sections (theme/topic);
  /// null on system sections (`essentiel` / `bonnes`).
  final VoidCallback? onTapFavorite;

  /// Story 23.4 — settings affordance (tune button + empty-state CTA). Only
  /// wired for the veille section → opens the veille config in edit mode.
  final VoidCallback? onTapSettings;

  /// CTA « Ajouter des sources » de l'empty-state d'une section thème favorite
  /// vide. Ouvre « Composer ma Tournée ». Distinct de [onTapSettings]
  /// (spécifique veille). Câblé uniquement pour les sections thème.
  final VoidCallback? onAddSources;

  /// Story 22.3 — tap sur le badge « Choisie pour vous » d'une section
  /// suggérée → ouvre la sheet « Pourquoi cette section ? ». Câblé uniquement
  /// pour les sections `origin == suggested` (cf. flux_continu_screen).
  final VoidCallback? onTapSuggestionInfo;

  /// Story 22.6 — CTA direct « Ajouter à mon Essentiel » en pied d'une section
  /// suggérée : promeut la section en favorite sans passer par la sheet. Câblé
  /// uniquement pour les sections `origin == suggested` (non-null ⇒ bouton
  /// rendu). Le future résout après la promotion (le bouton gère spinner +
  /// anti double-tap localement).
  final Future<void> Function()? onPromoteSuggestion;

  /// Rend le libellé d'attente (« Ta tournée se prépare… ») en tête des cartes
  /// squelette de cette section. Réservé à la **première** coquille non résolue
  /// de la page (câblé par `flux_continu_screen`) : un seul indicateur pour
  /// toute la Tournée, comme le veut le minimalisme du design system.
  final bool showPreparingLabel;

  /// Jour Tournée courant. **Non-null ⇒ les cartes comptent une impression**
  /// (dénominateur du CTR). Laissé `null` sur les chemins de **lecture seule** —
  /// les éditions passées de `/edition`, qui sont de la consultation d'archive
  /// et pas une Tournée servie par l'algo : les y compter fausserait le taux.
  final String? impressionDayKey;

  /// Rang de la section dans la page (0 = héros). Ignoré sans
  /// [impressionDayKey].
  final int sectionIndex;

  /// Nombre de cartes rendues **avant** cette section, pour que chaque carte
  /// porte son rang absolu dans la page.
  final int globalPositionOffset;

  /// Somme des meilleurs scores du bloc, quand l'ordonnancement par score est
  /// branché. `null` = ordre non piloté par le score.
  final double? blockScore;

  /// Jour « serein » (mode Bonnes Nouvelles) — un CTR de jour serein ne se
  /// compare pas à un CTR de jour normal.
  final bool isSerene;

  const SectionBlock({
    super.key,
    required this.section,
    required this.onTapArticle,
    this.onDismissArticle,
    this.pendingFeedbackIds = const <String>{},
    this.onSelectFeedbackChip,
    this.onResolveFeedback,
    this.onUndoFeedback,
    this.enableSwipeHintOnFirstCard = false,
    this.onSwipeHintComplete,
    this.firstSwipeableCardAnchor,
    this.onSwipeConversion,
    this.onLongPressConversion,
    this.onTapFavorite,
    this.onTapSettings,
    this.onAddSources,
    this.onSeeAll,
    this.onTapSuggestionInfo,
    this.onPromoteSuggestion,
    this.showPreparingLabel = false,
    this.impressionDayKey,
    this.sectionIndex = 0,
    this.globalPositionOffset = 0,
    this.blockScore,
    this.isSerene = false,
  });

  /// Enveloppe une carte d'article dans son compteur d'impression. Passe-plat
  /// quand [impressionDayKey] est `null` (lecture seule) : zéro widget de plus
  /// dans l'arbre sur ces chemins.
  Widget _tracked({
    required int position,
    required String contentId,
    required Widget child,
    double? scoreTotal,
    String? theme,
    String? sourceId,
  }) {
    final dayKey = impressionDayKey;
    if (dayKey == null) return child;
    final section = this.section;
    return ArticleImpressionTracker(
      dayKey: dayKey,
      info: ArticleImpressionInfo(
        contentId: contentId,
        sectionKey: sectionKey(section),
        sectionFamily: sectionFamily(section),
        surface: 'tournee',
        sectionIndex: sectionIndex,
        positionInSection: position,
        globalPosition: globalPositionOffset + position,
        scoreTotal: scoreTotal,
        blockScore: blockScore,
        theme: theme,
        sourceId: sourceId,
        isSerene: isSerene,
        underfilled: section is FeedThemeSection && section.underfilled,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    // EssentielSection is a fully self-contained hi-fi card — no banner,
    // no "Plus de…" overflow.
    if (section is EssentielSection) {
      return Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bouton « personnaliser » retiré (décision PO) : point d'entrée
            // unique = l'inline « GÉRER » de MyInterestsIntro. Le déclencheur
            // « rewind » de l'en-tête de la carte subsiste, lui.
            EssentielHiFiCard(
              articles: section.articles,
              carousel: section.carousel,
              onTapArticle: (a) => onTapArticle(a),
              impressionDayKey: impressionDayKey,
              sectionIndex: sectionIndex,
              globalPositionOffset: globalPositionOffset,
              isSerene: isSerene,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    // Le rappel d'alertes porte son propre titre et ses propres lignes : pas de
    // banner ni de cartes d'article, donc pas de shell de section non plus.
    if (section is AlertsSection) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlertsSectionCard(section: section),
          const SizedBox(height: 16),
        ],
      );
    }
    // Carte carrousel du jour (Story 32.1) — scroller horizontal auto-porté
    // (PageView + dots), sans banner ni shell de section, comme AlertsSection.
    // `onTapArticle` du SectionBlock accepte un Object ; on lui passe le Content.
    if (section is CarouselSection) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FeedCarousel(
            data: section.data,
            onArticleTap: (content) => onTapArticle(content),
          ),
          const SizedBox(height: 16),
        ],
      );
    }
    final cards = _buildCards();
    // Section source sans article récent (≤72h) mais avec des cartes plus
    // anciennes (repli 30 j backend) → on signale « Pas d'article récent. » dans
    // la blurb du banner. L'empty-state (aucun article même vieux) reste géré
    // par _buildCards et n'affiche pas cette note.
    final effectiveBlurb =
        section is FeedThemeSection &&
            section.kind == SectionKind.source &&
            section.noRecentSource &&
            section.items.isNotEmpty
        ? 'Pas d\'article récent.'
        : section.blurb;
    // Section suggérée par le facteur → balise « Choisie pour vous » + puce
    // « Ajouter à l'Essentiel ». Calculé une fois (partagé par les params
    // `suggested` et `onPromote` du banner).
    final isSuggested = section is FeedThemeSection && section.isSuggested;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBanner(
          title: section.label,
          accent: section.accent,
          blurb: effectiveBlurb,
          illustrationAsset: section.illustrationAsset,
          // PR « Sources dans la Tournée » — hero logo source à la place de
          // l'illustration thème.
          logoUrl:
              section is FeedThemeSection && section.kind == SectionKind.source
              ? section.sourceLogoUrl
              : null,
          onTapFavorite: onTapFavorite,
          onTapSettings: onTapSettings,
          onTap: onSeeAll,
          // Story 22.3 — badge « Choisie pour vous » sur les sections suggérées.
          suggested: isSuggested,
          onTapInfo: onTapSuggestionInfo,
          // Story 22.6 (redesign) — puce d'action « Ajouter à l'Essentiel » sur
          // la ligne de la balise (plus de CTA sous les cartes → snap/fit
          // intact). Le badge/info-tap reste la voie « Pourquoi cette
          // section ? ». Câblage instrumentation inchangé (origin: 'card').
          onPromote: isSuggested ? onPromoteSuggestion : null,
        ),
        ...cards,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _feedbackInlineFor(String contentId) {
    return Padding(
      key: ValueKey('flux_feedback_$contentId'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: FeedbackInline(
        onSelectSource: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.source),
        onSelectTopic: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.topic),
        onSelectAlreadySeen: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.alreadySeen),
        onUndo: () => onUndoFeedback?.call(contentId),
        onClose: () => onResolveFeedback?.call(contentId),
      ),
    );
  }

  /// Mode Lisible — IDs des cartes autorisées à afficher leur image pleine
  /// largeur : les **2 premières** cartes porteuses d'image d'une section. Au
  /// delà, l'image n'est pas affichée (cf. [FluxContinuArticleCard.allowImageOnTop])
  /// pour éviter qu'une section ne devienne trop haute. Décision PO : « si 2
  /// images dispo, ne pas afficher la 3ᵉ ». Sans effet hors mode Lisible.
  static const int _maxImagesPerSection = 2;

  Set<String> _imageAllowedIds(List<({String id, String? thumb})> items) {
    final allowed = <String>{};
    var count = 0;
    for (final item in items) {
      if (item.thumb != null && item.thumb!.isNotEmpty) {
        if (count < _maxImagesPerSection) allowed.add(item.id);
        count++;
      }
    }
    return allowed;
  }

  List<Widget> _buildCards() {
    switch (section) {
      case EssentielSection():
        // build() short-circuits to EssentielHiFiCard before reaching
        // _buildCards, so this branch is unreachable in practice.
        return const [];
      case AlertsSection():
        // Idem : build() court-circuite sur AlertsSectionCard.
        return const [];
      case CarouselSection():
        // Idem : build() court-circuite sur FeedCarousel avant _buildCards.
        return const [];
      case DigestTopicSection(:final topics, :final coreVisibleCount):
        final visible = topics.take(coreVisibleCount).toList();
        // `pickTopicLead` scanne les articles du topic ; on le résout une fois
        // par topic ici plutôt qu'à chaque référence (≈6×/carte/frame de scroll).
        final leads = [for (final topic in visible) pickTopicLead(topic)];
        final firstSwipeableIndex = leads.indexWhere(
          (lead) => !pendingFeedbackIds.contains(lead.contentId),
        );
        final imageAllowed = _imageAllowedIds([
          for (final lead in leads)
            (id: lead.contentId, thumb: lead.thumbnailUrl),
        ]);
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds.contains(leads[i].contentId))
              _feedbackInlineFor(leads[i].contentId)
            else
              _tracked(
                position: i,
                contentId: leads[i].contentId,
                scoreTotal: leads[i].recommendationReason?.scoreTotal,
                theme: visible[i].theme,
                sourceId: leads[i].source?.id,
                child: FluxContinuArticleCard(
                  article: leads[i],
                  allowImageOnTop: imageAllowed.contains(leads[i].contentId),
                  sourceCount: visible[i].coverageCount,
                  perspectiveSources: visible[i].effectiveCoverageSources,
                  divergenceLevel: visible[i].divergenceLevel,
                  onTap: () => onTapArticle(leads[i]),
                  onSwipeDismiss: onDismissArticle == null
                      ? null
                      : () => onDismissArticle!(leads[i].contentId),
                  enableSwipeHint:
                      enableSwipeHintOnFirstCard && i == firstSwipeableIndex,
                  onSwipeHintComplete:
                      enableSwipeHintOnFirstCard && i == firstSwipeableIndex
                      ? onSwipeHintComplete
                      : null,
                  nudgeAnchor: i == firstSwipeableIndex
                      ? firstSwipeableCardAnchor
                      : null,
                  onSwipeConversion: onSwipeConversion,
                  onLongPressConversion: onLongPressConversion,
                ),
              ),
          // Actus du jour — pas de footer d'ajout de sources → on re-signale
          // l'ouverture de la section par un « Tout lire › » discret cliquable.
          if (onSeeAll != null) _seeAllFooter(),
        ];
      case FeedThemeSection(
        :final items,
        :final coreVisibleCount,
        :final underfilled,
        :final themeSlug,
        :final label,
        :final isPlaceholder,
        :final followedSourceCount,
      ):
        // Issue #1 — « squelette stable » : une coquille seed-ée AVANT le
        // fan-out réserve sa hauteur finale (N cartes squelette) pour que
        // l'upsert remplace le contenu **sur place**, sans décaler les sections
        // suivantes (Actus/Bonnes) vers le bas. Court-circuite les empty-states
        // ci-dessous, réservés aux sections **résolues** vides
        // (`isPlaceholder == false && items.isEmpty`).
        if (isPlaceholder) {
          return sectionSkeletonCards(
            coreVisibleCount,
            // Le libellé vit **dans** la 1ʳᵉ carte squelette : il ne consomme
            // aucune hauteur propre, donc l'invariant de géométrie stable
            // (remplacement sur place, zéro décalage) tient toujours.
            firstCardLabel: showPreparingLabel ? kSectionPreparingLabel : null,
          );
        }
        // Story 23.4 — la section veille reste visible même vide : on rend un
        // placeholder + CTA réglages au lieu de cartes.
        if (items.isEmpty && section.kind == SectionKind.veille) {
          return [_VeilleEmptyState(onTapSettings: onTapSettings)];
        }
        // PR « Sources dans la Tournée » — section source **toujours visible**
        // même sans article frais : placeholder + CTA vers la curation
        // complète de la source (qui contient souvent des articles plus
        // anciens). Décision PO : ne jamais masquer une source favorite.
        if (items.isEmpty && section.kind == SectionKind.source) {
          return [
            _FavoriteEmptyState(
              message: 'Rien de neuf récemment chez ${section.label}.',
              ctaIcon: Icons.library_books_outlined,
              ctaLabel: 'Voir toute la curation',
              onCta: onSeeAll,
            ),
          ];
        }
        // Tournée bugs E2E — une section thème **favorite** vide reste visible
        // (miroir source/veille : ne jamais masquer un favori) : placeholder +
        // CTA « Ajouter des sources » qui ouvre « Composer ma Tournée ». Un
        // thème à 1 article rend sa carte normalement.
        if (items.isEmpty && section.kind == SectionKind.theme) {
          // Thème favori vide → footer « Étoffer » **déplié** : « rien de neuf »
          // + sources de qualité à suivre + recherche. Pour un sujet custom
          // (pas de slug macro-thème), on garde le CTA générique historique.
          return [
            _themeFooter(
              themeSlug: themeSlug,
              label: label,
              initiallyExpanded: true,
              headline: 'Rien de neuf récemment sur $label.',
              fallbackCtaLabel: 'Ajouter des sources',
            ),
          ];
        }
        final visible = items.take(coreVisibleCount).toList();
        // Section veille — en-têtes « Tes sources » / « Couverture élargie »
        // dérivés au rendu sur les transitions de `veilleGroup`.
        if (section.kind == SectionKind.veille) {
          final rows = buildVeilleFeedRows(visible);
          final firstSwipeableIndex = visible.indexWhere(
            (content) => !pendingFeedbackIds.contains(content.id),
          );
          return [
            for (final row in rows)
              switch (row) {
                VeilleHeaderRow(:final label) => VeilleGroupHeader(
                  label: label,
                ),
                VeilleArticleRow(:final content, :final index) =>
                  pendingFeedbackIds.contains(content.id)
                      ? _feedbackInlineFor(content.id)
                      : _tracked(
                          position: index,
                          contentId: content.id,
                          scoreTotal: content.recommendationReason?.scoreTotal,
                          theme: content.source.theme,
                          sourceId: content.source.id,
                          child: FluxContinuArticleCard(
                            article: content,
                            onTap: () => onTapArticle(content),
                            onSwipeDismiss: onDismissArticle == null
                                ? null
                                : () => onDismissArticle!(content.id),
                            enableSwipeHint:
                                enableSwipeHintOnFirstCard &&
                                index == firstSwipeableIndex,
                            onSwipeHintComplete:
                                enableSwipeHintOnFirstCard &&
                                    index == firstSwipeableIndex
                                ? onSwipeHintComplete
                                : null,
                            nudgeAnchor: index == firstSwipeableIndex
                                ? firstSwipeableCardAnchor
                                : null,
                            onSwipeConversion: onSwipeConversion,
                            onLongPressConversion: onLongPressConversion,
                          ),
                        ),
              },
          ];
        }
        final firstSwipeableIndex = visible.indexWhere(
          (content) => !pendingFeedbackIds.contains(content.id),
        );
        final imageAllowed = _imageAllowedIds([
          for (final content in visible)
            (id: content.id, thumb: content.thumbnailUrl),
        ]);
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds.contains(visible[i].id))
              _feedbackInlineFor(visible[i].id)
            else
              _tracked(
                position: i,
                contentId: visible[i].id,
                scoreTotal: visible[i].recommendationReason?.scoreTotal,
                theme: themeSlug ?? visible[i].source.theme,
                sourceId: visible[i].source.id,
                child: FluxContinuArticleCard(
                  article: visible[i],
                  allowImageOnTop: imageAllowed.contains(visible[i].id),
                  onTap: () => onTapArticle(visible[i]),
                  onSwipeDismiss: onDismissArticle == null
                      ? null
                      : () => onDismissArticle!(visible[i].id),
                  enableSwipeHint:
                      enableSwipeHintOnFirstCard && i == firstSwipeableIndex,
                  onSwipeHintComplete:
                      enableSwipeHintOnFirstCard && i == firstSwipeableIndex
                      ? onSwipeHintComplete
                      : null,
                  nudgeAnchor: i == firstSwipeableIndex
                      ? firstSwipeableCardAnchor
                      : null,
                  onSwipeConversion: onSwipeConversion,
                  onLongPressConversion: onLongPressConversion,
                ),
              ),
          // Cohérence Tournée — un thème **maigre affiché** (≤1 survivant après
          // dédup, enrichi par réinjection) porte en pied le footer « Étoffer »
          // **déplié** (sources de qualité + recherche), vrai vecteur d'ajout.
          // Distinct de l'empty-state (items vides) au-dessus. Sujet custom →
          // CTA générique historique.
          if (section.kind == SectionKind.theme && underfilled)
            _themeFooter(
              themeSlug: themeSlug,
              label: label,
              initiallyExpanded: true,
              fallbackCtaLabel: 'Plus de sources',
            ),
          // Thème **riche** (assez d'articles) — Story 22.5 : le pied dépend du
          // nombre de sources déjà suivies sur le thème.
          //  - < kThemeFewFollowedSources sources suivies → footer « Étoffer »
          //    **replié** (« Ajouter des sources ») : l'user a peu de sources,
          //    on pousse la découverte.
          //  - sinon → « Tout lire › » (le thème est déjà bien couvert, on
          //    signale surtout l'accès à la page complète).
          // Branches mutuellement exclusives (un seul footer).
          if (section.kind == SectionKind.theme &&
              !underfilled &&
              themeSlug != null &&
              followedSourceCount < kThemeFewFollowedSources)
            EtofferThemeFooter(
              slug: themeSlug,
              label: label,
              onSearch: onAddSources,
            )
          else if (section.kind == SectionKind.theme &&
              !underfilled &&
              onSeeAll != null)
            _seeAllFooter(),
          // Section source non vide — pas de footer « Ajouter plus de sources »
          // (réservé aux thèmes) → « Tout lire › » discret pour re-signaler
          // l'ouverture de la page source. Exclut la veille (rendue plus haut).
          if (section.kind == SectionKind.source && onSeeAll != null)
            _seeAllFooter(),
        ];
    }
  }

  /// « Tout lire › » — CTA discret de bas de section, re-signalant l'ouverture
  /// de la page dédiée sur les sections **sans** footer d'ajout de sources
  /// (Actus du jour, sources non vides ; les thèmes portent déjà « Ajouter plus
  /// de sources »). Icône *après* le texte (chevron de progression), donc un
  /// `Row` explicite plutôt que `TextButton.icon`. Rendu seulement si [onSeeAll]
  /// est câblé. La hauteur réservée par ce footer est anticipée par le fit
  /// (`kSeeAllFooterHeight`) pour ne pas dérégler le snap.
  /// Style du CTA « Tout lire › » — figé en `static final` (et non alloué à
  /// chaque build) : `SectionBlock` se reconstruit par section à chaque frame
  /// au scroll, un `styleFrom` inline y rebâtirait le `ButtonStyle` inutilement.
  static final _seeAllFooterStyle = TextButton.styleFrom(
    foregroundColor: const Color(0xFF5D5B5A),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 28),
    // `shrinkWrap` : sans ça le TextButton réserve un tap-target de 48px de haut
    // (padded par défaut) → c'est cette hauteur fantôme, pas la marge, qui
    // éloignait « Tout lire › » de sa section. On la collapse au contenu réel.
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // Typo du DS (DM Sans via `labelMedium`) : le `TextStyle` brut précédent
    // n'avait pas de `fontFamily` → rendu dans la police système, hors DS. La
    // couleur reste portée par `foregroundColor` (texte + chevron).
    textStyle: FacteurTypography.labelMedium(
      const Color(0xFF5D5B5A),
    ).copyWith(fontSize: 12.5),
  );

  Widget _seeAllFooter() {
    // Volume promis par la page dédiée, borné [3, 9] : le compte vient du
    // snapshot client (`totalCount`, déjà en mémoire), jamais d'une requête —
    // ce CTA ne doit rien coûter au chargement. Le « + » assume la borne haute
    // (la page dédiée pagine au-delà).
    final count = section.totalCount.clamp(3, 9);
    return Container(
      // Marges resserrées : le CTA colle au bas de la dernière carte (qui porte
      // déjà 12px de padding bas). `kSeeAllFooterHeight` reflète la hauteur
      // rendue (tap-target collapsé) pour ne pas dérégler le budget de fit.
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      alignment: Alignment.center,
      child: TextButton(
        onPressed: onSeeAll,
        style: _seeAllFooterStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tout lire ($count+)'),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  /// Pied d'une section thématique : footer « Étoffer [thème] » (vrai vecteur
  /// d'ajout de sources de qualité) quand on a un slug macro-thème, sinon le
  /// CTA générique historique pour un sujet custom. Décision unique partagée
  /// par les cas thème vide / maigre.
  Widget _themeFooter({
    required String? themeSlug,
    required String label,
    required bool initiallyExpanded,
    required String fallbackCtaLabel,
    String? headline,
  }) {
    if (themeSlug != null) {
      return EtofferThemeFooter(
        slug: themeSlug,
        label: label,
        headline: headline,
        initiallyExpanded: initiallyExpanded,
        onSearch: onAddSources,
      );
    }
    return _FavoriteEmptyState(
      message: headline,
      ctaIcon: Icons.add_rounded,
      ctaLabel: fallbackCtaLabel,
      onCta: onAddSources,
    );
  }
}

/// Story 23.4 — état vide de la section veille (config active mais 0 article).
/// Garde la section visible et propose un CTA réglages.
class _VeilleEmptyState extends StatelessWidget {
  final VoidCallback? onTapSettings;
  const _VeilleEmptyState({this.onTapSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aucun nouvel article pour ta veille pour l\'instant.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF5D5B5A),
            ),
          ),
          if (onTapSettings != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onTapSettings,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Régler ma veille'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2C3E50),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// État vide partagé d'une section **favorite** (source ou thème) sans article
/// frais dans la fenêtre. Décision PO : ne jamais masquer un favori → la section
/// reste visible avec un placeholder + un CTA optionnel. Spécialisé par les
/// sections source (« Voir toute la curation ») et thème (« Ajouter des
/// sources » → « Composer ma Tournée »).
class _FavoriteEmptyState extends StatelessWidget {
  /// Message d'accroche. `null` ⇒ variante **CTA seul** (pied d'une section
  /// maigre déjà remplie : pas de message, juste le bouton « Ajouter plus de
  /// sources »).
  final String? message;
  final IconData ctaIcon;
  final String ctaLabel;
  final VoidCallback? onCta;
  const _FavoriteEmptyState({
    this.message,
    required this.ctaIcon,
    required this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: EdgeInsets.fromLTRB(16, message == null ? 10 : 18, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null)
            Text(
              message!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF5D5B5A),
              ),
            ),
          if (onCta != null) ...[
            if (message != null) const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCta,
                icon: Icon(ctaIcon, size: 16),
                label: Text(ctaLabel),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2C3E50),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Issue #1 — carte squelette d'une coquille de section (placeholder seed-é
/// avant le fan-out). Sa géométrie réserve `kRegularCardHeight` (146px : ~134px
/// de carte + 12px de marge basse) pour que l'arrivée du contenu réel
/// (`FluxContinuArticleCard`, même réserve) remplace **sur place** sans décaler
/// les sections suivantes. Calquée visuellement sur `ExploreDiscoverySkeleton`.
/// Publique pour être réutilisée par le squelette cold-start
/// (`_FluxContinuSkeleton`) → hauteur stable de bout en bout.
///
/// Le bloc respire (shimmer) : sans animation, les coquilles grises se lisent
/// comme un état vide définitif alors que le fan-out des sections thème/source
/// dure plusieurs secondes sous l'unique worker uvicorn.
class SectionSkeletonCard extends StatelessWidget {
  /// Libellé d'attente rendu **dans** la carte (cf. [kSectionPreparingLabel]).
  /// `null` = carte nue. Porté par la carte plutôt que par un widget au-dessus
  /// pour ne consommer aucune hauteur propre (géométrie stable).
  final String? label;

  const SectionSkeletonCard({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Mêmes teintes que `_MetaShimmer` (rituel matinal) — le sweep est porté par
    // le **fond** seul : le libellé est posé par-dessus, hors du ShaderMask, qui
    // sinon écraserait sa couleur.
    final base = facteurSkeletonBase(colors);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        height: 134,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Shimmer.fromColors(
              baseColor: base,
              highlightColor: facteurSkeletonHighlight(colors),
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
            if (label != null)
              Center(
                child: Text(
                  label!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Libellé d'attente unique de la Tournée, rendu dans la 1ʳᵉ carte squelette
/// non résolue (cf. `SectionBlock.showPreparingLabel`).
const String kSectionPreparingLabel = 'Ta tournée se prépare…';

/// Issue #1 — [count] cartes squelette réservant la hauteur finale d'une
/// section. Partagé par le placeholder de [SectionBlock] et le cold-skeleton
/// (`_FluxContinuSkeleton`) pour garantir la même géométrie de bout en bout.
/// [firstCardLabel] pose le libellé d'attente sur la première carte seulement.
List<Widget> sectionSkeletonCards(int count, {String? firstCardLabel}) => [
  for (var i = 0; i < count; i++)
    SectionSkeletonCard(label: i == 0 ? firstCardLabel : null),
];
