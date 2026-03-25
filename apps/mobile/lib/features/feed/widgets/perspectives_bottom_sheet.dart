import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_detail_modal.dart';
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

/// Stance group order and labels for grouped display
const _stanceGroups = [
  ('gauche', 'Gauche'),
  ('centre', 'Centre'),
  ('droite', 'Droite'),
];

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

enum _AnalysisState { idle, loading, done, error }

class _PerspectivesBottomSheetState extends ConsumerState<PerspectivesBottomSheet> {
  /// Active filter: 'gauche', 'centre', 'droite', or null (show all)
  String? _activeBiasFilter;

  /// Analysis state
  _AnalysisState _analysisState = _AnalysisState.idle;
  String? _analysisText;
  bool _isAnalysisExpanded = true;

  List<Perspective> get _filteredPerspectives {
    if (_activeBiasFilter == null) return widget.perspectives;
    return widget.perspectives
        .where((p) => p.biasGroup == _activeBiasFilter)
        .toList();
  }

  /// Compute merged 3-segment distribution from the 5-segment API data
  Map<String, int> get _mergedDistribution {
    final dist = widget.biasDistribution;
    return {
      'gauche': (dist['left'] ?? 0) + (dist['center-left'] ?? 0),
      'centre': dist['center'] ?? 0,
      'droite': (dist['center-right'] ?? 0) + (dist['right'] ?? 0),
    };
  }

  /// Whether to show grouped layout (>= 3 perspectives and >= 2 distinct groups)
  bool get _shouldGroup {
    if (widget.perspectives.length < 3) return false;
    final groups = widget.perspectives.map((p) => p.biasGroup).toSet();
    return groups.length >= 2;
  }

