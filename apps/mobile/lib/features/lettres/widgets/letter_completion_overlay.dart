import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/letter.dart';

/// Plein écran cachet animé : affiché quand une lettre passe à `archived`.
class LetterCompletionOverlay extends StatefulWidget {
  final Letter letter;
  final VoidCallback onDismiss;

  const LetterCompletionOverlay({
    super.key,
    required this.letter,
    required this.onDismiss,
  });

  @override
  State<LetterCompletionOverlay> createState() =>
      _LetterCompletionOverlayState();
}

class _LetterCompletionOverlayState extends State<LetterCompletionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _continue() {
    widget.onDismiss();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  void _close() {
    widget.onDismiss();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final dateLabel = _formatStampDate(
      (widget.letter.archivedAt ?? DateTime.now()).toLocal(),
    );

    return Material(
      color: colors.backgroundPrimary,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _ctl,
                builder: (context, child) {
                  final t = _ctl.value;
                  // Phase 1 (0..0.6) : fade-in + scale 1.4→0.96 + rotate -12→-2
                  // Phase 2 (0.6..1) : scale 0.96→1.0 + rotate -2→-4
                  final double opacity;
                  final double scale;
                  final double rotateDeg;
                  if (t < 0.6) {
                    final p = (t / 0.6).clamp(0.0, 1.0);
                    final eased = Curves.easeOutCubic.transform(p);
                    opacity = eased;
                    scale = 1.4 + (0.96 - 1.4) * eased;
                    rotateDeg = -12 + (-2 - -12) * eased;
                  } else {
                    final p = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
                    final eased = Curves.easeOutCubic.transform(p);
                    opacity = 1;
                    scale = 0.96 + (1.0 - 0.96) * eased;
                    rotateDeg = -2 + (-4 - -2) * eased;
                  }
                  return Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: rotateDeg * math.pi / 180,
                      child: Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _Cachet(
                  letterNum: widget.letter.letterNum,
                  dateLabel: dateLabel,
                  colors: colors,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Lettre classée.',
                style: GoogleFonts.fraunces(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                widget.letter.completionVoeu ?? 'On te prépare la suite !',
                style: GoogleFonts.dmSans(
                  fontSize: 14.5,
                  height: 1.5,
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Continuer',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _close,
                  child: Text(
                    'Fermer',
                    style: GoogleFonts.dmSans(
                      fontSize: 14.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cachet extends StatelessWidget {
  final String letterNum;
  final String dateLabel;
  final FacteurColors colors;

  const _Cachet({
    required this.letterNum,
    required this.dateLabel,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 130,
      child: CustomPaint(
        painter: _CachetPainter(color: colors.primary),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                letterNum,
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'CLASSÉE',
                style: GoogleFonts.courierPrime(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateLabel,
                style: GoogleFonts.courierPrime(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CachetPainter extends CustomPainter {
  final Color color;

  _CachetPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 2;

    // Outer fill
    final fill = Paint()..color = color.withOpacity(0.04);
    canvas.drawCircle(center, outerR, fill);

    // Outer stroke
    final outerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color;
    canvas.drawCircle(center, outerR, outerStroke);

    // Inner dashed ring
    final innerR = outerR - 5;
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.45);

    const dashLen = 4.0;
    const gapLen = 4.0;
    final circumference = 2 * math.pi * innerR;
    final dashCount = (circumference / (dashLen + gapLen)).floor();
    final sweepPerStep = (2 * math.pi) / dashCount;
    final sweepDash = sweepPerStep * (dashLen / (dashLen + gapLen));

    final innerRect = Rect.fromCircle(center: center, radius: innerR);
    for (int i = 0; i < dashCount; i++) {
      final start = i * sweepPerStep;
      canvas.drawArc(innerRect, start, sweepDash, false, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CachetPainter old) => old.color != color;
}

const _stampMonths = [
  'JANV',
  'FÉVR',
  'MARS',
  'AVRIL',
  'MAI',
  'JUIN',
  'JUIL',
  'AOÛT',
  'SEPT',
  'OCT',
  'NOV',
  'DÉC',
];

String _formatStampDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  return '$dd ${_stampMonths[d.month - 1]} ${d.year}';
}
