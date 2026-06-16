import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/web/web_perf.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../digest/widgets/divergence_inline_badge.dart';
import '../../digest/widgets/markdown_text.dart';
import '../../digest/widgets/section_divider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_detail_modal.dart';
import '../providers/feed_provider.dart';
import '../repositories/feed_repository.dart' show HighlightSpan, TokenSpan;
import 'coverage_comparison_card.dart';
import 'coverage_spectrum_bar.dart';
import 'diff_title.dart';

/// Texte d'introduction expliquant le surlignage. Affiché dans le bottom-sheet
/// modal ET derrière le bouton info de la section inline du reader d'article
/// — single source of truth pour les deux vues.
const String kHighlightIntroText =
    'Le surlignage met en évidence les termes qui '
    'marquent l\'angle éditorial : plus le surlignage '
    'est intense, plus le choix de mot est éditorialisé.';

/// Disclaimer affiché sous l'analyse Facteur — partagé par la zone inline
/// plein écran ([PerspectivesAnalysisZone]) et le bottom sheet ([_AnalysisSheet]).
const String kAnalysisDisclaimerText =
    'Analyse générée par Mistral Large · '
    "l'IA peut faire des erreurs.";

const String kDivergenceExplanationText =
    'Facteur mesure la divergence en comparant le vocabulaire et le cadrage '
    'adopté par chaque source ayant couvert cet article. '
    'Un niveau élevé (Polarisé) signale des angles éditoriaux très différents ; '
    'un niveau bas (Traitements similaires) indique un traitement convergent.';

/// Ouvre l'URL d'une perspective dans le reader unique (`ContentDetailScreen`
/// en mode externe) via la route `content-external` sur le root navigator.
/// On garde ainsi le MÊME header / footer / scroll / anti-saccades que pour un
/// article interne — plus de webview dupliquée à re-diverger. La route étant
/// full-screen + swipe-back iOS, fermer le reader ramène sur la sheet de
/// comparaisons intacte (elle-même sur le root navigator).
void openPerspectiveReader(BuildContext context, Perspective p) {
  context.pushNamed(RouteNames.contentExternal, extra: p);
}

/// Model for a perspective from an external source
class Perspective {
  final String title;
  final String url;
  final String sourceName;
  final String sourceDomain;
  final String biasStance;
  final String? publishedAt;

  /// Tokens divergents du titre vs. référence, colorisés par bias.
  final List<HighlightSpan> highlightSpans;

  /// Tokens partagés avec la référence (rendus en text_tertiary par DiffTitle).
  final List<TokenSpan> sharedTokens;

  /// Langue ISO du titre ("fr","en",...). Optionnel — exposé par PR 5.
  /// Réservé au regroupement "Couverture étrangère" (PR 6.1).
  final String? language;

  Perspective({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceDomain,
    required this.biasStance,
    this.publishedAt,
    this.highlightSpans = const [],
    this.sharedTokens = const [],
    this.language,
  });

  factory Perspective.fromJson(Map<String, dynamic> json) {
    // DÉSACTIVÉ (T1) : le highlighting des biais n'est plus affiché → on ne
    // parse plus `highlight_spans` / `shared_tokens` ; les champs restent à
    // `const []` ⇒ DiffTitle rend un titre plain. Réactivation = re-parser ici
    // (et aux autres sites de construction de Perspective).
    return Perspective(
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      sourceName: (json['source_name'] as String?) ?? 'Unknown',
      sourceDomain: (json['source_domain'] as String?) ?? '',
      biasStance: (json['bias_stance'] as String?) ?? 'unknown',
      publishedAt: json['published_at'] as String?,
      language: json['language'] as String?,
    );
  }

  Color getBiasColor(FacteurColors colors) =>
      Perspective.colorForStance(biasStance, colors);

  /// Mapping bord politique → couleur. Single source of truth réutilisé par
  /// [getBiasColor] (instance).
  static Color colorForStance(String stance, FacteurColors colors) {
    switch (stance) {
      case 'left':
        return colors.biasLeft;
      case 'center-left':
        return colors.biasCenterLeft;
      case 'center':
        return colors.biasCenter;
      case 'center-right':
        return colors.biasCenterRight;
      case 'right':
        return colors.biasRight;
      default:
        return colors.biasUnknown;
    }
  }

  String getBiasLabel() => Perspective.getBiasLabelFromStance(biasStance);

  static String getBiasLabelFromStance(String stance) {
    switch (stance) {
      case 'left':
        return 'Gauche';
      case 'center-left':
        return 'Centre-G';
      case 'center':
        return 'Centre';
      case 'center-right':
        return 'Centre-D';
      case 'right':
        return 'Droite';
      default:
        return '?';
    }
  }

  /// Map detailed bias to simplified 3-segment group
  String get biasGroup {
    switch (biasStance) {
      case 'left':
      case 'center-left':
        return 'gauche';
      case 'center':
        return 'centre';
      case 'center-right':
      case 'right':
        return 'droite';
      default:
        return 'centre';
    }
  }
}

/// Map a detailed bias stance to a simplified 3-segment group
String _toBarGroup(String stance) {
  switch (stance) {
    case 'left':
    case 'center-left':
      return 'gauche';
    case 'center':
      return 'centre';
    case 'center-right':
    case 'right':
      return 'droite';
    default:
      return 'centre';
  }
}

/// Analysis workflow state
enum PerspectivesAnalysisState { idle, loading, done, error }

enum PerspectivesSectionStatus { loading, empty, ready }

