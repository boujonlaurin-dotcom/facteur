import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/theme.dart';
import '../../../shared/widgets/read_state_mark.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../digest/models/digest_models.dart';
import '../../digest/widgets/divergence_inline_badge.dart';
import '../../feed/models/content_model.dart';
import '../../feed/services/read_sync_service.dart';
import '../../feed/widgets/animated_feed_card.dart';
import '../../feed/widgets/swipe_to_open_card.dart';
import '../../settings/models/display_mode_spec.dart';
import '../../settings/providers/display_mode_provider.dart';
import '../../sources/models/source_model.dart';
import 'auto_grow_candidate.dart';
import 'coverage_chip.dart';

/// Unified view-model that hides the DigestItem vs Content split from the
/// rendering layer. Both types carry the fields needed to display a Flux
/// Continu list item, but their field names diverge enough to warrant a
/// thin adapter rather than a sea of conditionals in the widget.
class FluxArticleVM {
  final String contentId;
  final String title;
  final String? thumbnailUrl;
  final String sourceName;
  final String? sourceLogoUrl;
  final ContentType contentType;
  final int? durationSeconds;
  final DateTime? publishedAt;
  final bool isFollowedSource;

  /// État de lecture serveur-truth (avant fusion session), source unique dont
  /// dérivent [hasBeenRead] et [isCompleted]. Porte la 3ᵉ marche « Ouvert »
  /// quand le temps passé est connu (chemin `Content`) ; retombe sur « Lu en
  /// partie » quand il ne l'est pas (chemin `DigestItem`).
  final ReadState readState;

  const FluxArticleVM({
    required this.contentId,
    required this.title,
    required this.sourceName,
    required this.contentType,
    this.thumbnailUrl,
    this.sourceLogoUrl,
    this.durationSeconds,
    this.publishedAt,
    this.isFollowedSource = false,
    this.readState = ReadState.unread,
  });

  bool get hasBeenRead => readState != ReadState.unread;

  /// « Lu jusqu'au bout » — distinct de [hasBeenRead] que le seuil d'ouverture
  /// d'1 s suffit à déclencher.
  bool get isCompleted => readState == ReadState.completed;

  factory FluxArticleVM.from(Object article) {
    if (article is DigestItem) {
      return FluxArticleVM(
        contentId: article.contentId,
        title: article.title,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source?.name ?? 'Inconnu',
        sourceLogoUrl: article.source?.logoUrl,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
        publishedAt: article.publishedAt,
        isFollowedSource: article.isFollowedSource,
        // Le modèle mobile `DigestItem` (freezed) ne parse pas encore
        // `time_spent_seconds` (câblage déféré, cf. story 30.4) → signal inconnu :
        // `deriveReadState` retombe sur « Lu en partie » (0.6), jamais « Ouvert ».
        readState: deriveReadState(
          isConsumed: article.isRead,
          readingProgress: 0,
          isVideo: article.contentType == ContentType.youtube ||
              article.contentType == ContentType.video,
          timeSpentSeconds: null,
          isCompleted: article.completedAt != null,
        ),
      );
    }
    if (article is Content) {
      return FluxArticleVM(
        contentId: article.id,
        title: article.title,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source.name,
        sourceLogoUrl: article.source.logoUrl,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
        publishedAt: article.publishedAt,
        isFollowedSource: article.isFollowedSource,
        readState: article.readState,
      );
    }
    throw ArgumentError('Unsupported article type: ${article.runtimeType}');
  }
}

/// Article list item for the Flux Continu V1.8.
///
/// Layout per maquette V6 :
/// - 12px padding inside a 12-radius surface card, soft shadow.
/// - Head row : title (4-line ellipsis, DM Sans 18 w600) + 72×72 thumb on
///   the right (radius 10).
/// - Footer row (single-line) : source dot + name · clock·time
///   · pastille de couverture optionnelle (sujet couvert par ≥ 2 rédactions).
class FluxContinuArticleCard extends ConsumerStatefulWidget {
  final Object article;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeDismiss;
  final bool enableSwipeHint;
  final VoidCallback? onSwipeHintComplete;
  final GlobalKey? nudgeAnchor;
  final VoidCallback? onSwipeConversion;
  final VoidCallback? onLongPressConversion;
  /// Nombre de rédactions couvrant le sujet — pilote la pastille de couverture
  /// du footer (seuil [kCoverageChipMinSources]).
  final int sourceCount;
  final List<SourceMini> perspectiveSources;
  final String? divergenceLevel;

