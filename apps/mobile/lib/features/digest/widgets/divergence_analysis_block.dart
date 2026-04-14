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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  colors.primary.withOpacity(0.30),
                  FacteurColors.sWarning.withOpacity(0.33),
                ]
              : [
                  colors.primary.withOpacity(0.20),
                  FacteurColors.sWarning.withOpacity(0.25),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: FacteurColors.sWarning.withOpacity(isDark ? 0.80 : 0.70),
            ),
          ),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with info tooltip
          Row(
            children: [
              Text(
                '\u{1F50D} Analyse de biais (${widget.perspectiveCount} sources)',
                style: TextStyle(
                  fontSize: 14,
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
                  color: colors.textSecondary.withOpacity(0.5),
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
                          ? Colors.white.withOpacity(0.85)
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
                          ? Colors.white.withOpacity(0.85)
                          : colors.textSecondary,
                    ),
                  ),
                if (!_isExpanded) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Lire la suite…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // CTA button — primary filled, centered with logos
          if (widget.onCompare != null && widget.perspectiveCount > 1) ...[
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: widget.onCompare,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._buildLogoRow(colors, isDark),
                      if (widget.perspectiveSources.isNotEmpty)
                        const SizedBox(width: 6),
                      Text(
                        'Toutes les perspectives',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 10,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withOpacity(0.5), width: 1),
          ),
          child: _buildLogoCircle(
            name: visible[i].name,
            logoUrl: visible[i].logoUrl,
            size: 16.0,
            colors: colors,
          ),
        ),
      ],
      if (extraCount > 0) ...[
        const SizedBox(width: 4),
        Text(
          '+$extraCount',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.8),
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
