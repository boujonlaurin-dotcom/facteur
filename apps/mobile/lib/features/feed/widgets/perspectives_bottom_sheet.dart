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
    // Liste ordonnée des biais pour la barre
    final orderedBiases = [
      'left',
      'center-left',
      'center',
      'center-right',
      'right'
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Barre de segments fixes
          Row(
            children: orderedBiases.map((bias) {
              final count = biasDistribution[bias] ?? 0;
              final Color baseColor;
              switch (bias) {
                case 'left':
                  baseColor = colors.biasLeft;
                  break;
                case 'center-left':
                  baseColor = colors.biasCenterLeft;
                  break;
                case 'center':
                  baseColor = colors.biasCenter;
                  break;
                case 'center-right':
                  baseColor = colors.biasCenterRight;
                  break;
                case 'right':
                  baseColor = colors.biasRight;
                  break;
                default:
                  baseColor = colors.biasUnknown;
              }

              return Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 1.0), // 2px total gap
                  decoration: BoxDecoration(
                    // Approche Expert : Saturation progressive + Gaps nets
                    // Évite l'effet "cheap" des bordures tout en préservant l'identité colorimétrique
                    color: count > 0
                        ? baseColor.withValues(
                            alpha: count == 1 ? 0.55 : (count == 2 ? 0.8 : 1.0))
                        : baseColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    // Bordure sombre subtile pour faire ressortir les blocs actifs
                    border: count > 0
                        ? Border.all(
                            color: Colors.black.withValues(alpha: 0.25),
                            width: 0.8,
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Labels alignés sur les segments extrêmes et centre
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gauche',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: (biasDistribution['left'] ?? 0) > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: (biasDistribution['left'] ?? 0) > 0
                          ? colors.biasLeft
                          : colors.textTertiary)),
              Text('Centre',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: (biasDistribution['center'] ?? 0) > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: (biasDistribution['center'] ?? 0) > 0
                          ? colors.biasCenter
                          : colors.textTertiary)),
              Text('Droite',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: (biasDistribution['right'] ?? 0) > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: (biasDistribution['right'] ?? 0) > 0
                          ? colors.biasRight
                          : colors.textTertiary)),
            ],
          ),
        ],
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
            color: colors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune perspective trouvée',
            style: textTheme.titleSmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Sujet probablement pas d\'actualité / un peu trop "niche"',
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
