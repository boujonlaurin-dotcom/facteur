import 'package:flutter/material.dart';

/// Peintre d'un rectangle arrondi à bord **pointillé** (tirets).
///
/// Maison (≈ pas de dépendance `dotted_border`) pour un contrôle pixel exact :
/// utilisé pour le filet du masthead, le liseré du sceau (`mt-seal`), la feuille
/// de partage et le contour des pastilles de streak. Déterministe → goldens
/// stables.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.radius = 0,
    this.dashLength = 4,
    this.gapLength = 3,
    this.inset = 0,
  });

  /// Couleur du tiret.
  final Color color;

  /// Épaisseur du trait.
  final double strokeWidth;

  /// Rayon des coins du rectangle.
  final double radius;

  /// Longueur d'un tiret.
  final double dashLength;

  /// Longueur d'un espace entre deux tirets.
  final double gapLength;

  /// Marge intérieure du tracé par rapport aux bords (utile pour le liseré
  /// `mt-seal` qui s'inscrit à l'intérieur de la tuile).
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final path = Path()..addRRect(rrect);
    canvas.drawPath(_dashPath(path), paint);
  }

  /// Reconstruit [source] en n'en gardant que des segments de [dashLength]
  /// espacés de [gapLength], le long de toutes ses métriques.
  Path _dashPath(Path source) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        if (draw) {
          dest.addPath(
            metric.extractPath(distance, distance + len),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(DashedRRectPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius ||
        dashLength != oldDelegate.dashLength ||
        gapLength != oldDelegate.gapLength ||
        inset != oldDelegate.inset;
  }
}

/// Filet horizontal pointillé (masthead `.rule`, clôture `.tf-closure-rule`).
class DashedLinePainter extends CustomPainter {
  const DashedLinePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashLength = 5,
    this.gapLength = 4,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashLength, y), paint);
      x += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(DashedLinePainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashLength != oldDelegate.dashLength ||
        gapLength != oldDelegate.gapLength;
  }
}
