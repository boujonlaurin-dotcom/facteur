import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../feed/widgets/initial_circle.dart';
import '../models/digest_models.dart';
import 'bias_spectrum_bar.dart';
import 'divergence_chip.dart';
import 'markdown_text.dart';

/// Block displaying a quick analysis of media divergences on a topic.
/// Hidden when [divergenceAnalysis] is null.
class DivergenceAnalysisBlock extends StatefulWidget {
  final String? divergenceAnalysis;
  final String? biasHighlights;
  final Map<String, int>? biasDistribution;
  final String? divergenceLevel;
  final VoidCallback? onCompare;
  final int perspectiveCount;
  final List<SourceMini> perspectiveSources;

  const DivergenceAnalysisBlock({
    super.key,
    this.divergenceAnalysis,
    this.biasHighlights,
    this.biasDistribution,
    this.divergenceLevel,
    this.onCompare,
    this.perspectiveCount = 0,
    this.perspectiveSources = const [],
  });

  @override
  State<DivergenceAnalysisBlock> createState() =>
      _DivergenceAnalysisBlockState();
}

class _DivergenceAnalysisBlockState extends State<DivergenceAnalysisBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.divergenceAnalysis == null) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  colors.primary.withValues(alpha: 0.12),
                  colors.primary.withValues(alpha: 0.06),
                ]
              : [
                  colors.primary.withValues(alpha: 0.08),
                  colors.primary.withValues(alpha: 0.03),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.primary.withValues(alpha: isDark ? 0.3 : 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with info tooltip
          Row(
            children: [
              Text(
                "\u{1F50D} L'analyse Facteur",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Analyse générée via Mistral Medium',
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),

          // Divergence chip
          if (widget.divergenceLevel != null) ...[
            const SizedBox(height: 8),
            DivergenceChip(divergenceLevel: widget.divergenceLevel),
          ],

          // Bias spectrum bar
          if (widget.biasDistribution != null) ...[
            const SizedBox(height: 8),
            BiasSpectrumBar(biasDistribution: widget.biasDistribution),
          ],

          // Analysis text — collapsed (3 lines) or expanded
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isExpanded)
                  MarkdownText(
                    text: widget.divergenceAnalysis!,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : colors.textSecondary,
                    ),
                  )
                else
                  MarkdownText(
                    text: widget.divergenceAnalysis!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : colors.textSecondary,
                    ),
                  ),
                if (!_isExpanded) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Lire la suite…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // CTA button
          if (widget.onCompare != null && widget.perspectiveCount > 1) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: widget.onCompare,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  // Logo row
                  ..._buildLogoRow(colors, isDark),
                  const SizedBox(width: 8),
                  Text(
                    'Toutes les perspectives',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildLogoRow(FacteurColors colors, bool isDark) {
    final sources = widget.perspectiveSources;
    if (sources.isEmpty) return [];

    const maxLogos = 3;
    final visible = sources.take(maxLogos).toList();
    final extraCount = sources.length - visible.length;

    return [
      for (var i = 0; i < visible.length; i++) ...[
        if (i > 0) const SizedBox(width: 2),
        _buildLogoCircle(
          name: visible[i].name,
          logoUrl: visible[i].logoUrl,
          size: 18.0,
          colors: colors,
        ),
      ],
      if (extraCount > 0) ...[
        const SizedBox(width: 4),
        Text(
          '+$extraCount',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary.withValues(alpha: 0.7),
          ),
        ),
      ],
    ];
  }

  Widget _buildLogoCircle({
    required String name,
    required String? logoUrl,
    required double size,
    required FacteurColors colors,
  }) {
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;
    if (hasLogo) {
      return ClipOval(
        child: FacteurImage(
          imageUrl: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (context) => InitialCircle(
            initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
            colors: colors,
            size: size,
          ),
        ),
      );
    }
    return InitialCircle(
      initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
      colors: colors,
      size: size,
    );
  }
}
