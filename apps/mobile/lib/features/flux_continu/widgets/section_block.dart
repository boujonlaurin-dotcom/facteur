import 'package:flutter/material.dart';

import '../../feed/widgets/feedback_inline.dart';
import '../models/flux_continu_models.dart';
import 'essentiel_hi_fi_card.dart';
import 'flux_continu_article_card.dart';
import 'folded_section_card.dart';
import 'plus_de_button.dart';
import 'section_banner.dart';
import 'tournee_composer_sheet.dart';

/// Identifies which chip the user picked on a [FeedbackInline] banner.
enum FluxFeedbackChip { source, topic, alreadySeen }

/// Composes one section of the Flux Continu V1.8: banner → cards → "Plus
/// de…" overflow. State (open/closed for the overflow) is passed in so the
/// provider remains the single source of truth.
///
/// For [DigestTopicSection], the section renders one card per topic, the
/// lead article being picked by [pickTopicLead]. For [FeedThemeSection],
/// one card per feed item.
class SectionBlock extends StatelessWidget {
  final FluxSection section;
  final bool isOpen;
  final bool isFolded;
  final VoidCallback onToggleMore;
  final VoidCallback? onUnfold;
  final VoidCallback? onFold;
  final void Function(Object article, FluxSection section) onTapArticle;
  final ValueChanged<String>? onDismissArticle;

  /// Opens the dedicated full-page view for a [FeedThemeSection]. Wired by
  /// the flux_continu screen to push `/flux-continu/theme/:key`. Ignored
  /// for [DigestTopicSection] which keeps its in-place fold/expand button.
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

