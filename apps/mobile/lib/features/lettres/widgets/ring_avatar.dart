import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

class RingAvatar extends StatelessWidget {
  final String initials;
  final double? progress;

  const RingAvatar({
    super.key,
    required this.initials,
    this.progress,
  });

  factory RingAvatar.fromName(String? fullName, double? progress) {
    final raw = fullName?.trim() ?? '';
    if (raw.isEmpty) {
      return RingAvatar(initials: 'F', progress: progress);
    }
    final parts = raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final letters =
        parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
    return RingAvatar(initials: letters, progress: progress);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasRing = progress != null;
    final clamped = (progress ?? 0).clamp(0.0, 1.0);

    final avatar = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.textPrimary,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1,
          color: colors.backgroundPrimary,
        ),
      ),
    );

    if (!hasRing) {
      return SizedBox(
        width: 38,
        height: 38,
        child: Center(child: avatar),
      );
    }

    return SizedBox(
      width: 38,
      height: 38,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: clamped),
        builder: (context, value, child) {
          return CustomPaint(
            painter: _RingPainter(
              progress: value,
              progressColor: colors.textSecondary,
            ),
            child: child,
          );
        },
        child: Center(child: avatar),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color progressColor;

  _RingPainter({required this.progress, required this.progressColor});

  static const double _radius = 17.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Colors.black.withValues(alpha: 0.07);
    canvas.drawCircle(center, _radius, track);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    final rect = Rect.fromCircle(center: center, radius: _radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}
