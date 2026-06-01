import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/serein_colors.dart';
import '../../../config/theme.dart';

class RingAvatar extends StatelessWidget {
  final String initials;
  final double? progress;

  /// When true the avatar adopts the serein identity: sage-green fill/ring and
  /// a small lotus badge — the persistent visual cue that serein mode is ON.
  final bool serein;

  const RingAvatar({
    super.key,
    required this.initials,
    this.progress,
    this.serein = false,
  });

  factory RingAvatar.fromName(
    String? fullName,
    double? progress, {
    bool serein = false,
  }) {
    final raw = fullName?.trim() ?? '';
    if (raw.isEmpty) {
      return RingAvatar(initials: 'F', progress: progress, serein: serein);
    }
    final parts = raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final letters =
        parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
    return RingAvatar(initials: letters, progress: progress, serein: serein);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasRing = progress != null;
    final clamped = (progress ?? 0).clamp(0.0, 1.0);

    final avatar = Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: serein ? SereinColors.sereinColor : colors.textPrimary,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1,
          color: colors.backgroundPrimary,
        ),
      ),
    );

    final Widget inner;
    if (!hasRing) {
      inner = Center(child: avatar);
    } else {
      inner = TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: clamped),
        builder: (context, value, child) {
          return CustomPaint(
            painter: _RingPainter(
              progress: value,
              progressColor:
                  serein ? SereinColors.sereinColor : colors.textSecondary,
            ),
            child: child,
          );
        },
        child: Center(child: avatar),
      );
    }

    // Non-serein render is left byte-identical to the original tree so the
    // existing golden snapshots keep passing — only serein adds the Stack.
    if (!serein) {
      return SizedBox(width: 42, height: 42, child: inner);
    }

    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: inner),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.backgroundPrimary,
              ),
              child: Icon(
                SereinColors.sereinIcon,
                size: 12,
                color: SereinColors.sereinColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color progressColor;

  _RingPainter({required this.progress, required this.progressColor});

  static const double _radius = 18.7;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = Colors.black.withValues(alpha: 0.07);
    canvas.drawCircle(center, _radius, track);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
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