  /// Mode Lisible — autorise l'image pleine largeur en haut de carte. Mis à
  /// `false` par [SectionBlock] au-delà de la 2ᵉ carte porteuse d'image d'une
  /// section : la 3ᵉ image n'est pas affichée (carte en layout texte) pour
  /// éviter qu'une section ne devienne trop haute. Sans effet hors mode
  /// Lisible (image-on-top déjà désactivé).
  final bool allowImageOnTop;

  const FluxContinuArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onSwipeDismiss,
    this.enableSwipeHint = false,
    this.onSwipeHintComplete,
    this.nudgeAnchor,
    this.onSwipeConversion,
    this.onLongPressConversion,
    this.sourceCount = 0,
    this.perspectiveSources = const [],
    this.divergenceLevel,
    this.allowImageOnTop = true,
  });

  @override
  ConsumerState<FluxContinuArticleCard> createState() =>
      _FluxContinuArticleCardState();
}

class _FluxContinuArticleCardState
    extends ConsumerState<FluxContinuArticleCard> {
  bool _thumbErrored = false;

  @override
  Widget build(BuildContext context) {
    final vm = FluxArticleVM.from(widget.article);
    final wasConsumedThisSession = ref.watch(
      consumedContentIdsProvider.select((ids) => ids.contains(vm.contentId)),
    );
    // Complétée pendant la session : la carte reflète l'état sans attendre un
    // refetch du feed.
    final completedThisSession = ref.watch(
      completedContentIdsProvider.select((ids) => ids.contains(vm.contentId)),
    );
    final readState = effectiveReadState(
      vm.readState,
      consumedThisSession: wasConsumedThisSession,
      completedThisSession: completedThisSession,
    );
    final hasBeenRead = readState != ReadState.unread;
    final isCompleted = readState == ReadState.completed;
    final colors = context.facteurColors;
    final spec = ref.watch(displayModeSpecProvider);
    // Reclaim the thumb slot when the network image fails — avoids the
    // grey/broken visual reported on many Reporterre articles (cached
    // vignettes that 404 or load empty). Le mode minimaliste masque le thumb
    // pour toutes les cartes (spec.showImages).
    final hasThumb = spec.showImages &&
        vm.thumbnailUrl != null &&
        vm.thumbnailUrl!.isNotEmpty &&
        !_thumbErrored;
    const cardRadius = BorderRadius.all(Radius.circular(FacteurRadius.large));

    Widget card = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Opacity(
        opacity: opacityForReadState(readState),
        child: Stack(
          children: [
            // `animate: false` au montage : le filet d'une carte déjà aboutie
            // est peint d'emblée (c'est un état). `didUpdateWidget` anime la
            // seule transition qui est un événement — le retour d'article.
            AnimatedFeedCard(
              isCompleted: isCompleted,
              animate: false,
              child: Material(
              color: colors.surface,
              borderRadius: cardRadius,
              elevation: 0,
              child: AutoGrowCandidate(
                contentId: vm.contentId,
                isRead: hasBeenRead,
                child: ArticlePreviewGesture(
                  contentBuilder: () => articleToContent(widget.article),
                  onLongPressStart: () => widget.onLongPressConversion?.call(),
                  child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: cardRadius,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: cardRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: spec.imageOnTop && hasThumb && widget.allowImageOnTop
                        ? _buildImageOnTopBody(vm, spec, colors)
                        : _buildRowBody(vm, spec, colors, hasThumb),
                  ),
                ),
                ),
              ),
            ),
            ),
            if (hasBeenRead)
              Positioned(
                top: 4,
                right: 4,
                child: ReadStateMark(
                  color: colors.success,
                  state: readState,
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      card = SwipeToOpenCard(
        key: ValueKey('swipe_${vm.contentId}'),
        onSwipeOpen: widget.onTap!,
        onSwipeDismiss: widget.onSwipeDismiss,
        enableHintAnimation: widget.enableSwipeHint,
        onHintAnimationComplete: widget.onSwipeHintComplete,
        onSwipeGesture: widget.onSwipeConversion,
        child: card,
      );
    }

    return widget.nudgeAnchor == null
        ? card
        : KeyedSubtree(key: widget.nudgeAnchor, child: card);
  }

  /// Layout historique : titre à gauche, thumb carré optionnel à droite.
  /// Sert aussi de fallback ludique quand l'image est absente ou en erreur.
  Widget _buildRowBody(
    FluxArticleVM vm,
    DisplayModeSpec spec,
    FacteurColors colors,
    bool hasThumb,
  ) {
    return Padding(
      padding: spec.dense
          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
          : const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode Lisible — une carte SANS image gagne une ligne de titre
              // (4 au lieu de 3) : sans image dominante, il y a la place. Les
              // cartes avec image (_buildImageOnTopBody) gardent 3 lignes.
              Expanded(
                child: _title(
                  vm,
                  spec,
                  colors,
                  maxLines: spec.imageOnTop
                      ? spec.regularTitleMaxLines + 1
                      : spec.regularTitleMaxLines,
                ),
              ),
              if (hasThumb && spec.thumbSize > 0) ...[
                const SizedBox(width: 12),
                _Thumbnail(
                  url: vm.thumbnailUrl!,
                  isVideo: _isVideo(vm.contentType),
                  size: spec.thumbSize,
                  accent: colors.primary,
                  onError: _onThumbError,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _footer(vm, colors),
        ],
      ),
    );
  }

  /// Layout ludique : image pleine largeur en haut de carte (type carrousel),
  /// bloc texte paddé dessous. Hauteur d'image **fixe** (spec) pour que
  /// l'estimation `regularCardHeight` du fit reste juste sur tout device.
  Widget _buildImageOnTopBody(
    FluxArticleVM vm,
    DisplayModeSpec spec,
    FacteurColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FacteurRadius.large),
          ),
          child: SizedBox(
            width: double.infinity,
            height: spec.regularImageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FacteurImage(
                  imageUrl: vm.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_) => Container(
                    color: colors.primary.withValues(alpha: 0.06),
                  ),
                  errorWidget: (_) {
                    // Bubble up → la carte rebuild en layout texte standard.
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _onThumbError());
                    return const SizedBox.shrink();
                  },
                ),
                if (_isVideo(vm.contentType))
                  const Center(child: _VideoPlayBadge()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _title(vm, spec, colors),
              const SizedBox(height: 10),
              _footer(vm, colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _title(
    FluxArticleVM vm,
    DisplayModeSpec spec,
    FacteurColors colors, {
    int? maxLines,
  }) {
    return Text(
      vm.title,
      style: GoogleFonts.dmSans(
        fontSize: 18.0 * spec.fontScale,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.15,
        color: colors.textPrimary,
      ),
      maxLines: maxLines ?? spec.regularTitleMaxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _footer(FluxArticleVM vm, FacteurColors colors) {
    return _Footer(
      vm: vm,
      colors: colors,
      showCoverage: widget.sourceCount >= kCoverageChipMinSources,
      sourceCount: widget.sourceCount,
      perspectiveSources: widget.perspectiveSources,
      divergenceLevel: widget.divergenceLevel,
    );
  }

  void _onThumbError() {
    if (mounted && !_thumbErrored) {
      setState(() => _thumbErrored = true);
    }
  }

  bool _isVideo(ContentType type) =>
      type == ContentType.video || type == ContentType.youtube;
}

/// Adapter producing a synthetic [Content] suitable for
/// `TopicChip.showArticleSheet` regardless of the source type. [DigestItem]
/// carries every field needed by the sheet except the rich [Source] object —
/// a minimal [Source] is built from its [SourceMini]. Exposed as top-level so
/// the screen can reuse it when resolving an inline-feedback chip on a digest
/// lead.
Content articleToContent(Object article) {
  if (article is Content) return article;
  if (article is DigestItem) {
    final src = article.source;
    return Content(
      id: article.contentId,
      title: article.title,
      url: article.url,
      thumbnailUrl: article.thumbnailUrl,
      description: article.description,
      htmlContent: article.htmlContent,
      contentType: article.contentType,
      durationSeconds: article.durationSeconds,
      publishedAt: article.publishedAt ?? DateTime.now(),
      source: Source(
        id: src?.id ?? '',
        name: src?.name ?? 'Inconnu',
        type: SourceType.article,
        theme: src?.theme,
        logoUrl: src?.logoUrl,
      ),
      topics: article.topics,
      isPaid: article.isPaid,
      isSaved: article.isSaved,
      isLiked: article.isLiked,
      // Sans ça l'écran de détail ouvert depuis une carte du flux rejouait la
      // complétion (haptique + POST + `article_finished`) sur un article déjà
      // terminé.
      completedAt: article.completedAt,
    );
  }
  throw ArgumentError('Unsupported article type: ${article.runtimeType}');
}

class _Thumbnail extends StatelessWidget {
  final String url;
  final bool isVideo;
  final double size;
  final Color accent;
  final VoidCallback onError;

  const _Thumbnail({
    required this.url,
    required this.isVideo,
    required this.size,
    required this.accent,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final loadingPlaceholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FacteurImage(
              imageUrl: url,
              width: size,
              height: size,
              placeholder: (_) => loadingPlaceholder,
              errorWidget: (_) {
                // Bubble up so the parent card can drop the thumb slot
                // entirely (next rebuild). Returning shrink keeps the
                // current frame from flashing a placeholder.
                WidgetsBinding.instance.addPostFrameCallback((_) => onError());
                return const SizedBox.shrink();
              },
            ),
            if (isVideo) const Center(child: _VideoPlayBadge()),
          ],
        ),
      ),
    );
  }
}

/// Small play badge overlay for YouTube/video thumbnails — sized for the
/// 78×78 article-card thumb (the shared [VideoPlayOverlay] is tuned for
/// large reader hero images).
class _VideoPlayBadge extends StatelessWidget {
  const _VideoPlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          PhosphorIcons.play(PhosphorIconsStyle.fill),
          size: 14,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final FluxArticleVM vm;
  final FacteurColors colors;
  final bool showCoverage;
  final int sourceCount;
  final List<SourceMini> perspectiveSources;
  final String? divergenceLevel;

  const _Footer({
    required this.vm,
    required this.colors,
    required this.showCoverage,
    required this.sourceCount,
    required this.perspectiveSources,
    this.divergenceLevel,
  });

  @override
  Widget build(BuildContext context) {
    final separator = Text(
      '·',
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textTertiary.withValues(alpha: 0.55),
      ),
    );

    // Deux groupes : l'identité (qui flexe) et le trailing (taille fixe).
    // Un `Spacer` au même niveau que le `Flexible` du nom se partagerait
    // l'espace libre à 50/50 — un nom long ne rétrécissait alors que jusqu'à sa
    // moitié et le trailing débordait. Ici l'`Expanded` pousse le trailing à
    // droite ET absorbe toute la contrainte, donc le nom s'ellipse en premier.
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              SourceDot(
                name: vm.sourceName,
                logoUrl: vm.sourceLogoUrl,
                accent: colors.primary,
                ringColor: colors.surface,
                size: 14,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  vm.sourceName,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!vm.isFollowedSource) ...[
                const SizedBox(width: 3),
                Text(
                  '+',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              separator,
              const SizedBox(width: 6),
              Icon(
                PhosphorIconsRegular.clock,
                size: 12,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 3),
              Text(
                _publishedAtShort(vm.publishedAt),
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (divergenceLevel != null) ...[
          const SizedBox(width: 6),
          DivergenceInlineBadge(
            divergenceLevel: divergenceLevel,
            iconOnly: true,
          ),
        ],
        if (showCoverage) ...[
          const SizedBox(width: 6),
          CoverageChip(
            key: const Key('flux-coverage-chip'),
            sourceCount: sourceCount,
            sources: perspectiveSources,
            colors: colors,
          ),
        ],
      ],
    );
  }

  String _publishedAtShort(DateTime? date) {
    if (date == null) return 'récent';
    return timeago
        .format(date, locale: 'fr_short')
        .replaceAll('il y a ', '')
        .trim();
  }
}
