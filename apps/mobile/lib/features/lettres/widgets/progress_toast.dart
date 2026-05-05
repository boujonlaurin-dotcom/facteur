import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

enum ProgressToastLevel { micro, section, step }

OverlayEntry? _currentEntry;
VoidCallback? _currentDismiss;

void showProgressToast(
  BuildContext context, {
  required ProgressToastLevel level,
  int? current,
  int? total,
  String? label,
  String? sectionTitle,
  String? stepNum,
  String? stepTitle,
  VoidCallback? onOpen,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // Anti-overlap : un seul toast à la fois.
  _currentDismiss?.call();

  late OverlayEntry entry;
  late void Function() dismiss;
  bool removed = false;

  void onDismissed() {
    if (removed) return;
    removed = true;
    if (identical(entry, _currentEntry)) {
      _currentEntry = null;
      _currentDismiss = null;
    }
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ProgressToast(
      level: level,
      current: current,
      total: total,
      label: label,
      sectionTitle: sectionTitle,
      stepNum: stepNum,
      stepTitle: stepTitle,
      onOpen: onOpen,
      onDismissed: onDismissed,
      onRequestClose: (cb) => dismiss = cb,
    ),
  );

  _currentEntry = entry;
  _currentDismiss = () {
    dismiss();
  };

  overlay.insert(entry);

  switch (level) {
    case ProgressToastLevel.micro:
      HapticFeedback.selectionClick();
      break;
    case ProgressToastLevel.section:
      HapticFeedback.lightImpact();
      break;
    case ProgressToastLevel.step:
      HapticFeedback.mediumImpact();
      break;
  }
}

class _ProgressToast extends StatefulWidget {
  final ProgressToastLevel level;
  final int? current;
  final int? total;
  final String? label;
  final String? sectionTitle;
  final String? stepNum;
  final String? stepTitle;
  final VoidCallback? onOpen;
  final VoidCallback onDismissed;
  final ValueChanged<VoidCallback> onRequestClose;

  const _ProgressToast({
    required this.level,
    required this.onDismissed,
    required this.onRequestClose,
    this.current,
    this.total,
    this.label,
    this.sectionTitle,
    this.stepNum,
    this.stepTitle,
    this.onOpen,
  });

  @override
  State<_ProgressToast> createState() => _ProgressToastState();
}

class _ProgressToastState extends State<_ProgressToast>
    with TickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 360);
  static const _exitDuration = Duration(milliseconds: 240);

  late final AnimationController _enter;
  late final AnimationController _life;
  Timer? _holdTimer;
  bool _leaving = false;

  Duration get _hold => widget.level == ProgressToastLevel.step
      ? const Duration(milliseconds: 4500)
      : const Duration(milliseconds: 3000);

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: _enterDuration)
      ..forward();
    _life = AnimationController(vsync: this, duration: _hold)..forward();
    _holdTimer = Timer(_hold, _close);
    widget.onRequestClose(_close);
  }

  Future<void> _close() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _holdTimer?.cancel();
    _enter.duration = _exitDuration;
    await _enter.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  void _handleTap() {
    if (widget.level != ProgressToastLevel.step) return;
    final cb = widget.onOpen;
    _close();
    if (cb != null) cb();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _enter.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final mq = MediaQuery.of(context);
    return Positioned(
      top: 56 + mq.viewPadding.top,
      right: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: AnimatedBuilder(
          animation: _enter,
          builder: (_, child) {
            final t = Curves.easeOutCubic.transform(_enter.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - t)),
                child: Transform.scale(
                  alignment: Alignment.topRight,
                  scale: 0.96 + 0.04 * t,
                  child: child,
                ),
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: _buildShell(colors),
          ),
        ),
      ),
    );
  }

  Widget _buildShell(FacteurColors colors) {
    final accent = widget.level == ProgressToastLevel.step
        ? colors.primary
        : colors.success;

    final body = switch (widget.level) {
      ProgressToastLevel.micro => _MicroBody(accent: accent, toast: widget),
      ProgressToastLevel.section =>
        _SectionBody(accent: accent, toast: widget),
      ProgressToastLevel.step => _StepBody(toast: widget),
    };

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: widget.level == ProgressToastLevel.step
              ? Border.all(color: colors.primary.withValues(alpha: 0.15))
              : null,
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x2E3C2814),
              blurRadius: 18,
              spreadRadius: -6,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              body,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _LifeBar(controller: _life, accent: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LifeBar extends StatelessWidget {
  final AnimationController controller;
  final Color accent;

  const _LifeBar({required this.controller, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.04),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (1 - controller.value).clamp(0.0, 1.0),
              child: Container(color: accent.withValues(alpha: 0.45)),
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   NIVEAU 1 · B — Micro (article lu, 1/3) avec segments + shimmer
   ============================================================ */
class _MicroBody extends StatelessWidget {
  final Color accent;
  final _ProgressToast toast;

  const _MicroBody({required this.accent, required this.toast});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final current = toast.current ?? 1;
    final total = toast.total ?? 3;
    final label = toast.label ?? 'Action validée';

    return SizedBox(
      width: 200,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _PopTick(color: accent, size: 18, iconSize: 11),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$current/$total',
                  style: GoogleFonts.courierPrime(
                    fontSize: 9.5,
                    color: colors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: _Segments(
                current: current,
                total: total,
                accent: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segments extends StatefulWidget {
  final int current;
  final int total;
  final Color accent;

  const _Segments({
    required this.current,
    required this.total,
    required this.accent,
  });

  @override
  State<_Segments> createState() => _SegmentsState();
}

class _SegmentsState extends State<_Segments>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _shimmer.forward();
    });
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(widget.total, (i) {
        final filled = i < widget.current;
        final justFilled = i == widget.current - 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == widget.total - 1 ? 0 : 3),
            child: _Segment(
              filled: filled,
              shimmer: justFilled ? _shimmer : null,
              accent: widget.accent,
              fillDelay: Duration(milliseconds: 120 + i * 60),
            ),
          ),
        );
      }),
    );
  }
}

