import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Animation minimaliste pour l'écran de conclusion.
/// Inspirée par le design "Notion" / Premium Press : sobre, rassurant, simple.
class MinimalLoader extends StatefulWidget {
  const MinimalLoader({super.key});

  @override
  State<MinimalLoader> createState() => _MinimalLoaderState();
}

class _MinimalLoaderState extends State<MinimalLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2), // Rotation plus lente et posée
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48, // Beaucoup plus petit et discret
      height: 48,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _MinimalLoaderPainter(
              progress: _controller.value,
              color: context.facteurColors.primary,
              trackColor:
                  context.facteurColors.surface, // Ou un gris très léger
            ),
          );
        },
      ),
    );
  }
}

class _MinimalLoaderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _MinimalLoaderPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2; // Padding de 2px
    const strokeWidth = 3.5; // Trait fin mais visible

    // 1. Fond du cercle (Track) - subtil et rassurant
    final trackPaint = Paint()
      ..color = color.withValues(
          alpha: 0.1) // Très léger rappel de la couleur primaire
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // 2. Arc de progression (Spinner)
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round // Bouts arrondis pour le côté "soft"
      ..strokeWidth = strokeWidth;

    // Animation de rotation + longueur d'arc variable (Material style, mais plus doux)
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);
    const sweepAngle =
        math.pi * 0.7; // Longueur d'arc constante pour la sobriété

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_MinimalLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
