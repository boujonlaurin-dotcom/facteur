import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';

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

/// Bottom sheet to display alternative perspectives
class PerspectivesBottomSheet extends StatefulWidget {
  final List<Perspective> perspectives;
  final Map<String, int> biasDistribution;
  final List<String> keywords;
  final String sourceBiasStance;

  const PerspectivesBottomSheet({
    super.key,
    required this.perspectives,
    required this.biasDistribution,
    required this.keywords,
    this.sourceBiasStance = 'unknown',
  });

  @override
  State<PerspectivesBottomSheet> createState() =>
      _PerspectivesBottomSheetState();
}

class _PerspectivesBottomSheetState extends State<PerspectivesBottomSheet> {
  /// Active filter: 'gauche', 'centre', 'droite', or null (show all)
  String? _activeBiasFilter;

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

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filteredPerspectives;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                  PhosphorIcons.scales(PhosphorIconsStyle.fill),
                  color: colors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autres points de vue',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Mots-clés: ${widget.keywords.join(", ")}',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
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

          const Divider(height: 1),

          // Perspectives List
          Flexible(
            child: filtered.isEmpty
                ? _buildEmptyState(context, colors, textTheme)
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _PerspectiveCard(perspective: filtered[index]);
                    },
                  ),
          ),
        ],
      ),
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

                return SizedBox(
                  height: 36,
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
                        left: (markerX - 45)
                            .clamp(0.0, constraints.maxWidth - 90),
                        top: 10,
                        child: SizedBox(
                          width: 90,
                          child: Column(
                            children: [
                              Text(
                                'Votre source',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: sourceColor,
                                ),
                              ),
                              Text(
                                segments[sourceIndex].$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: sourceColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 4),
          // Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: segments.map((seg) {
              final count = merged[seg.$1] ?? 0;
              return Text(
                seg.$2,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                  color: count > 0 ? seg.$3 : colors.textTertiary,
                ),
              );
            }).toList(),
          ),
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

class _PerspectiveCard extends StatelessWidget {
  final Perspective perspective;

  const _PerspectiveCard({required this.perspective});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final uri = Uri.parse(perspective.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
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

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Source + Bias
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              perspective.sourceName,
                              style: textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: perspective
                                  .getBiasColor(colors)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              perspective.getBiasLabel(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: perspective.getBiasColor(colors),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Title
                      Text(
                        perspective.title,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