class _Segment extends StatefulWidget {
  final bool filled;
  final AnimationController? shimmer;
  final Color accent;
  final Duration fillDelay;

  const _Segment({
    required this.filled,
    required this.accent,
    required this.fillDelay,
    this.shimmer,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    if (widget.filled) {
      Future<void>.delayed(widget.fillDelay, () {
        if (mounted) _fill.forward();
      });
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: 0.07)),
            if (widget.filled)
              AnimatedBuilder(
                animation: _fill,
                builder: (_, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor:
                        Curves.easeOutCubic.transform(_fill.value),
                    child: Container(color: widget.accent),
                  ),
                ),
              ),
            if (widget.shimmer != null)
              AnimatedBuilder(
                animation: widget.shimmer!,
                builder: (_, __) {
                  final v = widget.shimmer!.value;
                  return FractionalTranslation(
                    translation: Offset(-1 + 2 * v, 0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x99FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PopTick extends StatefulWidget {
  final Color color;
  final double size;
  final double iconSize;

  const _PopTick({
    required this.color,
    required this.size,
    required this.iconSize,
  });

  @override
  State<_PopTick> createState() => _PopTickState();
}

class _PopTickState extends State<_PopTick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final v = _ctl.value;
        // overshoot: 0 → 1.15 → 1.0
        final scale = v < 0.6
            ? 0.4 + (1.15 - 0.4) * (v / 0.6)
            : 1.15 - 0.15 * ((v - 0.6) / 0.4);
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                PhosphorIcons.check(PhosphorIconsStyle.bold),
                color: Colors.white,
                size: widget.iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}

/* ============================================================
   NIVEAU 2 · B — Section terminée (enveloppe scellée)
   ============================================================ */
class _SectionBody extends StatelessWidget {
  final Color accent;
  final _ProgressToast toast;

  const _SectionBody({required this.accent, required this.toast});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final title = toast.sectionTitle ?? 'Section terminée';

    return SizedBox(
      width: 230,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.surface, colors.surfaceElevated],
          ),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.35)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SealEnvelope(accent: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SECTION CLASSÉE',
                      style: GoogleFonts.courierPrime(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: GoogleFonts.fraunces(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        height: 1.2,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lue de bout en bout · 100%',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        height: 1.3,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SealEnvelope extends StatefulWidget {
  final Color accent;

  const _SealEnvelope({required this.accent});

  @override
  State<_SealEnvelope> createState() => _SealEnvelopeState();
}

class _SealEnvelopeState extends State<_SealEnvelope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _seal;

  @override
  void initState() {
    super.initState();
    _seal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) _seal.forward();
    });
  }

  @override
  void dispose() {
    _seal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 28,
      child: Stack(
        children: [
          // Enveloppe parchemin
          Positioned.fill(
            child: CustomPaint(
              painter: _EnvelopePainter(
                background: const Color(0xFFFBF6EC),
                stroke: const Color(0x383C2814),
              ),
            ),
          ),
          // Sceau qui s'appose
          AnimatedBuilder(
            animation: _seal,
            builder: (_, __) {
              final v = _seal.value;
              // 0 → translateY(-90% scale 1.6, opacity 0)
              // 0.6 → translateY(-45% scale 0.88, opacity 1)
              // 1 → translateY(-50% scale 1, opacity 1)
              double scale;
              double yPct;
              if (v < 0.6) {
                final t = v / 0.6;
                scale = 1.6 - (1.6 - 0.88) * t;
                yPct = -0.90 + (-0.45 - -0.90) * t;
              } else {
                final t = (v - 0.6) / 0.4;
                scale = 0.88 + (1.0 - 0.88) * t;
                yPct = -0.45 + (-0.50 - -0.45) * t;
              }
              return Positioned(
                left: 36 / 2 - 8,
                top: 28 * 0.6 + yPct * 16,
                child: Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        PhosphorIcons.check(PhosphorIconsStyle.bold),
                        color: Colors.white,
                        size: 9,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  final Color background;
  final Color stroke;

  _EnvelopePainter({required this.background, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas.drawRRect(rrect, Paint()..color = background);
    final border = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rrect, border);
    // Rabat en V (lignes diagonales sur le haut)
    final flap = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = size.width / 2;
    final mid = size.height / 2;
    canvas.drawLine(Offset.zero, Offset(cx, mid), flap);
    canvas.drawLine(Offset(size.width, 0), Offset(cx, mid), flap);
  }

  @override
  bool shouldRepaint(_EnvelopePainter oldDelegate) =>
      background != oldDelegate.background || stroke != oldDelegate.stroke;
}

/* ============================================================
   NIVEAU 3 · B — Étape (cachet + halo + CTA)
   ============================================================ */
class _StepBody extends StatelessWidget {
  final _ProgressToast toast;

  const _StepBody({required this.toast});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final num = toast.stepNum ?? '01';
    final title = toast.stepTitle ?? 'Étape classée';

    return SizedBox(
      width: 244,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.64, 0),
            radius: 0.55,
            colors: [
              colors.primary.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CachetStamp(num: num, accent: colors.primary),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ÉTAPE · VALIDÉE',
                          style: GoogleFonts.courierPrime(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: GoogleFonts.fraunces(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            height: 1.15,
                            color: colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: CustomPaint(
                  painter: _DashedTopBorder(
                    color: colors.primary.withValues(alpha: 0.25),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Ouvrir le cachet',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                PhosphorIcons.arrowRight(),
                                size: 13,
                                color: colors.primary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatToday(),
                          style: GoogleFonts.courierPrime(
                            fontSize: 8.5,
                            color: colors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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

String _formatToday() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(now.day)}·${two(now.month)}·${two(now.year % 100)}';
}

class _CachetStamp extends StatefulWidget {
  final String num;
  final Color accent;

  const _CachetStamp({required this.num, required this.accent});

  @override
  State<_CachetStamp> createState() => _CachetStampState();
}

class _CachetStampState extends State<_CachetStamp>
    with TickerProviderStateMixin {
  late final AnimationController _drop;
  late final AnimationController _halo;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _halo.forward();
    });
  }

  @override
  void dispose() {
    _drop.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _halo,
            builder: (_, __) {
              final v = _halo.value;
              double opacity;
              if (v < 0.3) {
                opacity = (v / 0.3) * 0.5;
              } else {
                opacity = 0.5 * (1 - ((v - 0.3) / 0.7));
              }
              final scale = 0.7 + 0.8 * v;
              return IgnorePointer(
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _drop,
            builder: (_, child) {
              final v = _drop.value;
              double scale;
              double rotateDeg;
              if (v < 0.55) {
                final t = v / 0.55;
                scale = 1.6 - (1.6 - 0.92) * t;
                rotateDeg = -16 + (-2 - -16) * t;
              } else {
                final t = (v - 0.55) / 0.45;
                scale = 0.92 + (1.0 - 0.92) * t;
                rotateDeg = -2 + (-6 - -2) * t;
              }
              return Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: rotateDeg * 3.1415926 / 180,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: _StampBody(num: widget.num, accent: widget.accent),
          ),
        ],
      ),
    );
  }
}

class _StampBody extends StatelessWidget {
  final String num;
  final Color accent;

  const _StampBody({required this.num, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xD9FDFBF7),
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Bordure pointillée intérieure
          Padding(
            padding: const EdgeInsets.all(2),
            child: CustomPaint(
              size: const Size.square(38),
              painter: _DashedCirclePainter(
                color: accent.withValues(alpha: 0.5),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                num,
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: accent,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'CLASSÉE',
                style: GoogleFonts.courierPrime(
                  fontSize: 6,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;

  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    final path = Path()..addOval(rect);
    const dash = 2.0;
    const gap = 2.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _DashedTopBorder extends CustomPainter {
  final Color color;

  _DashedTopBorder({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + dash).clamp(0, size.width), 0),
          paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedTopBorder oldDelegate) =>
      color != oldDelegate.color;
}
