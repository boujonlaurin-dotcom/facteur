import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Badge inline pour la meta-row d'un [`FeedCard`] dans le digest L'Essentiel :
/// trois niveaux de polarisation rendus en `CustomPaint` (28×12 dots) + label
/// mono uppercase. Niveau dérivé directement du `divergenceLevel` exposé par
/// le back via `DigestTopic.divergenceLevel` :
///
/// * `'low'`  → `Traitements similaires` (3 dots groupés au centre)
/// * `'medium'` → `Avis variés` (5 dots étalés régulièrement, label tertiary)
/// * `'high'` → `Polarisé`   (2 paires brique-marine, label primary bold)
///
/// `null` ou valeur inconnue → `SizedBox.shrink()` (silence — conforme au
/// hand-off : on n'affiche le badge que sur articles topicalisés).
class DivergenceInlineBadge extends StatelessWidget {
  final String? divergenceLevel;

  /// Mode compact pour les listes étroites (Flux Continu) : rend uniquement
  /// les dots, sans le label texte. Opacité des dots `medium` boostée pour
  /// compenser l'absence du label qui portait l'information sémantique.
  final bool iconOnly;

  /// Facteur d'échelle appliqué au glyphe ET au label (1.0 = taille de base).
  /// Utilisé par la section « Couverture médiatique » pour grossir la balise
  /// (~+45 %) ; toutes les autres call-sites gardent 1.0.
  final double scale;

  const DivergenceInlineBadge({
    super.key,
    this.divergenceLevel,
    this.iconOnly = false,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final config = _configFor(divergenceLevel, context.facteurColors, iconOnly);
    if (config == null) return const SizedBox.shrink();

    final glyph = CustomPaint(
      size: Size(28 * scale, 12 * scale),
      painter: _DivergenceGlyphPainter(config, scale),
    );

    if (iconOnly) return glyph;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        SizedBox(width: 4 * scale),
        Text(
          config.label,
          style: GoogleFonts.courierPrime(
            fontSize: 8 * scale,
            fontWeight: config.bold ? FontWeight.w700 : FontWeight.w500,
            color: config.labelColor,
            letterSpacing: 0.35 * scale,
          ),
        ),
      ],
    );
  }

  static _BadgeConfig? _configFor(
    String? level,
    FacteurColors colors,
    bool iconOnly,
  ) {
    switch (level) {
      case 'low':
        final dotOpacity = iconOnly ? 0.85 : 0.72;
        return _BadgeConfig(
          label: 'TRAITEMENTS SIMILAIRES',
          dots: [
            _Dot(11, 6, colors.success, dotOpacity),
            _Dot(15, 6, colors.success, dotOpacity),
            _Dot(19, 6, colors.success, dotOpacity),
          ],
          labelColor: colors.textSecondary,
          bold: false,
        );
      case 'medium':
        // En iconOnly les dots portent tout le sens — on remonte l'opacité
        // pour qu'ils restent lisibles sans le label.
        final dotOpacity = iconOnly ? 0.85 : 0.5;
        return _BadgeConfig(
          label: 'AVIS VARIÉS',
          dots: [
            _Dot(4, 6, colors.textTertiary, dotOpacity),
            _Dot(10, 6, colors.textTertiary, dotOpacity),
            _Dot(15, 6, colors.textTertiary, dotOpacity),
            _Dot(20, 6, colors.textTertiary, dotOpacity),
            _Dot(25, 6, colors.textTertiary, dotOpacity),
          ],
          labelColor: colors.textTertiary,
          bold: false,
        );
      case 'high':
        return _BadgeConfig(
          label: 'POLARISÉ',
          dots: [
            _Dot(4, 6, colors.biasLeft, 1.0),
            _Dot(8, 6, colors.biasLeft, 1.0),
            _Dot(20, 6, colors.biasRight, 1.0),
            _Dot(24, 6, colors.biasRight, 1.0),
          ],
          labelColor: colors.textPrimary,
          bold: true,
        );
      default:
        return null;
    }
  }
}

class _BadgeConfig {
  final String label;
  final List<_Dot> dots;
  final Color labelColor;
  final bool bold;
  const _BadgeConfig({
    required this.label,
    required this.dots,
    required this.labelColor,
    required this.bold,
  });
}

class _Dot {
  final double x;
  final double y;
  final Color color;
  final double opacity;
  const _Dot(this.x, this.y, this.color, this.opacity);
}

class _DivergenceGlyphPainter extends CustomPainter {
  final _BadgeConfig config;
  final double scale;
  _DivergenceGlyphPainter(this.config, this.scale);

  static const double _radius = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale != 1.0) canvas.scale(scale);
    for (final dot in config.dots) {
      final paint = Paint()..color = dot.color.withValues(alpha: dot.opacity);
      canvas.drawCircle(Offset(dot.x, dot.y), _radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DivergenceGlyphPainter oldDelegate) {
    return oldDelegate.config != config || oldDelegate.scale != scale;
  }
}
