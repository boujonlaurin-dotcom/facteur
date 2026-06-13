import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Horizontal dotted separator with a centered label, used to mark the
/// transition between the bounded "Tournée du jour" stack and the open-ended
/// "Explorer" feed below. Visual ID : two dotted segments (left/right of the
/// label) drawn with [_DottedLinePainter], label uppercase letter-spaced.
class SectionDividerDotted extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry margin;

  const SectionDividerDotted({
    super.key,
    required this.label,
    this.margin = const EdgeInsets.fromLTRB(20, 8, 20, 12),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final tint = colors.border.withValues(alpha: 0.65);
    return Padding(
      padding: margin,
      child: Row(
        children: [
          Expanded(child: _DottedLine(color: tint)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(child: _DottedLine(color: tint)),
        ],
      ),
    );
  }
}

class _DottedLine extends StatelessWidget {
  final Color color;

  const _DottedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DottedLinePainter(color: color),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dashWidth = 2.0;
    const dashGap = 4.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
