import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Petite bulle "nudge" affichée à gauche d'un FAB pour inviter à l'action.
/// Speech-bubble avec petit triangle pointant vers la droite (le FAB).
class FabNudgeBubble extends StatelessWidget {
  final String text;
  final double maxWidth;

  const FabNudgeBubble({
    super.key,
    required this.text,
    this.maxWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space3,
                vertical: FacteurSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.25,
                    ),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(8, 12),
            painter: _BubbleTailPainter(
              fill: colors.surface,
              border: colors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color border;

  _BubbleTailPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}