  const SectionBlock({
    super.key,
    required this.section,
    required this.isOpen,
    required this.onToggleMore,
    required this.onTapArticle,
    this.isFolded = false,
    this.onUnfold,
    this.onFold,
    this.onDismissArticle,
    this.pendingFeedbackIds = const <String>{},
    this.onSelectFeedbackChip,
    this.onResolveFeedback,
    this.onUndoFeedback,
    this.enableSwipeHintOnFirstCard = false,
    this.onSwipeHintComplete,
    this.onTapFavorite,
    this.onTapSettings,
    this.onAddSources,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    // Instant swap (no AnimatedSize): the screen's scroll listener compensates
    // the offset by the exact pixel delta the moment we shrink, so the
    // viewport visually doesn't move. An animated transition here would defeat
    // the compensation by leaving the height in flux when the post-frame
    // callback measures it.
    return isFolded ? _buildFolded() : _buildExpanded();
  }

  Widget _buildFolded() {
    return FoldedSectionCard(
      title: section.label,
      articleCount: section.totalCount,
      onTap: onUnfold,
    );
  }

  Widget _buildExpanded() {
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
              onTapArticle: (a) => onTapArticle(a, section),
              onTapPersonalize: () => showTourneeComposerSheet(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    final cards = _buildCards();
    final hiddenCount = section.totalCount - section.coreVisibleCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBanner(
          title: section.label,
          accent: section.accent,
          blurb: section.blurb,
          illustrationAsset: section.illustrationAsset,
          // PR « Sources dans la Tournée » — hero logo source à la place de
          // l'illustration thème.
          logoUrl: section is FeedThemeSection &&
                  section.kind == SectionKind.source
              ? section.sourceLogoUrl
              : null,
          onTapFold: onFold,
          onTapFavorite: onTapFavorite,
          onTapSettings: onTapSettings,
        ),
        ...cards,
        _SectionFooterRow(
          voirPlus: _buildVoirPlusButton(section, hiddenCount),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Returns the "Voir tout" / "Plus de…" button for this section, or null
  /// when no overflow CTA applies.
  Widget? _buildVoirPlusButton(FluxSection section, int hiddenCount) {
    // Filet de sécurité : le bouton est TOUJOURS rendu pour une section thème
    // (indépendant de la taille du pool). Le deep-dive est la seule route vers
    // carrousels / « Explorer plus » / CTA « Sujet suivant », donc on ne le
    // masque jamais — même quand la section tient en entier à l'écran.
    if (section is FeedThemeSection && onSeeAll != null) {
      return SeeAllSectionButton(
        hiddenCount: hiddenCount > 0 ? hiddenCount : 0,
        onTap: onSeeAll!,
      );
    }
    if (section is DigestTopicSection &&
        onSeeAll != null &&
        section.hasOverflow) {
      return SeeAllSectionButton(
        hiddenCount: hiddenCount > 0 ? hiddenCount : 0,
        onTap: onSeeAll!,
      );
    }
    if (section.hasOverflow) {
      return PlusDeButton(
        sectionLabel: section.label,
        isOpen: isOpen,
        hiddenCount: hiddenCount > 0 ? hiddenCount : 0,
        onTap: onToggleMore,
      );
    }
    return null;
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

  List<Widget> _buildCards() {
    final isEssentiel = section.kind == SectionKind.essentiel;
    switch (section) {
      case EssentielSection():
        // _buildExpanded short-circuits to EssentielHiFiCard before reaching
        // _buildCards, so this branch is unreachable in practice.
        return const [];
      case DigestTopicSection(:final topics, :final coreVisibleCount):
        final visible =
            isOpen ? topics : topics.take(coreVisibleCount).toList();
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds
                .contains(pickTopicLead(visible[i]).contentId))
              _feedbackInlineFor(pickTopicLead(visible[i]).contentId)
            else
              FluxContinuArticleCard(
                article: pickTopicLead(visible[i]),
                isEssentiel: isEssentiel,
                pressReviewCount: visible[i].perspectiveCount,
                perspectiveSources: visible[i].perspectiveSources,
                divergenceLevel: visible[i].divergenceLevel,
                onTap: () =>
                    onTapArticle(pickTopicLead(visible[i]), section),
                onSwipeDismiss: onDismissArticle == null
                    ? null
                    : () =>
                        onDismissArticle!(pickTopicLead(visible[i]).contentId),
                enableSwipeHint: enableSwipeHintOnFirstCard && i == 0,
                onSwipeHintComplete:
                    enableSwipeHintOnFirstCard && i == 0
                        ? onSwipeHintComplete
                        : null,
              ),
        ];
      case FeedThemeSection(:final items, :final coreVisibleCount):
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
            )
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
            )
          ];
        }
        final visible = items.take(coreVisibleCount).toList();
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds.contains(visible[i].id))
              _feedbackInlineFor(visible[i].id)
            else
              FluxContinuArticleCard(
                article: visible[i],
                onTap: () => onTapArticle(visible[i], section),
                onSwipeDismiss: onDismissArticle == null
                    ? null
                    : () => onDismissArticle!(visible[i].id),
                enableSwipeHint: enableSwipeHintOnFirstCard && i == 0,
                onSwipeHintComplete:
                    enableSwipeHintOnFirstCard && i == 0
                        ? onSwipeHintComplete
                        : null,
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
  final String message;
  final IconData ctaIcon;
  final String ctaLabel;
  final VoidCallback? onCta;
  const _FavoriteEmptyState({
    required this.message,
    required this.ctaIcon,
    required this.ctaLabel,
    this.onCta,
  });

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
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF5D5B5A),
            ),
          ),
          if (onCta != null) ...[
            const SizedBox(height: 8),
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

/// Footer for a [SectionBlock]: renders the full-width "Voir tout" / "Plus
/// de…" overflow button (or nothing when the section has no overflow CTA).
/// Owns the bottom padding so the button stays flush with the cards above.
class _SectionFooterRow extends StatelessWidget {
  final Widget? voirPlus;

  const _SectionFooterRow({this.voirPlus});

  @override
  Widget build(BuildContext context) {
    final voirPlus = this.voirPlus;
    if (voirPlus == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: voirPlus,
    );
  }
}
