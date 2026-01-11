import 'dart:math';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Animation de particules qui convergent vers le centre
/// Effet "agrégation de sources" pour la conclusion de l'onboarding
class ParticlesAnimation extends StatefulWidget {
  const ParticlesAnimation({super.key});

  @override
  State<ParticlesAnimation> createState() => _ParticlesAnimationState();
}

class _ParticlesAnimationState extends State<ParticlesAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Générer les particules avec positions aléatoires
    _particles = List.generate(
      25,
      (index) => Particle(
        startX: Random().nextDouble() * 2 - 1, // -1 à 1
        startY: Random().nextDouble() * 2 - 1, // -1 à 1
        size: 4.0 + Random().nextDouble() * 4.0, // 4 à 8
        delay: Random().nextDouble() * 0.3, // 0 à 0.3
        colorIndex: Random().nextInt(3), // 3 couleurs
      ),
    );

    // Boucle l'animation
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: ParticlesPainter(
              particles: _particles,
              progress: _controller.value,
              colors: [
                context.facteurColors.primary,
                context.facteurColors.secondary,
                context.facteurColors.textPrimary.withValues(alpha: 0.8),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Représente une particule individuelle
class Particle {
  final double startX;
  final double startY;
  final double size;
  final double delay;
  final int colorIndex;

  const Particle({
    required this.startX,
    required this.startY,
    required this.size,
    required this.delay,
    required this.colorIndex,
  });
}

/// Painter personnalisé pour dessiner les particules
class ParticlesPainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;
  final List<Color> colors;

  ParticlesPainter({
    required this.particles,
    required this.progress,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final particle in particles) {
      // Calculer la progression de cette particule (avec delay)
      final delayedProgress = (progress - particle.delay).clamp(0.0, 1.0);

      // Animation avec easing
      final easedProgress = Curves.easeInOutCubic.transform(delayedProgress);

      // Position interpolée du start vers le centre
      final startOffset = Offset(
        center.dx + (particle.startX * size.width * 0.4),
        center.dy + (particle.startY * size.height * 0.4),
      );

      final currentX =
          startOffset.dx + (center.dx - startOffset.dx) * easedProgress;
      final currentY =
          startOffset.dy + (center.dy - startOffset.dy) * easedProgress;

      // Opacity : fade in puis fade out à la fin
      final opacity = easedProgress < 0.8
          ? (easedProgress * 1.25).clamp(0.3, 1.0)
          : (1.0 - (easedProgress - 0.8) * 5).clamp(0.0, 1.0);

      // Size : petit au début, plus grand à la fin
      final currentSize = particle.size * (0.7 + easedProgress * 0.3);

      // Dessiner la particule
      final paint = Paint()
        ..color = colors[particle.colorIndex].withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(currentX, currentY),
        currentSize,
        paint,
      );
    }

    // Dessiner l'emoji central
    _drawCenterEmoji(canvas, size, progress);
  }

  void _drawCenterEmoji(Canvas canvas, Size size, double progress) {
    // L'emoji apparaît progressivement
    if (progress > 0.5) {
      final emojiOpacity = ((progress - 0.5) * 2).clamp(0.0, 1.0);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '📬',
          style: TextStyle(
            fontSize: 40,
            color: Colors.white.withOpacity(emojiOpacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(ParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
