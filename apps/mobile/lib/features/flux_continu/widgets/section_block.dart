import 'package:flutter/material.dart';

import '../../feed/widgets/feedback_inline.dart';
import '../models/flux_continu_models.dart';
import 'essentiel_hi_fi_card.dart';
import 'flux_continu_article_card.dart';
import 'section_banner.dart';
import 'tournee_composer_sheet.dart';
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

  /// EPIC « Lettre du jour » — `false` ⇒ rendu **lecture seule** (lettre d'un
  /// jour passé) : masque le bouton « personnaliser » du héros Essentiel. Le
  /// reste de la lecture seule (pas de swipe/feedback) découle déjà des
  /// callbacks de mutation laissés nuls par l'appelant.
  final bool interactive;

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
    this.interactive = true,
  });

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
            EssentielHiFiCard(
              articles: section.articles,
              onTapArticle: (a) => onTapArticle(a),
              // Lecture seule (lettre passée) : bouton « personnaliser » masqué.
              onTapPersonalize: interactive
                  ? () => showTourneeComposerSheet(context)
                  : null,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    final cards = _buildCards();
    final hiddenCount =
        (section.totalCount - section.coreVisibleCount).clamp(0, 999);
    // Section source sans article récent (≤72h) mais avec des cartes plus
    // anciennes (repli 30 j backend) → on signale « Pas d'article récent. » dans
    // la blurb du banner. L'empty-state (aucun article même vieux) reste géré
    // par _buildCards et n'affiche pas cette note.
    final effectiveBlurb = section is FeedThemeSection &&
            section.kind == SectionKind.source &&
            section.noRecentSource &&
            section.items.isNotEmpty
        ? 'Pas d\'article récent.'
        : section.blurb;
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
          hiddenCount: hiddenCount,
          // Story 22.3 — badge « Choisie pour vous » sur les sections suggérées.
          suggested: section is FeedThemeSection && section.isSuggested,
          onTapInfo: onTapSuggestionInfo,
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
    final isEssentiel = section.kind == SectionKind.essentiel;
    switch (section) {
      case EssentielSection():
        // build() short-circuits to EssentielHiFiCard before reaching
        // _buildCards, so this branch is unreachable in practice.
        return const [];
      case DigestTopicSection(:final topics, :final coreVisibleCount):
        final visible = topics.take(coreVisibleCount).toList();
        final firstSwipeableIndex = visible.indexWhere(
          (topic) =>
              !pendingFeedbackIds.contains(pickTopicLead(topic).contentId),
        );
        final imageAllowed = _imageAllowedIds([
          for (final topic in visible)
            (
              id: pickTopicLead(topic).contentId,
              thumb: pickTopicLead(topic).thumbnailUrl,
            ),
        ]);
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds.contains(
              pickTopicLead(visible[i]).contentId,
            ))
              _feedbackInlineFor(pickTopicLead(visible[i]).contentId)
            else
              FluxContinuArticleCard(
                article: pickTopicLead(visible[i]),
                isEssentiel: isEssentiel,
                allowImageOnTop: imageAllowed.contains(
                  pickTopicLead(visible[i]).contentId,
                ),
                pressReviewCount: visible[i].perspectiveCount,
                perspectiveSources: visible[i].perspectiveSources,
                divergenceLevel: visible[i].divergenceLevel,
                onTap: () => onTapArticle(pickTopicLead(visible[i])),
                onSwipeDismiss: onDismissArticle == null
                    ? null
                    : () => onDismissArticle!(
                          pickTopicLead(visible[i]).contentId,
                        ),
                enableSwipeHint:
                    enableSwipeHintOnFirstCard && i == firstSwipeableIndex,
                onSwipeHintComplete:
                    enableSwipeHintOnFirstCard && i == firstSwipeableIndex
                        ? onSwipeHintComplete
                        : null,
                nudgeAnchor:
                    i == firstSwipeableIndex ? firstSwipeableCardAnchor : null,
                onSwipeConversion: onSwipeConversion,
                onLongPressConversion: onLongPressConversion,
              ),
        ];
      case FeedThemeSection(
          :final items,
          :final coreVisibleCount,
          :final underfilled,
        ):
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
          return [
            _FavoriteEmptyState(
              message: 'Rien de neuf récemment sur ${section.label}.',
              ctaIcon: Icons.add_rounded,
              ctaLabel: 'Ajouter des sources',
              onCta: onAddSources,
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
                      : FluxContinuArticleCard(
                          article: content,
                          onTap: () => onTapArticle(content),
                          onSwipeDismiss: onDismissArticle == null
                              ? null
                              : () => onDismissArticle!(content.id),
                          enableSwipeHint: enableSwipeHintOnFirstCard &&
                              index == firstSwipeableIndex,
                          onSwipeHintComplete: enableSwipeHintOnFirstCard &&
                                  index == firstSwipeableIndex
                              ? onSwipeHintComplete
                              : null,
                          nudgeAnchor: index == firstSwipeableIndex
                              ? firstSwipeableCardAnchor
                              : null,
                          onSwipeConversion: onSwipeConversion,
                          onLongPressConversion: onLongPressConversion,
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
              FluxContinuArticleCard(
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
                nudgeAnchor:
                    i == firstSwipeableIndex ? firstSwipeableCardAnchor : null,
                onSwipeConversion: onSwipeConversion,
                onLongPressConversion: onLongPressConversion,
              ),
          // Cohérence Tournée — un thème **maigre affiché** (≤1 survivant après
          // dédup, enrichi par réinjection) porte en pied un CTA pour étoffer la
          // section. Distinct de l'empty-state (items vides) au-dessus.
          if (section.kind == SectionKind.theme && underfilled)
            _FavoriteEmptyState(
              ctaIcon: Icons.add_rounded,
              ctaLabel: 'Ajouter plus de sources',
              onCta: onAddSources,
            ),
        ];
    }
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

