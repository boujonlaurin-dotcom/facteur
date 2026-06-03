import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../digest/widgets/divergence_inline_badge.dart';
import '../../digest/widgets/markdown_text.dart';
import '../../digest/widgets/section_divider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_detail_modal.dart';
import '../providers/feed_provider.dart';
import '../repositories/feed_repository.dart' show HighlightSpan, TokenSpan;
import 'coverage_spectrum_bar.dart';
import 'diff_title.dart';

/// Texte d'introduction expliquant le surlignage. Affiché dans le bottom-sheet
/// modal ET derrière le bouton info de la section inline du reader d'article
/// — single source of truth pour les deux vues.
const String kHighlightIntroText =
    'Le surlignage met en évidence les termes qui '
    'marquent l\'angle éditorial : plus le surlignage '
    'est intense, plus le choix de mot est éditorialisé.';

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
void _openPerspectiveWebView(BuildContext context, Perspective p) {
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
    final rawHighlights = json['highlight_spans'] as List<dynamic>?;
    final rawShared = json['shared_tokens'] as List<dynamic>?;
    return Perspective(
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      sourceName: (json['source_name'] as String?) ?? 'Unknown',
      sourceDomain: (json['source_domain'] as String?) ?? '',
      biasStance: (json['bias_stance'] as String?) ?? 'unknown',
      publishedAt: json['published_at'] as String?,
      highlightSpans: rawHighlights == null
          ? const []
          : rawHighlights
              .map((e) => HighlightSpan.fromJson(e as Map<String, dynamic>))
              .toList(),
      sharedTokens: rawShared == null
          ? const []
          : rawShared
              .map((e) => TokenSpan.fromJson(e as Map<String, dynamic>))
              .toList(),
      language: json['language'] as String?,
    );
  }

  Color getBiasColor(FacteurColors colors) {
    switch (biasStance) {
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
          _openPerspectiveWebView(context, perspective);
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
                          title: perspective.title.trim(),
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
                        child: Image.network(
                          'https://www.google.com/s2/favicons?domain=${perspective.sourceDomain}&sz=32',
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) =>
                              _buildSourcePlaceholder(colors),
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
                'Analyse générée par Mistral Large · l\'IA peut faire des erreurs.',
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

  /// Controlled mode: when provided, the parent owns the filter state.
  /// Préservé pour compatibilité avec le call-site existant — non utilisé
  /// par la refonte hi-fi (le spectrum 5-segs est en lecture seule).
  final Set<String>? externalSelectedSegments;
  final void Function(String)? onSegmentTap;
  final VoidCallback? onClearSegments;

  /// Analysis state controlled by the parent screen.
  final PerspectivesAnalysisState analysisState;
  final String? analysisText;
  final VoidCallback? onRequestAnalysis;

  /// Key attached to the analysis result zone so the parent can scroll to it.
  final Key? analysisZoneKey;

  /// Key attached to the first perspective card so the parent can detect
  /// when the user has scrolled past it.
  final Key? firstCardKey;

  /// Whether the section body is expanded. Controlled by the parent.
  final bool isExpanded;

  /// Called when the user taps the header to toggle collapse/expand.
  final VoidCallback onToggle;

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
    this.externalSelectedSegments,
    this.onSegmentTap,
    this.onClearSegments,
    this.analysisState = PerspectivesAnalysisState.idle,
    this.analysisText,
    this.onRequestAnalysis,
    this.analysisZoneKey,
    this.firstCardKey,
    this.isExpanded = true,
    required this.onToggle,
    this.status = PerspectivesSectionStatus.ready,
  });

  @override
  ConsumerState<PerspectivesInlineSection> createState() =>
      _PerspectivesInlineSectionState();
}

enum _EmptyStage { none, fading, collapsed }

// ── Timing de la séquence "aucune source trouvée" ──────────────────────────
// Ajuster ces 4 valeurs pour calibrer l'animation :
const _kEmptyReadDelay   = Duration(milliseconds: 1500); // pause avant le fade
const _kEmptyFadeDuration = Duration(milliseconds: 800);  // fade 0.28 → 0
const _kEmptySlideDuration = Duration(milliseconds: 960); // glissement vers la droite
const _kEmptyInitialOpacity = 0.28;                       // opacité pendant la pause
// ──────────────────────────────────────────────────────────────────────────

