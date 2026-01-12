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

  Color getBiasColor() {
    switch (biasStance) {
      case 'left':
        return Colors.red.shade400;
      case 'center-left':
        return Colors.orange.shade400;
      case 'center':
        return Colors.purple.shade400;
      case 'center-right':
        return Colors.blue.shade300;
      case 'right':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade400;
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
}

/// Bottom sheet to display alternative perspectives
class PerspectivesBottomSheet extends StatelessWidget {
  final List<Perspective> perspectives;
  final Map<String, int> biasDistribution;
  final List<String> keywords;

  const PerspectivesBottomSheet({
    super.key,
    required this.perspectives,
    required this.biasDistribution,
    required this.keywords,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
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
              color: colors.textSecondary.withOpacity(0.2),
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
                        'Mots-clés: ${keywords.join(", ")}',
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

          // Bias Bar
          _buildBiasBar(context, colors),

          const Divider(height: 1),

          // Perspectives List
          Flexible(
            child: perspectives.isEmpty
                ? _buildEmptyState(context, colors, textTheme)
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: perspectives.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _PerspectiveCard(perspective: perspectives[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiasBar(BuildContext context, FacteurColors colors) {
    final total = biasDistribution.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              _buildBiasSegment('left', Colors.red.shade400,
                  biasDistribution['left'] ?? 0, total),
              _buildBiasSegment('center-left', Colors.orange.shade400,
                  biasDistribution['center-left'] ?? 0, total),
              _buildBiasSegment('center', Colors.purple.shade400,
                  biasDistribution['center'] ?? 0, total),
              _buildBiasSegment('center-right', Colors.blue.shade300,
                  biasDistribution['center-right'] ?? 0, total),
              _buildBiasSegment('right', Colors.blue.shade600,
                  biasDistribution['right'] ?? 0, total),
              _buildBiasSegment('unknown', Colors.grey.shade400,
                  biasDistribution['unknown'] ?? 0, total),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gauche',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary)),
              Text('Centre',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary)),
              Text('Droite',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBiasSegment(String bias, Color color, int count, int total) {
    if (count == 0) return const SizedBox.shrink();
    final flex = (count / total * 10).round().clamp(1, 10);

    return Expanded(
      flex: flex,
      child: Container(
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, FacteurColors colors, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.duotone),
            size: 48,
            color: colors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune perspective trouvée',
            style: textTheme.titleSmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Nous n\'avons pas trouvé d\'articles similaires sur ce sujet.',
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
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
                    color: perspective.getBiasColor(),
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
                              color:
                                  perspective.getBiasColor().withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              perspective.getBiasLabel(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: perspective.getBiasColor(),
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
