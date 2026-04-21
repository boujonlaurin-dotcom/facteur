import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_detail_modal.dart';
import '../../digest/widgets/markdown_text.dart';
import '../providers/feed_provider.dart';

/// Model for a perspective from an external source
class Perspective {
  final String title;
  final String url;
  final String sourceName;
  final String sourceDomain;
  final String biasStance;
  final String? publishedAt;

  Perspective({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceDomain,
    required this.biasStance,
    this.publishedAt,
  });

  factory Perspective.fromJson(Map<String, dynamic> json) {
    return Perspective(
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      sourceName: (json['source_name'] as String?) ?? 'Unknown',
      sourceDomain: (json['source_domain'] as String?) ?? '',
      biasStance: (json['bias_stance'] as String?) ?? 'unknown',
      publishedAt: json['published_at'] as String?,
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

  String getBiasLabel() {
    switch (biasStance) {
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

/// Bottom sheet to display alternative perspectives
class PerspectivesBottomSheet extends ConsumerStatefulWidget {
  final List<Perspective> perspectives;
  final Map<String, int> biasDistribution;
  final List<String> keywords;
  final String sourceBiasStance;
  final String sourceName;
  final String contentId;
  final String comparisonQuality;

  const PerspectivesBottomSheet({
    super.key,
    required this.perspectives,
    required this.biasDistribution,
    required this.keywords,
    required this.contentId,
    this.sourceBiasStance = 'unknown',
    this.sourceName = '',
    this.comparisonQuality = 'low',
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

  static const _groupOrder = ['gauche', 'centre', 'droite'];

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
    sorted.sort((a, b) => _groupOrder
        .indexOf(a.biasGroup)
        .compareTo(_groupOrder.indexOf(b.biasGroup)));
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

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filteredPerspectives;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
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
                                  'Voir tous les points de vue',
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
                                    PhosphorIcons.x(PhosphorIconsStyle.bold)),
                                onPressed: () => Navigator.pop(context),
                                color: colors.textSecondary,
                              ),
                            ],
                          ),
                          if (widget.comparisonQuality == 'low')
                            PerspectivesWarningBadge(
                                colors: colors, textTheme: textTheme),
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
                                          () => _selectedSegments = {}),
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
                                                PhosphorIconsStyle.bold),
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
                    ...filtered.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PerspectiveCard(perspective: p),
                      ),
                    ),
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
                              'Voir tous les points de vue',
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
                            icon:
                                Icon(PhosphorIcons.x(PhosphorIconsStyle.bold)),
                            onPressed: () => Navigator.pop(context),
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PerspectivesEmptyState(
                        colors: colors, textTheme: textTheme),
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
              color: widget.colors.textSecondary
                  .withValues(alpha: 0.08 + 0.08 * _controller.value),
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

  const _PerspectiveCard({required this.perspective});

  /// Find matching Source from user sources by domain
  Source? _findSource(List<Source> sources) {
    final domain = perspective.sourceDomain.toLowerCase();
    if (domain.isEmpty) return null;
    return sources.cast<Source?>().firstWhere(
      (s) {
        if (s?.url == null) return false;
        final uri = Uri.tryParse(s!.url!);
        if (uri == null) return false;
        final host = uri.host.toLowerCase().replaceFirst('www.', '');
        return host == domain || host == 'www.$domain';
      },
      orElse: () => null,
    );
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
        onTap: () async {
          final uri = Uri.parse(perspective.url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                        child: Text(
                          perspective.title
                              .replaceAll(RegExp(r'\s*[-–|]\s*[^-–|]+$'), '')
                              .trim(),
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                            fontSize:
                                (textTheme.bodyMedium?.fontSize ?? 14) + 1,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        PhosphorIcons.arrowSquareOut(
                            PhosphorIconsStyle.regular),
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
                          horizontal: 6, vertical: 2),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '⚠️ Comparaison limitée (sujet peu couvert)',
          style: textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: colors.textTertiary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.newspaperClipping(PhosphorIconsStyle.duotone),
              size: 48,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Sujet peu couvert',
                style: textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "Ce sujet n'a pas encore été repris par d'autres médias.",
                style:
                    textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
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

  const PerspectivesBiasBar({
    super.key,
    required this.colors,
    required this.mergedDistribution,
    required this.sourceBiasStance,
    required this.sourceName,
    required this.selectedSegments,
    required this.onSegmentTap,
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
                onTap: count > 0 ? () => onSegmentTap(seg.$1) : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isActive ? 1.0 : 0.3,
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: seg.$3
                                .withValues(alpha: count > 0 ? 0.15 : 0.05),
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
                                color: count > 0 ? seg.$3 : colors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
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
                                      : (count == 2 ? 0.8 : 1.0))
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
        if (sourceIndex >= 0 && sourceBiasStance != 'unknown') ...[
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final totalFlex = flexValues.fold<int>(0, (sum, f) => sum + f);
              double offsetFraction = 0;
              for (int i = 0; i < sourceIndex; i++) {
                offsetFraction += flexValues[i] / totalFlex;
              }
              offsetFraction += (flexValues[sourceIndex] / totalFlex) / 2;

              final markerX = constraints.maxWidth * offsetFraction;
              final sourceColor = segments[sourceIndex].$3;
              final displayName =
                  sourceName.isNotEmpty ? sourceName : segments[sourceIndex].$2;

              return SizedBox(
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: markerX - 7,
                      top: 0,
                      child: CustomPaint(
                        size: const Size(14, 8),
                        painter:
                            PerspectivesTrianglePainter(color: sourceColor),
                      ),
                    ),
                    Positioned(
                      left:
                          (markerX - 50).clamp(0.0, constraints.maxWidth - 100),
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
        ],
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        border:
            Border.all(color: widget.colors.primary.withValues(alpha: 0.15)),
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
                'Analyse Facteur',
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

  /// Controlled mode: when provided, the parent owns the filter state.
  final Set<String>? externalSelectedSegments;
  final void Function(String)? onSegmentTap;
  final VoidCallback? onClearSegments;

  /// Analysis state controlled by the parent screen.
  final PerspectivesAnalysisState analysisState;
  final String? analysisText;
  final VoidCallback? onRequestAnalysis;

  /// Key attached to the analysis result zone so the parent can scroll to it.
  final Key? analysisZoneKey;

  const PerspectivesInlineSection({
    super.key,
    required this.perspectives,
    required this.biasDistribution,
    required this.keywords,
    required this.contentId,
    this.sourceBiasStance = 'unknown',
    this.sourceName = '',
    this.comparisonQuality = 'low',
    this.externalSelectedSegments,
    this.onSegmentTap,
    this.onClearSegments,
    this.analysisState = PerspectivesAnalysisState.idle,
    this.analysisText,
    this.onRequestAnalysis,
    this.analysisZoneKey,
  });

  @override
  ConsumerState<PerspectivesInlineSection> createState() =>
      _PerspectivesInlineSectionState();
}

class _PerspectivesInlineSectionState
    extends ConsumerState<PerspectivesInlineSection> {
  Set<String> _selectedSegments = {};

  Set<String> get _effectiveSegments =>
      widget.externalSelectedSegments ?? _selectedSegments;

  static const _groupOrder = ['gauche', 'centre', 'droite'];

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
    sorted.sort((a, b) => _groupOrder
        .indexOf(a.biasGroup)
        .compareTo(_groupOrder.indexOf(b.biasGroup)));
    return sorted;
  }

  List<Perspective> get _filteredPerspectives {
    final sorted = _sortedPerspectives;
    if (_effectiveSegments.isEmpty) return sorted;
    return sorted
        .where((p) => _effectiveSegments.contains(p.biasGroup))
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

  void _handleSegmentTap(String key) {
    if (widget.onSegmentTap != null) {
      widget.onSegmentTap!(key);
    } else {
      _onSegmentTapInternal(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filteredPerspectives;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.perspectives.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIcons.eye(PhosphorIconsStyle.regular),
                      color: colors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Voir tous les points de vue',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          fontSize: (textTheme.titleMedium?.fontSize ?? 16) + 1,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.comparisonQuality == 'low')
                  PerspectivesWarningBadge(
                      colors: colors, textTheme: textTheme),
                const SizedBox(height: 16),
                PerspectivesBiasBar(
                  colors: colors,
                  mergedDistribution: _mergedDistribution,
                  sourceBiasStance: widget.sourceBiasStance,
                  sourceName: widget.sourceName,
                  selectedSegments: _effectiveSegments,
                  onSegmentTap: _handleSegmentTap,
                ),
                SizedBox(
                  height: 20,
                  child: _effectiveSegments.isNotEmpty
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              if (widget.onClearSegments != null) {
                                widget.onClearSegments!();
                              } else {
                                setState(() => _selectedSegments = {});
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tout afficher',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  PhosphorIcons.x(PhosphorIconsStyle.bold),
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
          ...filtered.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PerspectiveCard(perspective: p),
            ),
          ),
          if (widget.analysisState != PerspectivesAnalysisState.idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PerspectivesAnalysisZone(
                state: widget.analysisState,
                text: widget.analysisText,
                onRequestAnalysis: widget.onRequestAnalysis,
                colors: colors,
                textTheme: textTheme,
                zoneKey: widget.analysisZoneKey,
              ),
            ),
          if (widget.analysisState == PerspectivesAnalysisState.idle)
            const SizedBox(height: 32),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIcons.eye(PhosphorIconsStyle.regular),
                  color: colors.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Voir tous les points de vue',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      fontSize: (textTheme.titleMedium?.fontSize ?? 16) + 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PerspectivesEmptyState(colors: colors, textTheme: textTheme),
        ],
      ],
    );
  }
}
