import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Badge inline pour la meta-row d'un [`FeedCard`] dans le digest L'Essentiel :
/// trois niveaux de polarisation rendus en `CustomPaint` (28×12 dots) + label
/// mono uppercase. Niveau dérivé directement du `divergenceLevel` exposé par
/// le back via `DigestTopic.divergenceLevel` :
///
/// * `'low'`  → `Consensus`  (3 dots groupés au centre, label tertiary)
/// * `'medium'` → `Avis variés` (5 dots étalés régulièrement, label tertiary)
/// * `'high'` → `Polarisé`   (2 paires brique-marine, label primary bold)
///
/// `null` ou valeur inconnue → `SizedBox.shrink()` (silence — conforme au
/// hand-off : on n'affiche le badge que sur articles topicalisés).
class DivergenceInlineBadge extends StatelessWidget {
  final String? divergenceLevel;

  const DivergenceInlineBadge({super.key, this.divergenceLevel});

  @override
  Widget build(BuildContext context) {
    final config = _configFor(divergenceLevel, context.facteurColors);
    if (config == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(28, 12),
          painter: _DivergenceGlyphPainter(config),
        ),
        const SizedBox(width: 4),
        Text(
          config.label,
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: config.bold ? FontWeight.w700 : FontWeight.w500,
            color: config.labelColor,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  static _BadgeConfig? _configFor(String? level, FacteurColors colors) {
    switch (level) {
      case 'low':
        return _BadgeConfig(
          label: 'CONSENSUS',
          dots: [
            _Dot(11, 6, colors.textTertiary, 0.55),
            _Dot(14, 6, colors.textTertiary, 0.55),
            _Dot(17, 6, colors.textTertiary, 0.55),
          ],
          labelColor: colors.textTertiary,
          bold: false,
        );
      case 'medium':
        return _BadgeConfig(
          label: 'AVIS VARIÉS',
          dots: [
            _Dot(4, 6, colors.textTertiary, 0.5),
            _Dot(10, 6, colors.textTertiary, 0.5),
            _Dot(15, 6, colors.textTertiary, 0.5),
            _Dot(20, 6, colors.textTertiary, 0.5),
            _Dot(25, 6, colors.textTertiary, 0.5),
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
  _DivergenceGlyphPainter(this.config);

  static const double _radius = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    for (final dot in config.dots) {
      final paint = Paint()..color = dot.color.withValues(alpha: dot.opacity);
      canvas.drawCircle(Offset(dot.x, dot.y), _radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DivergenceGlyphPainter oldDelegate) {
    return oldDelegate.config != config;
  }
}