  Future<void> _requestAnalysis() async {
    setState(() => _analysisState = _AnalysisState.loading);

    try {
      final repository = ref.read(feedRepositoryProvider);

      final result = await repository.analyzePerspectives(widget.contentId);
      if (!mounted) return;

      setState(() {
        _analysisText = result;
        _analysisState =
            result != null ? _AnalysisState.done : _AnalysisState.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _analysisState = _AnalysisState.error);
    }
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
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.eye(PhosphorIconsStyle.fill),
                  color: colors.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voir tous les points de vue',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          fontSize: (textTheme.titleMedium?.fontSize ?? 16) + 1,
                        ),
                      ),
                      Text(
                        '(${widget.keywords.join(', ')})',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: (textTheme.labelSmall?.fontSize ?? 11) + 1,
                        ),
                      ),
                      if (widget.comparisonQuality == 'low')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
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
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold)),
                  onPressed: () => Navigator.pop(context),
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),

          // Bias Bar (hidden when empty)
          if (widget.perspectives.isNotEmpty) _buildBiasBar(context, colors),

          // Analysis zone (between bias bar and list)
          if (widget.perspectives.isNotEmpty)
            _buildAnalysisZone(context, colors, textTheme),

          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.backgroundPrimary,
                  colors.backgroundPrimary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),

          // Perspectives List
          Flexible(
            child: filtered.isEmpty
                ? _buildEmptyState(context, colors, textTheme)
                : _shouldGroup
                    ? _buildGroupedList(context, colors, textTheme,
                        widget.perspectives)
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _PerspectiveCard(
                              perspective: filtered[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisZone(
      BuildContext context, FacteurColors colors, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: switch (_analysisState) {
          _AnalysisState.idle => _buildAnalysisCta(colors, textTheme),
          _AnalysisState.loading => _buildAnalysisSkeleton(colors),
          _AnalysisState.done => _buildAnalysisResult(colors, textTheme),
          _AnalysisState.error => _buildAnalysisError(colors, textTheme),
        },
      ),
    );
  }

  Widget _buildAnalysisCta(FacteurColors colors, TextTheme textTheme) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: _requestAnalysis,
        icon: Icon(
          PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
          size: 18,
          color: colors.primary,
        ),
        label: Text(
          'Analyser les divergences',
          style: textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildAnalysisSkeleton(FacteurColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ShimmerLine(
              width: i == 2 ? 0.6 : (i == 1 ? 0.9 : 1.0),
              colors: colors,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResult(FacteurColors colors, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
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
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Analyse IA',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.primary,
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
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
          if (_isAnalysisExpanded) ...[
            const SizedBox(height: 8),
            Text(
              _analysisText ?? '',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Généré via Mistral',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: colors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisError(FacteurColors colors, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.textSecondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Analyse indisponible',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: _requestAnalysis,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Réessayer',
              style: textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(BuildContext context, FacteurColors colors,
      TextTheme textTheme, List<Perspective> perspectives) {
    // Group perspectives by stance
    final groups = <String, List<Perspective>>{};
    for (final p in perspectives) {
      groups.putIfAbsent(p.biasGroup, () => []).add(p);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in _stanceGroups)
          if (groups.containsKey(entry.$1)) ...[
            // Section header (tappable toggle collapse/expand)
            () {
              final isExpanded =
                  _activeBiasFilter == null || _activeBiasFilter == entry.$1;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_activeBiasFilter == entry.$1) {
                        _activeBiasFilter = null;
                      } else {
                        _activeBiasFilter = entry.$1;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _activeBiasFilter == entry.$1
                          ? colors.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${entry.$2} (${groups[entry.$1]!.length})',
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: _activeBiasFilter == entry.$1
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                            size: 12,
                            color: _activeBiasFilter == entry.$1
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }(),
            // Cards (only shown when expanded)
            if (_activeBiasFilter == null ||
                _activeBiasFilter == entry.$1)
              for (final p in groups[entry.$1]!) ...[
                _PerspectiveCard(perspective: p),
                const SizedBox(height: 8),
              ],
          ],
      ],
    );
  }

  Widget _buildBiasBar(BuildContext context, FacteurColors colors) {
    // 3 simplified segments: Gauche (left+center-left), Centre, Droite (center-right+right)
    final segments = [
      ('gauche', 'Gauche', colors.biasLeft),
      ('centre', 'Centre', colors.biasCenter),
      ('droite', 'Droite', colors.biasRight),
    ];

    final merged = _mergedDistribution;
    final total = merged.values.fold<int>(0, (sum, v) => sum + v);

    // Compute proportional flex values
    final flexValues = <int>[];
    for (final seg in segments) {
      final count = merged[seg.$1] ?? 0;
      if (count > 0 && total > 0) {
        final proportion = count / total;
        flexValues.add((proportion * 100).round().clamp(15, 100));
      } else {
        flexValues.add(15); // Minimum width for empty segments
      }
    }

    // Find the source's segment index for the marker
    final sourceGroup = _toBarGroup(widget.sourceBiasStance);
    final sourceIndex = segments.indexWhere((s) => s.$1 == sourceGroup);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Labels (above the bar) — aligned with bar segments via same flex
          Row(
            children: List.generate(segments.length, (i) {
              final seg = segments[i];
              final count = merged[seg.$1] ?? 0;
              return Expanded(
                flex: flexValues[i],
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: seg.$3
                          .withValues(alpha: count > 0 ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      seg.$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: count > 0 ? seg.$3 : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),

          // Interactive 3-segment bias bar
          Row(
            children: List.generate(segments.length, (i) {
              final seg = segments[i];
              final count = merged[seg.$1] ?? 0;
              final isSelected = _activeBiasFilter == seg.$1;
              final hasFilter = _activeBiasFilter != null;

              return Expanded(
                flex: flexValues[i],
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_activeBiasFilter == seg.$1) {
                        _activeBiasFilter = null;
                      } else {
                        _activeBiasFilter = seg.$1;
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: isSelected ? 18 : 12,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? seg.$3.withValues(
                              alpha: hasFilter && !isSelected
                                  ? 0.3
                                  : (count == 1
                                      ? 0.55
                                      : (count == 2 ? 0.8 : 1.0)))
                          : seg.$3.withValues(
                              alpha: hasFilter && !isSelected ? 0.1 : 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: count > 0
                          ? Border.all(
                              color: Colors.black.withValues(alpha: 0.2),
                              width: 0.8,
                            )
                          : null,
                    ),
                  ),
                ),
              );
            }),
          ),

          // "Votre source" marker
          if (sourceIndex >= 0 &&
              widget.sourceBiasStance != 'unknown') ...[
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final totalFlex =
                    flexValues.fold<int>(0, (sum, f) => sum + f);
                double offsetFraction = 0;
                for (int i = 0; i < sourceIndex; i++) {
                  offsetFraction += flexValues[i] / totalFlex;
                }
                // Center on the segment
                offsetFraction += (flexValues[sourceIndex] / totalFlex) / 2;

                final markerX = constraints.maxWidth * offsetFraction;
                final sourceColor = segments[sourceIndex].$3;

                final displayName = widget.sourceName.isNotEmpty
                    ? widget.sourceName
                    : segments[sourceIndex].$2;

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
                          painter: _TrianglePainter(color: sourceColor),
                        ),
                      ),
                      Positioned(
                        left: (markerX - 50)
                            .clamp(0.0, constraints.maxWidth - 100),
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
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, FacteurColors colors, TextTheme textTheme) {
    // If filtered to empty but there are perspectives, show filter message
    if (_activeBiasFilter != null && widget.perspectives.isNotEmpty) {
      final labels = {
        'gauche': 'Gauche',
        'centre': 'Centre',
        'droite': 'Droite',
      };
      final label = labels[_activeBiasFilter] ?? _activeBiasFilter!;
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.funnel(PhosphorIconsStyle.duotone),
              size: 48,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune perspective "$label"',
              style: textTheme.titleSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tape sur la barre pour voir toutes les perspectives.',
              style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.newspaperClipping(PhosphorIconsStyle.duotone),
            size: 48,
            color: colors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Sujet peu couvert',
            style: textTheme.titleSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ce sujet est peu couvert par les médias.\nEssaie la comparaison sur un autre article !',
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Shimmer line for skeleton loading
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
class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

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
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final uri = Uri.parse(perspective.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title area
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bias indicator
                    Container(
                      width: 4,
                      height: 50,
                      decoration: BoxDecoration(
                        color: perspective.getBiasColor(colors),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title
                    Expanded(
                      child: Text(
                        perspective.title.replaceAll(RegExp(r'\s*[-–|]\s*[^-–|]+$'), '').trim(),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          fontSize: (textTheme.bodyMedium?.fontSize ?? 14) + 3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular),
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
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
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
                      const SizedBox(width: 8),
                      // Source name
                      Flexible(
                        child: Text(
                          perspective.sourceName,
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: (textTheme.labelMedium?.fontSize ?? 12) - 0.5,
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
                      const SizedBox(width: 8),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
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
