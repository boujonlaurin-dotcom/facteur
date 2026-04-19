import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../feed/widgets/initial_circle.dart';
import '../models/digest_models.dart';
import 'bias_spectrum_bar.dart';
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
  // Identity of the singleton article's source — excluded from the 3 mini
  // logos shown in the CTA so the button complements (not duplicates) the
  // source already visible on the card. Match on id first, name fallback.
  final String? excludeSourceId;
  final String? excludeSourceName;

  const DivergenceAnalysisBlock({
    super.key,
    this.divergenceAnalysis,
    this.biasHighlights,
    this.biasDistribution,
    this.divergenceLevel,
    this.onCompare,
    this.perspectiveCount = 0,
    this.perspectiveSources = const [],
    this.excludeSourceId,
    this.excludeSourceName,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withOpacity(isDark ? 0.10 : 0.05),
            border: Border.all(
              color: colors.warning.withOpacity(0.08),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — badge chip (aligned with PasDeRecul's EditorialBadge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.warning.withOpacity(isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '\u{1F50D} Analyse de biais',
                  style: TextStyle(
                    color: colors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Divergence level — inline colored text (icon + label + sources)
              if (widget.divergenceLevel != null) ...[
                const SizedBox(height: 14),
                _buildDivergenceLine(colors),
              ],

              // Bias spectrum bar
              if (widget.biasDistribution != null) ...[
                const SizedBox(height: 14),
                BiasSpectrumBar(biasDistribution: widget.biasDistribution),
              ],

              // E1.b — collapsed by default: chevron "Lire l'analyse"
              // Expanded: full text + CTA "Voir les N perspectives →"
              // Toggle is handled by the parent InkWell (whole card is tappable).
              const SizedBox(height: 14),
              if (!_isExpanded)
                Row(
                  children: [
                    Icon(
                      Icons.expand_more,
                      size: 16,
                      color: colors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Lire l'analyse",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                )
              else ...[
                // "Réduire" chevron aligned right — toggles via parent InkWell.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.expand_less,
                      size: 16,
                      color: colors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Réduire',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                MarkdownText(
                  text: widget.divergenceAnalysis!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark
                        ? Colors.white.withOpacity(0.85)
                        : colors.textSecondary,
                  ),
                ),
                // CTA — pill discrète "Voir les N perspectives [logo×3]".
                // Style volontairement effacé : couleur tertiaire, bord
                // léger, taille compacte. Le focus visuel reste sur la
                // barre de biais ; le bouton complète sans s'imposer.
                if (widget.onCompare != null &&
                    widget.perspectiveCount > 1) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 30,
                      child: OutlinedButton(
                        onPressed: widget.onCompare,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          side: BorderSide(
                            color: colors.textSecondary.withOpacity(0.25),
                            width: 0.8,
                          ),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Voir les ${widget.perspectiveCount} perspectives',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colors.textSecondary,
                              ),
                            ),
                            ..._buildCtaLogos(colors),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Up to 3 mini source logos rendered after the CTA text, showing
  /// "other" sources covering the topic (i.e. excluding the singleton's
  /// source — already visible on the card). Logos are sized to slot
  /// inside the discreet 30px-tall button without inflating it.
  /// Returns an empty list if nothing to show so the layout degrades
  /// cleanly.
  List<Widget> _buildCtaLogos(FacteurColors colors) {
    const maxLogos = 3;
    const size = 16.0;

    bool isExcluded(SourceMini s) =>
        (widget.excludeSourceId != null && s.id == widget.excludeSourceId) ||
        (widget.excludeSourceName != null && s.name == widget.excludeSourceName);

    final others = <SourceMini>[];
    final seen = <String>{};
    for (final s in widget.perspectiveSources) {
      if (isExcluded(s)) continue;
      if (!seen.add(s.name)) continue;
      others.add(s);
      if (others.length >= maxLogos) break;
    }

    if (others.isEmpty) return const [];

    final widgets = <Widget>[const SizedBox(width: 6)];
    for (var i = 0; i < others.length; i++) {
      if (i > 0) widgets.add(const SizedBox(width: 3));
      widgets.add(_logoCircle(others[i], size, colors));
    }
    return widgets;
  }

  Widget _logoCircle(SourceMini s, double size, FacteurColors colors) {
    final logoUrl = s.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipOval(
        child: FacteurImage(
          imageUrl: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (context) => InitialCircle(
            initial: s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
            colors: colors,
            size: size,
          ),
        ),
      );
    }
    return InitialCircle(
      initial: s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
      colors: colors,
      size: size,
    );
  }

  /// Inline colored line for the divergence level, replacing the former
  /// `DivergenceChip` pill. Format: "[icon] {label} · N sources".
  Widget _buildDivergenceLine(FacteurColors colors) {
    final (IconData icon, String label, Color color) =
        switch (widget.divergenceLevel!) {
      'high' => (PhosphorIcons.lightning(), 'Fort désaccord', colors.error),
      'medium' => (
          PhosphorIcons.arrowsLeftRight(),
          'Angles différents',
          colors.warning
        ),
      _ => (
          PhosphorIcons.equals(),
          'Traitements similaires',
          colors.success
        ),
    };
    final sources = widget.perspectiveCount > 0
        ? ' · ${widget.perspectiveCount} sources'
        : '';
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label$sources',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