class _PerspectivesInlineSectionState
    extends ConsumerState<PerspectivesInlineSection> {
  double _rotationTurns = 0.0;
  Timer? _emptyDismissTimer;
  Timer? _emptyCollapseTimer;
  _EmptyStage _emptyStage = _EmptyStage.none;
  // Incrementé à chaque transition replié → ouvert : chaque DiffTitle reçoit
  // ce nombre dans sa Key, ce qui le re-crée et relance sa cascade. Garantit
  // que l'animation est jouée 1× par ouverture et pas re-déclenchée sur les
  // setState parents (filter, analysis, etc.).
  int _animationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _rotationTurns = widget.isExpanded ? 0.5 : 0.0;
    _syncEmptyDismissal();
  }

  @override
  void didUpdateWidget(PerspectivesInlineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      _rotationTurns += 0.5;
      if (widget.isExpanded) {
        _animationGeneration++;
      }
    }
    if (widget.status != oldWidget.status) {
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
      // Collapse hauteur une fois le slide terminé
      _emptyCollapseTimer = Timer(_kEmptySlideDuration, () {
        if (!mounted || widget.status != PerspectivesSectionStatus.empty) return;
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

  List<Perspective> get _filteredPerspectives {
    final sorted = _sortedPerspectives;
    final selected = widget.externalSelectedSegments;
    if (selected == null || selected.isEmpty) return sorted;
    return sorted.where((p) => selected.contains(p.biasGroup)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final variants = _filteredPerspectives.take(8).toList();
    final isReady = widget.status == PerspectivesSectionStatus.ready;
    final isEmpty = widget.status == PerspectivesSectionStatus.empty;
    final shouldShowHeader = !isEmpty || _emptyStage != _EmptyStage.collapsed;
    final label = widget.status == PerspectivesSectionStatus.loading
        ? 'Couverture médiatique'
        : 'Couverture médiatique (${widget.perspectives.length})';
    final labelColor = colors.textPrimary;
    final shouldShowBody = isReady && widget.isExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Bandeau cm-panel-inline : hairlines + label + spectrum + count + caret ──
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: shouldShowHeader
              // Disparition empty : à la fin du fade, le bandeau glisse vers la
              // droite hors écran avant que l'`AnimatedSize` ne replie la
              // hauteur — sortie franche plutôt qu'un simple collapse vertical.
              ? AnimatedSlide(
                  duration: _kEmptySlideDuration,
                  curve: Curves.easeOutCubic,
                  offset: isEmpty && _emptyStage != _EmptyStage.none
                      ? const Offset(1.1, 0)
                      : Offset.zero,
                  // Fondu front-loadé : disparaît progressivement avant que le
                  // slide ne s'amorce.
                  child: AnimatedOpacity(
                    duration: _kEmptyFadeDuration,
                    curve: Curves.easeOut,
                    opacity: isEmpty ? (_emptyStage != _EmptyStage.none ? 0 : _kEmptyInitialOpacity) : 1,
                    child: GestureDetector(
                      onTap: isReady ? widget.onToggle : null,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Colors.black.withValues(
                                alpha: isReady ? 0.08 : 0,
                              ),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Colors.black.withValues(
                                alpha: isReady ? 0.08 : 0,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: labelColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isEmpty) ...[
                              const SizedBox(width: 12),
                              if (widget.status ==
                                  PerspectivesSectionStatus.loading)
                                const CoverageSpectrumBarShimmer()
                              else
                                CoverageSpectrumBar(
                                  distribution: widget.biasDistribution,
                                ),
                            ],
                            if (isReady) ...[
                              const SizedBox(width: 10),
                              AnimatedRotation(
                                turns: _rotationTurns,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  PhosphorIcons.caretDown(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  size: 14,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: shouldShowBody
              ? _buildExpandedBody(colors, textTheme, variants)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildExpandedBody(
    FacteurColors colors,
    TextTheme textTheme,
    List<Perspective> variants,
  ) {
    final hasDivergenceBadge = widget.divergenceLevel != null;
    final shouldShowIntroInfo = variants.isNotEmpty;
    final shouldShowToolsRow = hasDivergenceBadge || shouldShowIntroInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shouldShowToolsRow)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: hasDivergenceBadge
                      // scaleDown : pleine taille (+45 %) quand ça rentre, se
                      // réduit gracieusement pour le label long « low » sur les
                      // largeurs serrées plutôt que d'overflow.
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: DivergenceInlineBadge(
                            divergenceLevel: widget.divergenceLevel,
                            scale: 1.45,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (shouldShowIntroInfo)
                  _HighlightInfoButton(
                    colors: colors,
                    onTap: () => _showHighlightInfo(context, colors, textTheme),
                  ),
              ],
            ),
          ),
        for (var i = 0; i < variants.length; i++)
          _VariantRow(
            key: ValueKey('variant_${_animationGeneration}_$i'),
            firstCardKey: i == 0 ? widget.firstCardKey : null,
            perspective: variants[i],
            isLast: i == variants.length - 1,
          ),
        if (widget.analysisState == PerspectivesAnalysisState.idle)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: _AnalysisCtaCard(
              onTap: widget.onRequestAnalysis,
              state: widget.analysisState,
            ),
          ),
        if (widget.analysisState != PerspectivesAnalysisState.idle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: PerspectivesAnalysisZone(
              state: widget.analysisState,
              text: widget.analysisText,
              onRequestAnalysis: widget.onRequestAnalysis,
              colors: colors,
              textTheme: textTheme,
              zoneKey: widget.analysisZoneKey,
            ),
          ),
        const SizedBox(height: 16),
      ],
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

/// Ligne variante (cm-vrow) — border-left 4 px couleur bias + DiffTitle animé
/// suivi d'une foot row (favicon + nom + bias label + arrow).
class _VariantRow extends ConsumerWidget {
  final Perspective perspective;
  final bool isLast;
  final Key? firstCardKey;

  const _VariantRow({
    super.key,
    required this.perspective,
    required this.isLast,
    this.firstCardKey,
  });

  String _biasLabel() {
    switch (perspective.biasStance) {
      case 'left':
        return 'GAUCHE';
      case 'center-left':
        return 'CENTRE-G';
      case 'center':
        return 'CENTRE';
      case 'center-right':
        return 'CENTRE-D';
      case 'right':
        return 'DROITE';
      default:
        return 'SOURCE';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final biasColor = perspective.getBiasColor(colors);
    return InkWell(
      key: firstCardKey,
      onTap: () => _openPerspectiveWebView(context, perspective),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: biasColor, width: 4),
            bottom: isLast
                ? BorderSide.none
                : BorderSide(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiffTitle(
              title: perspective.title,
              highlightSpans: perspective.highlightSpans,
              sharedTokens: perspective.sharedTokens,
              biasColor: biasColor,
              baseStyle: textTheme.bodyMedium?.copyWith(
                    fontSize: 15.5,
                    height: 1.35,
                    color: colors.textPrimary,
                  ) ??
                  TextStyle(fontSize: 15.5, color: colors.textPrimary),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (perspective.sourceDomain.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      'https://www.google.com/s2/favicons?domain=${perspective.sourceDomain}&sz=64',
                      width: 20,
                      height: 20,
                      errorBuilder: (_, __, ___) => _SourceFallback(
                        name: perspective.sourceName,
                        colors: colors,
                      ),
                    ),
                  )
                else
                  _SourceFallback(name: perspective.sourceName, colors: colors),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    perspective.sourceName,
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _biasLabel(),
                  style: GoogleFonts.courierPrime(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: biasColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceFallback extends StatelessWidget {
  final String name;
  final FacteurColors colors;
  const _SourceFallback({required this.name, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// CTA Analyse Facteur — card dashed border, déprioritée. Affiché tant que
/// l'analyse est `idle` ; les états loading/done/error sont rendus par
/// [`PerspectivesAnalysisZone`] (qui prend la place visuelle).
class _AnalysisCtaCard extends StatelessWidget {
  final VoidCallback? onTap;
  final PerspectivesAnalysisState state;

  const _AnalysisCtaCard({required this.onTap, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state != PerspectivesAnalysisState.idle) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: Colors.black.withValues(alpha: 0.12),
          radius: 12,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.sparkle(PhosphorIconsStyle.regular),
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Analyse Facteur',
                      style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Synthèse approfondie en quelques secondes',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Lancer →',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = _dashPath(path, dashWidth: 4, gapWidth: 4);
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(
    Path source, {
    required double dashWidth,
    required double gapWidth,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dashWidth : gapWidth);
        if (draw) {
          out.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        distance = next;
        draw = !draw;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
