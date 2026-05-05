import 'package:flutter/material.dart';

import '../../../config/theme.dart';

class EnvelopeThumb extends StatelessWidget {
  final double width;
  final double height;
  final bool archived;

  const EnvelopeThumb({
    super.key,
    this.width = 52,
    this.height = 38,
    this.archived = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _EnvelopePainter(
          sealColor: archived
              ? colors.textTertiary.withOpacity(0.5)
              : colors.primary,
        ),
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  final Color sealColor;

  _EnvelopePainter({required this.sealColor});

  static const Color _bg = Color(0xFFFBF6EC);
  static final Color _border = const Color(0xFF3C2814).withOpacity(0.14);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    // Drop shadow
    final shadow = Paint()
      ..color = const Color(0xFF3C2814).withOpacity(0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      shadow,
    );

    // Background
    final bg = Paint()..color = _bg;
    canvas.drawRRect(rrect, bg);

    // Inset border
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _border;
    canvas.drawRRect(rrect, border);

    // V-flap (top diagonals meeting at center)
    final flap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _border;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    canvas.drawLine(Offset.zero, Offset(centerX, centerY), flap);
    canvas.drawLine(Offset(size.width, 0), Offset(centerX, centerY), flap);

    // Wax seal — centered on bottom edge
    final sealWidth = size.width * 0.34;
    final sealHeight = 2.0;
    final sealRect = Rect.fromCenter(
      center: Offset(centerX, size.height - 6),
      width: sealWidth,
      height: sealHeight,
    );
    final seal = Paint()..color = sealColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(sealRect, const Radius.circular(1)),
      seal,
    );
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter old) =>
      old.sealColor != sealColor;
}