/// Bottom sheet to display alternative perspectives
class PerspectivesBottomSheet extends ConsumerStatefulWidget {
  final List<Perspective> perspectives;
  final Map<String, int> biasDistribution;
  final List<String> keywords;
  final String sourceBiasStance;
  final String sourceName;
  final String contentId;
  final String comparisonQuality;
  final String? divergenceLevel;

  const PerspectivesBottomSheet({
    super.key,
    required this.perspectives,
    required this.biasDistribution,
    required this.keywords,
    required this.contentId,
    this.sourceBiasStance = 'unknown',
    this.sourceName = '',
    this.comparisonQuality = 'low',
    this.divergenceLevel,
  });

  @override
  ConsumerState<PerspectivesBottomSheet> createState() =>
      _PerspectivesBottomSheetState();
}

class _PerspectivesBottomSheetState
    extends ConsumerState<PerspectivesBottomSheet> {
  PerspectivesAnalysisState _analysisState = PerspectivesAnalysisState.idle;
  String? _analysisText;
  Set<String> _selectedSegments = {};
  // Sprint 2 PR1 — perspective comparison events.
  DateTime? _openedAt;
  final Set<String> _viewedPerspectiveIds = <String>{};

  static const _groupOrder = ['gauche', 'centre', 'droite'];

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsServiceProvider).trackPerspectiveComparisonOpened(
            contentId: widget.contentId,
            sourcesCount: widget.perspectives.length,
          );
    });
  }

  @override
  void dispose() {
    final opened = _openedAt;
    final elapsed =
        opened != null ? DateTime.now().difference(opened).inSeconds : 0;
    // En tests / teardown rapide, le ProviderScope peut être disposé avant
    // ce widget — on ne veut pas crasher pour un event analytics.
    try {
      ref.read(analyticsServiceProvider).trackPerspectiveComparisonClosed(
            contentId: widget.contentId,
            viewedArticles: _viewedPerspectiveIds.length,
            openedSeconds: elapsed,
          );
    } catch (_) {}
    super.dispose();
  }

  void _onPerspectiveViewed(String perspectiveId) {
    if (!_viewedPerspectiveIds.add(perspectiveId)) return;
    ref.read(analyticsServiceProvider).trackPerspectiveArticleViewed(
          contentId: widget.contentId,
          perspectiveArticleId: perspectiveId,
        );
  }

  Map<String, int> get _mergedDistribution {
    final dist = widget.biasDistribution;
    return {
      'gauche': (dist['left'] ?? 0) + (dist['center-left'] ?? 0),
      'centre': dist['center'] ?? 0,
      'droite': (dist['center-right'] ?? 0) + (dist['right'] ?? 0),
    };
  }

  List<Perspective> get _sortedPerspectives {
    final sorted = [...widget.perspectives];
    sorted.sort(
      (a, b) => _groupOrder
          .indexOf(a.biasGroup)
          .compareTo(_groupOrder.indexOf(b.biasGroup)),
    );
    return sorted;
  }

  List<Perspective> get _filteredPerspectives {
    final sorted = _sortedPerspectives;
    if (_selectedSegments.isEmpty) return sorted;
    return sorted
        .where((p) => _selectedSegments.contains(p.biasGroup))
        .toList();
  }

  void _onSegmentTapInternal(String key) {
    setState(() {
      if (_selectedSegments.contains(key)) {
        if (_selectedSegments.length == 1) {
          _selectedSegments = {};
        } else {
          _selectedSegments = Set.from(_selectedSegments)..remove(key);
        }
      } else {
        if (_selectedSegments.isEmpty || _selectedSegments.length == 3) {
          _selectedSegments = {key};
        } else {
          _selectedSegments = Set.from(_selectedSegments)..add(key);
        }
      }
    });
  }

  Future<void> _requestAnalysis() async {
    setState(() => _analysisState = PerspectivesAnalysisState.loading);

    try {
      final repository = ref.read(feedRepositoryProvider);

      final result = await repository.analyzePerspectives(widget.contentId);
      if (!mounted) return;

      setState(() {
        _analysisText = result;
        _analysisState = result != null
            ? PerspectivesAnalysisState.done
            : PerspectivesAnalysisState.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _analysisState = PerspectivesAnalysisState.error);
    }
  }

  /// Sépare FR (langue null ou `fr`) des couvertures étrangères et insère
  /// un `SectionDivider` "Couverture à l'étranger" entre les deux blocs.
  List<Widget> _buildPerspectiveCards(List<Perspective> perspectives) {
    final fr = <Perspective>[];
    final foreign = <Perspective>[];
    for (final p in perspectives) {
      if (p.language == null || p.language == 'fr') {
        fr.add(p);
      } else {
        foreign.add(p);
      }
    }

    Widget card(Perspective p, {bool dim = false}) {
      final w = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _PerspectiveCard(perspective: p, onView: _onPerspectiveViewed),
      );
      return dim ? Opacity(opacity: 0.92, child: w) : w;
    }

    return [
      for (final p in fr) card(p),
      if (foreign.isNotEmpty) ...[
        const SectionDivider(label: "Couverture à l'étranger"),
        for (final p in foreign) card(p, dim: true),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filteredPerspectives;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.perspectives.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                PhosphorIcons.eye(PhosphorIconsStyle.regular),
                                color: colors.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Couverture médiatique',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                    fontSize:
                                        (textTheme.titleMedium?.fontSize ??
                                                16) +
                                            1,
                                  ),
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  PhosphorIcons.x(PhosphorIconsStyle.bold),
                                ),
                                onPressed: () => Navigator.pop(context),
                                color: colors.textSecondary,
                              ),
                            ],
                          ),
                          if (widget.comparisonQuality == 'low')
                            PerspectivesWarningBadge(
                              colors: colors,
                              textTheme: textTheme,
                            ),
                          if (widget.divergenceLevel != null) ...[
                            const SizedBox(height: 8),
                            DivergenceInlineBadge(
                              divergenceLevel: widget.divergenceLevel,
                            ),
                            const SizedBox(height: 4),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            kHighlightIntroText,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          PerspectivesBiasBar(
                            colors: colors,
                            mergedDistribution: _mergedDistribution,
                            sourceBiasStance: widget.sourceBiasStance,
                            sourceName: widget.sourceName,
                            selectedSegments: _selectedSegments,
                            onSegmentTap: _onSegmentTapInternal,
                          ),
                          SizedBox(
                            height: 20,
                            child: _selectedSegments.isNotEmpty
                                ? Align(
                                    alignment: Alignment.centerRight,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _selectedSegments = {},
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Tout afficher',
                                            style:
                                                textTheme.labelSmall?.copyWith(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            PhosphorIcons.x(
                                              PhosphorIconsStyle.bold,
                                            ),
                                            size: 12,
                                            color: colors.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    // Split FR ("language" null ou "fr") des couvertures
                    // étrangères. Le panel reste pluraliste : insensible au
                    // toggle "Masquer les sources non françaises" (PO).
                    ..._buildPerspectiveCards(filtered),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: PerspectivesAnalysisZone(
                        state: _analysisState,
                        text: _analysisText,
                        onRequestAnalysis: _requestAnalysis,
                        colors: colors,
                        textTheme: textTheme,
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIcons.eye(PhosphorIconsStyle.regular),
                            color: colors.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Couverture médiatique',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                                fontSize:
                                    (textTheme.titleMedium?.fontSize ?? 16) + 1,
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              PhosphorIcons.x(PhosphorIconsStyle.bold),
                            ),
                            onPressed: () => Navigator.pop(context),
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PerspectivesEmptyState(
                      colors: colors,
                      textTheme: textTheme,
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

class _ShimmerLine extends StatefulWidget {
  final double width;
  final FacteurColors colors;

  const _ShimmerLine({required this.width, required this.colors});

  @override
  State<_ShimmerLine> createState() => _ShimmerLineState();
}

class _ShimmerLineState extends State<_ShimmerLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FractionallySizedBox(
          widthFactor: widget.width,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: widget.colors.textSecondary.withValues(
                alpha: 0.08 + 0.08 * _controller.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Triangle painter for the "Votre source" marker
class PerspectivesTrianglePainter extends CustomPainter {
  final Color color;

  PerspectivesTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PerspectiveCard extends ConsumerWidget {
  final Perspective perspective;
  // Sprint 2 PR1 — optional hook fired with a stable perspective id
  // before the external URL is launched, so the parent sheet can emit
  // perspective_article_viewed and keep track of unique views.
  final void Function(String perspectiveId)? onView;

  const _PerspectiveCard({required this.perspective, this.onView});

  /// Find matching Source from user sources by domain
  Source? _findSource(List<Source> sources) {
    final domain = perspective.sourceDomain.toLowerCase();
    if (domain.isEmpty) return null;
    return sources.cast<Source?>().firstWhere((s) {
      if (s?.url == null) return false;
      final uri = Uri.tryParse(s!.url!);
      if (uri == null) return false;
      final host = uri.host.toLowerCase().replaceFirst('www.', '');
      return host == domain || host == 'www.$domain';
    }, orElse: () => null);
  }

  void _showSourceDetail(BuildContext context, WidgetRef ref, Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceDetailModal(
        source: source,
        onToggleTrust: () {
          ref
              .read(userSourcesProvider.notifier)
              .toggleTrust(source.id, source.isTrusted);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final sourcesAsync = ref.watch(userSourcesProvider);
    final matchedSource = sourcesAsync.valueOrNull != null
        ? _findSource(sourcesAsync.valueOrNull!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FacteurCard(
        padding: EdgeInsets.zero,
        borderRadius: FacteurRadius.small,
        onTap: () {
          final perspectiveId = perspective.sourceDomain.isNotEmpty
              ? perspective.sourceDomain
              : perspective.url;
          onView?.call(perspectiveId);
          openPerspectiveReader(context, perspective);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title area
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DiffTitle(
                          // No .trim(): highlight offsets are computed server-
                          // side on the untrimmed title, so trimming here would
                          // shift every span by the leading-whitespace count
                          // (frequent on live RSS titles). Story 7.4 (B).
                          title: perspective.title,
                          highlightSpans: perspective.highlightSpans,
                          sharedTokens: perspective.sharedTokens,
                          biasColor: perspective.getBiasColor(colors),
                          baseStyle: textTheme.bodyMedium?.copyWith(
                                color: colors.textPrimary,
                                fontSize:
                                    (textTheme.bodyMedium?.fontSize ?? 14) + 2,
                                height: 1.35,
                              ) ??
                              TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                height: 1.35,
                              ),
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  bottom: 8,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: perspective.getBiasColor(colors),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),

            // Footer — source info, tappable if source found in DB
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: matchedSource != null
                  ? () => _showSourceDetail(context, ref, matchedSource)
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary.withValues(alpha: 0.5),
                  border: Border(
                    top: BorderSide(
                      color: colors.textSecondary.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    // Bias badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: perspective
                            .getBiasColor(colors)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        perspective.getBiasLabel(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: perspective.getBiasColor(colors),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Favicon
                    if (perspective.sourceDomain.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        // Web : proxy backend (CORS) via FacteurImage, sinon le
                        // canvas CanvasKit taint sur l'URL google directe.
                        child: FacteurImage(
                          imageUrl:
                              'https://www.google.com/s2/favicons?domain=${perspective.sourceDomain}&sz=32',
                          width: 14,
                          height: 14,
                          errorWidget: (_) => _buildSourcePlaceholder(colors),
                        ),
                      ),
                    ] else
                      _buildSourcePlaceholder(colors),
                    const SizedBox(width: 6),
                    // Source name
                    Flexible(
                      child: Text(
                        perspective.sourceName,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize:
                              (textTheme.labelMedium?.fontSize ?? 12) - 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Info hint (only if source is tappable)
                    if (matchedSource != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        PhosphorIcons.info(PhosphorIconsStyle.regular),
                        size: 11,
                        color: colors.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          perspective.sourceName.isNotEmpty
              ? perspective.sourceName.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class PerspectivesWarningBadge extends StatelessWidget {
  final FacteurColors colors;
  final TextTheme textTheme;

  const PerspectivesWarningBadge({
    super.key,
    required this.colors,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Comparaison limitée (sujet peu couvert)',
        style: textTheme.labelSmall?.copyWith(color: colors.textTertiary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class PerspectivesEmptyState extends StatelessWidget {
  final FacteurColors colors;
  final TextTheme textTheme;

  const PerspectivesEmptyState({
    super.key,
    required this.colors,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          "Ce sujet n'a pas encore été repris par d'autres médias.",
          style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PerspectivesBiasBar extends StatelessWidget {
  final FacteurColors colors;
  final Map<String, int> mergedDistribution;
  final String sourceBiasStance;
  final String sourceName;
  final Set<String> selectedSegments;
  final void Function(String) onSegmentTap;
  final bool compact;

  const PerspectivesBiasBar({
    super.key,
    required this.colors,
    required this.mergedDistribution,
    required this.sourceBiasStance,
    required this.sourceName,
    required this.selectedSegments,
    required this.onSegmentTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = [
      ('gauche', 'Gauche', colors.biasLeft),
      ('centre', 'Centre', colors.biasCenter),
      ('droite', 'Droite', colors.biasRight),
    ];

    final total = mergedDistribution.values.fold<int>(0, (sum, v) => sum + v);

    final flexValues = <int>[];
    for (final seg in segments) {
      final count = mergedDistribution[seg.$1] ?? 0;
      if (count > 0 && total > 0) {
        final proportion = count / total;
        flexValues.add((proportion * 100).round().clamp(15, 100));
      } else {
        flexValues.add(15);
      }
    }

    final sourceGroup = _toBarGroup(sourceBiasStance);
    final sourceIndex = segments.indexWhere((s) => s.$1 == sourceGroup);

    return Column(
      children: [
        Row(
          children: List.generate(segments.length, (i) {
            final seg = segments[i];
            final count = mergedDistribution[seg.$1] ?? 0;
            final isActive =
                selectedSegments.isEmpty || selectedSegments.contains(seg.$1);
            return Expanded(
              flex: flexValues[i],
              child: GestureDetector(
                onTap:
                    count > 0 && !compact ? () => onSegmentTap(seg.$1) : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isActive ? 1.0 : 0.3,
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: compact
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: seg.$3.withValues(
                                        alpha: count > 0 ? 0.15 : 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        seg.$2,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: count > 0
                                              ? seg.$3
                                              : colors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: count > 0
                              ? seg.$3.withValues(
                                  alpha: count == 1
                                      ? 0.55
                                      : (count == 2 ? 0.8 : 1.0),
                                )
                              : seg.$3.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: count > 0
                              ? Border.all(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  width: 0.8,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        if (sourceIndex >= 0 && sourceBiasStance != 'unknown')
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: compact
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalFlex = flexValues.fold<int>(
                          0,
                          (sum, f) => sum + f,
                        );
                        double offsetFraction = 0;
                        for (int i = 0; i < sourceIndex; i++) {
                          offsetFraction += flexValues[i] / totalFlex;
                        }
                        offsetFraction +=
                            (flexValues[sourceIndex] / totalFlex) / 2;

                        final markerX = constraints.maxWidth * offsetFraction;
                        final sourceColor = segments[sourceIndex].$3;
                        final displayName = sourceName.isNotEmpty
                            ? sourceName
                            : segments[sourceIndex].$2;

                        return SizedBox(
                          height: 28,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: markerX - 5,
                                top: 0,
                                child: CustomPaint(
                                  size: const Size(10, 6),
                                  painter: PerspectivesTrianglePainter(
                                    color: sourceColor,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: (markerX - 50).clamp(
                                  0.0,
                                  constraints.maxWidth - 100,
                                ),
                                top: 10,
                                child: SizedBox(
                                  width: 100,
                                  child: Text(
                                    displayName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: sourceColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

class PerspectivesAnalysisZone extends StatefulWidget {
  final PerspectivesAnalysisState state;
  final String? text;
  final VoidCallback? onRequestAnalysis;
  final FacteurColors colors;
  final TextTheme textTheme;
  final Key? zoneKey;

  const PerspectivesAnalysisZone({
    super.key,
    required this.state,
    this.text,
    required this.onRequestAnalysis,
    required this.colors,
    required this.textTheme,
    this.zoneKey,
  });

  @override
  State<PerspectivesAnalysisZone> createState() =>
      PerspectivesAnalysisZoneState();
}

class PerspectivesAnalysisZoneState extends State<PerspectivesAnalysisZone> {
  bool _isAnalysisExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.state == PerspectivesAnalysisState.idle) {
      return _buildAnalysisCta();
    }

    return AnimatedSize(
      key: widget.zoneKey,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: switch (widget.state) {
        PerspectivesAnalysisState.idle => const SizedBox.shrink(),
        PerspectivesAnalysisState.loading => _buildAnalysisSkeleton(),
        PerspectivesAnalysisState.done => _buildAnalysisResult(),
        PerspectivesAnalysisState.error => _buildAnalysisError(),
      },
    );
  }

  Widget _buildAnalysisCta() {
    return Center(
      child: OutlinedButton.icon(
        onPressed: widget.onRequestAnalysis,
        icon: Icon(
          PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
          size: 18,
          color: widget.colors.primary,
        ),
        label: Text(
          "Lancer l'analyse Facteur",
          style: widget.textTheme.labelLarge?.copyWith(
            color: widget.colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: widget.colors.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildAnalysisSkeleton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ShimmerLine(
              width: i == 2 ? 0.6 : (i == 1 ? 0.9 : 1.0),
              colors: widget.colors,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResult() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.colors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _isAnalysisExpanded = !_isAnalysisExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                  size: 18,
                  color: widget.colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Analyse Facteur',
                  style: widget.textTheme.titleSmall?.copyWith(
                    color: widget.colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _isAnalysisExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                    size: 12,
                    color: widget.colors.primary,
                  ),
                ),
              ],
            ),
          ),
          if (_isAnalysisExpanded) ...[
            const SizedBox(height: 10),
            MarkdownText(
              text: widget.text ?? '',
              style: widget.textTheme.bodySmall!.copyWith(
                color: widget.colors.textPrimary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                kAnalysisDisclaimerText,
                style: widget.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: widget.colors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colors.textSecondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Analyse indisponible',
              style: widget.textTheme.bodySmall?.copyWith(
                color: widget.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.onRequestAnalysis,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Réessayer',
              style: widget.textTheme.labelSmall?.copyWith(
                color: widget.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PerspectivesInlineSection extends ConsumerStatefulWidget {
  final List<Perspective> perspectives;
  final Map<String, int> biasDistribution;
  final List<String> keywords;
  final String sourceBiasStance;
  final String sourceName;
  final String contentId;
  final String comparisonQuality;
  final String? divergenceLevel;

  /// Key attached to the first perspective card so the parent can detect
  /// when the user has scrolled past it.
  final Key? firstCardKey;

  /// Ouvre le bottom sheet « Analyse Facteur » (carte CTA en fin de
  /// carrousel). Géré par l'écran parent.
  final VoidCallback? onOpenAnalysis;

  final PerspectivesSectionStatus status;

  const PerspectivesInlineSection({
    super.key,
    this.perspectives = const [],
    this.biasDistribution = const {},
    this.keywords = const [],
    required this.contentId,
    this.sourceBiasStance = 'unknown',
    this.sourceName = '',
    this.comparisonQuality = 'low',
    this.divergenceLevel,
    this.firstCardKey,
    this.onOpenAnalysis,
    this.status = PerspectivesSectionStatus.ready,
  });

  @override
  ConsumerState<PerspectivesInlineSection> createState() =>
      _PerspectivesInlineSectionState();
}

enum _EmptyStage { none, fading, collapsed }

// ── Timing de la séquence "aucune source trouvée" ──────────────────────────
// Escamotage doux : pause de lecture (message lisible) → fondu → repli de
// hauteur. Pas de glissement latéral (jugé abrupt).
const _kEmptyReadDelay   = Duration(milliseconds: 1800); // pause avant le fade
const _kEmptyFadeDuration = Duration(milliseconds: 450);  // fondu 1 → 0
const _kEmptyInitialOpacity = 1.0;                       // message lisible pendant la pause
// ──────────────────────────────────────────────────────────────────────────

/// Carte placeholder shimmer (gabarit carte réel 248×192) pour le squelette de
/// chargement du carrousel. Reprend l'animation de [CoverageSpectrumBarShimmer].
class _CoverageCardSkeleton extends StatefulWidget {
  const _CoverageCardSkeleton();

  @override
  State<_CoverageCardSkeleton> createState() => _CoverageCardSkeletonState();
}

class _CoverageCardSkeletonState extends State<_CoverageCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final baseColor = colors.textTertiary.withValues(alpha: 0.10);
    final highlightColor = Colors.white.withValues(alpha: 0.30);
    const radius = BorderRadius.all(Radius.circular(16));

    return SizedBox(
      width: 248,
      height: 192,
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = _controller.value * 2.8;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment(-1.4 + offset, 0),
                  end: Alignment(-0.2 + offset, 0),
                  colors: [
                    Colors.transparent,
                    highlightColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(rect);
              },
              child: child,
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );
  }
}

class _PerspectivesInlineSectionState
    extends ConsumerState<PerspectivesInlineSection> {
  Timer? _emptyDismissTimer;
  Timer? _emptyCollapseTimer;
  _EmptyStage _emptyStage = _EmptyStage.none;
  // Incrementé à la transition loading/empty → ready : chaque DiffTitle (porté
  // par CoverageComparisonCard) reçoit ce nombre dans sa Key, ce qui le re-crée
  // et joue sa cascade 1× quand les cartes apparaissent — pas re-déclenchée sur
  // les setState parents.
  int _animationGeneration = 0;

  // Carte 192 + padding vertical (15 haut + 16 bas). La hauteur fixe borne les
  // cartes médias et CTA au même gabarit.
  static const double _kCarouselCardHeight = 192;
  static const double _kCarouselViewportHeight =
      _kCarouselCardHeight + 15 + 16;

  @override
  void initState() {
    super.initState();
    _syncEmptyDismissal();
  }

  @override
  void didUpdateWidget(PerspectivesInlineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      // La cascade DiffTitle se joue 1× à l'arrivée des cartes.
      if (widget.status == PerspectivesSectionStatus.ready &&
          oldWidget.status != PerspectivesSectionStatus.ready) {
        _animationGeneration++;
      }
      _syncEmptyDismissal();
    }
  }

  @override
  void dispose() {
    _emptyDismissTimer?.cancel();
    _emptyCollapseTimer?.cancel();
    super.dispose();
  }

  void _syncEmptyDismissal() {
    _emptyDismissTimer?.cancel();
    _emptyDismissTimer = null;
    _emptyCollapseTimer?.cancel();
    _emptyCollapseTimer = null;

    if (widget.status != PerspectivesSectionStatus.empty) {
      if (_emptyStage != _EmptyStage.none) {
        setState(() => _emptyStage = _EmptyStage.none);
      }
      return;
    }

    if (_emptyStage != _EmptyStage.none) return;
    // Pause de lecture avant de démarrer le fade+slide
    _emptyDismissTimer = Timer(_kEmptyReadDelay, () {
      if (!mounted || widget.status != PerspectivesSectionStatus.empty) return;
      setState(() => _emptyStage = _EmptyStage.fading);
      // Collapse hauteur une fois le fondu terminé
      _emptyCollapseTimer = Timer(_kEmptyFadeDuration, () {
        if (!mounted || widget.status != PerspectivesSectionStatus.empty) {
          return;
        }
        setState(() => _emptyStage = _EmptyStage.collapsed);
      });
    });
  }

  static const _groupOrder = ['gauche', 'centre', 'droite'];

  List<Perspective> get _sortedPerspectives {
    final sorted = [...widget.perspectives];
    sorted.sort(
      (a, b) => _groupOrder
          .indexOf(a.biasGroup)
          .compareTo(_groupOrder.indexOf(b.biasGroup)),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = context.isDarkMode;
    final textTheme = Theme.of(context).textTheme;
    final variants = _sortedPerspectives.take(8).toList();
    final isReady = widget.status == PerspectivesSectionStatus.ready;
    final isEmpty = widget.status == PerspectivesSectionStatus.empty;
    final isLoading = widget.status == PerspectivesSectionStatus.loading;
    final shouldShowBand = !isEmpty || _emptyStage != _EmptyStage.collapsed;
    final label = (isLoading || isEmpty)
        ? 'Couverture médiatique'
        : 'Couverture médiatique (${widget.perspectives.length})';

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: shouldShowBand
          // Disparition empty : fondu doux du bandeau puis repli de la hauteur
          // par l'`AnimatedSize` (pas de glissement latéral).
          ? AnimatedOpacity(
              duration: _kEmptyFadeDuration,
              curve: Curves.easeOut,
              opacity: isEmpty
                  ? (_emptyStage != _EmptyStage.none
                      ? 0
                      : _kEmptyInitialOpacity)
                  : 1,
              // Bande frostée edge-to-edge encastrée : teinte crème assombri
              // translucide (laisse transparaître le parchemin du reader,
              // reste plus foncée que les cartes) + flou verre + hairline
              // chaude très douce haut/bas (creux secondaire, pas d'ombre).
              child: _buildFrostedBand(
                colors: colors,
                isDark: isDark,
                isReady: isReady,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(colors, textTheme, label, isLoading, isEmpty),
                    if (isReady) ...[
                      _buildCarousel(variants),
                      // Libellé de polarisation déplacé SOUS le carrousel
                      // (le header ne porte plus que le titre + la barre).
                      _buildBandFooter(colors, textTheme),
                    ] else if (isLoading) ...[
                      // Squelette plein-format : la bande garde la stature de
                      // l'état prêt (sinon un mince filet « ressemble à un bug »).
                      _buildLoadingSkeleton(),
                    ] else if (isEmpty) ...[
                      _buildEmptyMessage(colors, textTheme),
                    ],
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// Coque verre crème encastrée : la bande s'efface *derrière* le plan de
  /// l'article (secondaire). Teinte crème assombri translucide composée sur le
  /// parchemin de la page ⇒ rendu plus foncé que les cartes article (`surface
  /// #FDFBF7`), qui « popent » du coup. Pas d'ombre portée (elle faisait
  /// flotter/avancer la bande) : seulement une hairline chaude très douce
  /// top + bottom, lue comme un léger creux. Padding interne `(0,16,0,6)`.
  Widget _buildFrostedBand({
    required FacteurColors colors,
    required bool isDark,
    required bool isReady,
    required Widget child,
  }) {
    // Teinte quasi-invisible : à peine ~2 % sous le parchemin de la page. La
    // zone ne se lit plus comme un panneau ; c'est la hairline qui délimite.
    // Clair : crème translucide très léger. Sombre : backgroundPrimary discret.
    final tint = isDark
        ? colors.backgroundPrimary.withValues(alpha: 0.6)
        : const Color.fromRGBO(232, 222, 203, 0.55);
    // Web n'a pas de blur (no-op opaque) → teinte composée plus proche du fond.
    final fallbackColor = isDark
        ? colors.backgroundPrimary
        : const Color.fromRGBO(237, 228, 211, 1);
    // Hairline chaude nette mais fine : c'est la VRAIE séparation (élégante,
    // marquée). Top + bottom, gardée sur isReady.
    final hairlineColor = isDark
        ? Colors.white.withValues(alpha: isReady ? 0.09 : 0)
        : colors.border.withValues(alpha: isReady ? 0.7 : 0);

    return ClipRect(
      // ClipRect (bords droits) borne le BackdropFilter → vrai effet verre.
      child: webBlurFallback(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        fallbackColor: fallbackColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            border: Border(
              top: BorderSide(color: hairlineColor, width: 1),
              bottom: BorderSide(color: hairlineColor, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Header 2 lignes : (titre + barre spectre) / (badge divergence + info).
  Widget _buildHeader(
    FacteurColors colors,
    TextTheme textTheme,
    String label,
    bool isLoading,
    bool isEmpty,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : libellé à gauche (FittedBox scaleDown absorbe les titres
          // longs sans wrap), barre spectre (96 px) épinglée à droite et
          // centrée verticalement sur le titre.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (!isEmpty) ...[
                const SizedBox(width: 11),
                SizedBox(
                  width: 96,
                  child: isLoading
                      ? const CoverageSpectrumBarShimmer()
                      : CoverageSpectrumBar(
                          distribution: widget.biasDistribution,
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Pied de bande, sous le carrousel : libellé de polarisation à gauche +
  /// bouton info (surlignage) à droite. Rendu uniquement quand la couverture
  /// est prête (le `if (isReady)` du parent garantit déjà la condition).
  Widget _buildBandFooter(FacteurColors colors, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: DivergenceInlineBadge(
              divergenceLevel: widget.divergenceLevel,
              scale: 1.45,
            ),
          ),
          const SizedBox(width: 8),
          _HighlightInfoButton(
            colors: colors,
            onTap: () => _showHighlightInfo(context, colors, textTheme),
          ),
        ],
      ),
    );
  }

  /// Carrousel horizontal : cartes de couverture (gap 13) + carte CTA Analyse
  /// en fin de course. Viewport à hauteur fixe → cartes équi-hauteur.
  Widget _buildCarousel(List<Perspective> variants) {
    return SizedBox(
      height: _kCarouselViewportHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < variants.length; i++) ...[
              if (i > 0) const SizedBox(width: 13),
              CoverageComparisonCard(
                key: ValueKey('coverage_${_animationGeneration}_$i'),
                perspective: variants[i],
                firstCardKey: i == 0 ? widget.firstCardKey : null,
              ),
            ],
            if (variants.isNotEmpty) const SizedBox(width: 13),
            _AnalysisCtaCard(
              onTap: widget.onOpenAnalysis,
              count: widget.perspectives.length,
            ),
          ],
        ),
      ),
    );
  }

  /// Squelette du carrousel pendant le chargement : 2 cartes placeholder au
  /// gabarit réel (248×192) avec shimmer, dans le même viewport à hauteur fixe
  /// que l'état prêt → la bande ne se réduit pas à un filet.
  Widget _buildLoadingSkeleton() {
    return const SizedBox(
      height: _kCarouselViewportHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18, 15, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CoverageCardSkeleton(),
            SizedBox(width: 13),
            _CoverageCardSkeleton(),
          ],
        ),
      ),
    );
  }

  /// Corps de l'état vide : message explicite, lisible pendant la pause de
  /// lecture avant l'escamotage en fondu.
  Widget _buildEmptyMessage(FacteurColors colors, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Text(
        "Pas d'autre source trouvée",
        textAlign: TextAlign.center,
        style: textTheme.bodySmall?.copyWith(
          color: colors.textTertiary,
        ),
      ),
    );
  }

  void _showHighlightInfo(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: colors.backgroundPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.comparisonQuality == 'low') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.warning(PhosphorIconsStyle.regular),
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Comparaison limitée — sujet peu couvert par les médias',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                Icon(
                  PhosphorIcons.chartBar(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Niveau de polarisation',
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              kDivergenceExplanationText,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Divider(
              color: colors.textSecondary.withValues(alpha: 0.1),
              height: 1,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  PhosphorIcons.highlighter(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Surlignage',
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              kHighlightIntroText,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightInfoButton extends StatelessWidget {
  final FacteurColors colors;
  final VoidCallback onTap;

  const _HighlightInfoButton({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Surlignage',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(
        PhosphorIcons.info(PhosphorIconsStyle.regular),
        size: 17,
        color: colors.textSecondary,
      ),
    );
  }
}

/// RichText avec wash gris autour du pivot (si fourni). Utilisé pour signaler
/// le token-pivot du titre de référence dans le reader.
class PivotWashTitle extends StatefulWidget {
  final String title;
  final TokenSpan? pivot;
  final TextStyle? textStyle;
  final bool animate;
  final int? maxLines;

  const PivotWashTitle({
    super.key,
    required this.title,
    required this.pivot,
    this.textStyle,
    this.animate = true,
    this.maxLines,
  });

  @override
  State<PivotWashTitle> createState() => _PivotWashTitleState();
}

class _PivotWashTitleState extends State<PivotWashTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.pivot != null && widget.animate) {
      Future.delayed(DiffTitle.kStartDelay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(PivotWashTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.pivot != widget.pivot ||
        oldWidget.animate != widget.animate) {
      if (widget.pivot != null && widget.animate) {
        _controller.value = 0;
        Future.delayed(DiffTitle.kStartDelay, () {
          if (mounted) _controller.forward();
        });
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final titleStyle = widget.textStyle ??
        GoogleFonts.fraunces(
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
          height: 1.3,
        );
    final pivot = widget.pivot;
    if (pivot == null) {
      return Text(widget.title, style: titleStyle, maxLines: widget.maxLines);
    }
    final titleLen = widget.title.length;
    final start = pivot.start.clamp(0, titleLen);
    final end = pivot.end.clamp(start, titleLen);
    if (end == start) {
      return Text(widget.title, style: titleStyle, maxLines: widget.maxLines);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        final washColor = const Color(0xFF9E9E9E).withValues(alpha: 0.14 * t);
        return RichText(
          maxLines: widget.maxLines,
          text: TextSpan(
            style: titleStyle,
            children: [
              if (start > 0) TextSpan(text: widget.title.substring(0, start)),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: washColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.title.substring(start, end),
                    style: titleStyle,
                  ),
                ),
              ),
              if (end < titleLen) TextSpan(text: widget.title.substring(end)),
            ],
          ),
        );
      },
    );
  }
}

/// Carte CTA « Analyse Facteur » en fin de carrousel — gabarit gradient ocre.
/// Tap → ouvre le bottom sheet d'analyse (`onTap`, géré par l'écran parent).
class _AnalysisCtaCard extends StatelessWidget {
  final VoidCallback? onTap;
  final int count;

  const _AnalysisCtaCard({required this.onTap, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: 190,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFBEFE3), Color(0xFFF4DEC8)],
            ),
            border: Border.all(color: colors.primary.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
          // FittedBox(scaleDown) : la carte vit dans un viewport à hauteur
          // fixe ; si les métriques de police (tests, gros textScale) gonflent
          // le contenu, on le réduit au lieu d'overflow.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 160,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.primary.withValues(alpha: 0.14),
                          Colors.white,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                        size: 19,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Analyse Facteur',
                      style: GoogleFonts.fraunces(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Une synthèse neutre des $count angles, en quelques '
                      'secondes.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        height: 1.45,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lancer',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                          size: 14,
                          color: colors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom sheet « Analyse Facteur » (reskin du texte `analysis` existant) ───

/// État réactif poussé au bottom sheet d'analyse par l'écran parent.
class AnalysisSheetData {
  final PerspectivesAnalysisState state;
  final String? text;

  const AnalysisSheetData({
    this.state = PerspectivesAnalysisState.idle,
    this.text,
  });
}

/// Découpe le texte d'analyse en (essentiel partagé, là où ça diverge) sur le
/// **1ᵉʳ `\n\n`**. Absent → essentiel vide, tout sous « divergent ». Trim.
({String essentiel, String divergent}) splitAnalysisSections(String raw) {
  final idx = raw.indexOf('\n\n');
  if (idx < 0) return (essentiel: '', divergent: raw.trim());
  return (
    essentiel: raw.substring(0, idx).trim(),
    divergent: raw.substring(idx + 2).trim(),
  );
}

/// Ouvre le bottom sheet d'analyse. Scrim `rgba(20,16,12,.52)` sans blur ;
/// reduced-motion → coupe l'anim de montée. Le contenu réagit aux transitions
/// loading → done/error via `data`.
Future<void> showAnalysisBottomSheet({
  required BuildContext context,
  required ValueListenable<AnalysisSheetData> data,
  required List<Perspective> perspectives,
  required VoidCallback onRetry,
}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color.fromARGB(133, 20, 16, 12),
    sheetAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
    builder: (sheetContext) => _AnalysisSheet(
      data: data,
      perspectives: perspectives,
      onRetry: onRetry,
    ),
  );
}

class _AnalysisSheet extends StatelessWidget {
  final ValueListenable<AnalysisSheetData> data;
  final List<Perspective> perspectives;
  final VoidCallback onRetry;

  const _AnalysisSheet({
    required this.data,
    required this.perspectives,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.86),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header fixe ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            colors.primary.withValues(alpha: 0.13),
                            Colors.white,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                          size: 21,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Analyse Facteur',
                              style: GoogleFonts.fraunces(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                height: 1.12,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Synthèse neutre · ${perspectives.length} médias',
                              style: GoogleFonts.courierPrime(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: colors.textPrimary.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            PhosphorIcons.x(PhosphorIconsStyle.regular),
                            size: 15,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.07),
                ),
              ],
            ),
          ),
          // ── Contenu réactif ──
          Flexible(
            child: ValueListenableBuilder<AnalysisSheetData>(
              valueListenable: data,
              builder: (context, value, _) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
                  child: _buildContent(context, colors, textTheme, value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
    AnalysisSheetData value,
  ) {
    switch (value.state) {
      case PerspectivesAnalysisState.idle:
      case PerspectivesAnalysisState.loading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ShimmerLine(
                width: i == 2 ? 0.6 : (i == 1 ? 0.9 : 1.0),
                colors: colors,
              ),
            ],
          ],
        );
      case PerspectivesAnalysisState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analyse indisponible',
              style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Réessayer',
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      case PerspectivesAnalysisState.done:
        final (:essentiel, :divergent) =
            splitAnalysisSections(value.text ?? '');
        final bodyStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: 14.5,
          height: 1.62,
          color: colors.textPrimary,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (essentiel.isNotEmpty) ...[
              _sectionTitle("1 · L'ESSENTIEL PARTAGÉ", colors),
              const SizedBox(height: 7),
              MarkdownText(text: essentiel, style: bodyStyle),
              const SizedBox(height: 18),
            ],
            if (divergent.isNotEmpty) ...[
              _sectionTitle('2 · LÀ OÙ LES MÉDIAS DIVERGENT', colors),
              const SizedBox(height: 7),
              MarkdownText(text: divergent, style: bodyStyle),
              const SizedBox(height: 18),
            ],
            // DÉSACTIVÉ (T1) : section « 3 · LE VOCABULAIRE QUI SÉPARE » retirée
            // (dérivée du highlighting des biais, désormais coupé). Sections 1 &
            // 2 (prose Analyse Facteur) + disclaimer conservés.
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.07),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIcons.info(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kAnalysisDisclaimerText,
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.5,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _sectionTitle(String text, FacteurColors colors) {
    return Text(
      text,
      style: GoogleFonts.courierPrime(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: colors.primary,
      ),
    );
  }
}
