import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Mini FAB with an internal circular bias-distribution ring and eye icon.
/// Same size/shape as other reader FABs (bookmark, note).
class PerspectivesPill extends StatefulWidget {
  final Map<String, int> biasDistribution;
  final bool isLoading;
  final bool isEmpty;
  final VoidCallback onTap;

  const PerspectivesPill({
    super.key,
    required this.biasDistribution,
    required this.isLoading,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  State<PerspectivesPill> createState() => _PerspectivesPillState();
}

class _PerspectivesPillState extends State<PerspectivesPill>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    ));

    _loadingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.isLoading) _loadingController.repeat();

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void didUpdateWidget(PerspectivesPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _loadingController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _loadingController.stop();
      _loadingController.reset();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final bool isActive = !widget.isLoading && !widget.isEmpty;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Opacity(
          opacity: widget.isEmpty ? 0.4 : 1.0,
          child: SizedBox(
            width: 55,
            height: 55,
            child: FloatingActionButton(
              onPressed: isActive ? widget.onTap : null,
              backgroundColor: Colors.white,
              elevation: 2,
              heroTag: 'perspectives_fab',
              tooltip: 'Autres points de vue',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Circular bias ring inside the FAB
                  if (widget.isLoading)
                    AnimatedBuilder(
                      animation: _loadingController,
                      builder: (context, child) => CustomPaint(
                        size: const Size(41, 41),
                        painter: _BiasRingPainter.loading(
                          colors,
                          _loadingController.value,
                        ),
                      ),
                    )
                  else
                    CustomPaint(
                      size: const Size(41, 41),
                      painter: widget.isEmpty
                          ? _BiasRingPainter.empty(colors)
                          : _BiasRingPainter(
                              distribution: widget.biasDistribution,
                              colors: colors,
                            ),
                    ),
                  // Eye icon (smaller to fit inside the ring)
                  Icon(
                    PhosphorIcons.eye(PhosphorIconsStyle.regular),
                    size: 21,
                    color: isActive
                        ? colors.textPrimary
                        : colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a circular proportional bias-distribution ring.
class _BiasRingPainter extends CustomPainter {
  final Map<String, int> distribution;
  final FacteurColors colors;
  final bool _isLoading;
  final bool _isEmpty;
  final double _loadingProgress;

  static const double _strokeWidth = 2.5;
  static const double _gapDegrees = 6.0;

  _BiasRingPainter({
    required this.distribution,
    required this.colors,
  })  : _isLoading = false,
        _isEmpty = false,
        _loadingProgress = 0;

  _BiasRingPainter.loading(this.colors, this._loadingProgress)
      : distribution = const {},
        _isLoading = true,
        _isEmpty = false;

  _BiasRingPainter.empty(this.colors)
      : distribution = const {},
        _isLoading = false,
        _isEmpty = true,
        _loadingProgress = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (_strokeWidth / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    if (_isEmpty) {
      paint.color = colors.textTertiary.withValues(alpha: 0.2);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    if (_isLoading) {
      paint.color = colors.textTertiary.withValues(alpha: 0.3);
      final startAngle =
          _loadingProgress * 2 * math.pi - math.pi / 2;
      canvas.drawArc(rect, startAngle, 2 * math.pi / 3, false, paint);
      return;
    }

    // 3 merged segments: Gauche, Centre, Droite
    final left =
        (distribution['left'] ?? 0) + (distribution['center-left'] ?? 0);
    final center_ = distribution['center'] ?? 0;
    final right =
        (distribution['center-right'] ?? 0) + (distribution['right'] ?? 0);

    final segments = [
      (left, colors.biasLeft),
      (center_, colors.biasCenter),
      (right, colors.biasRight),
    ].where((s) => s.$1 > 0).toList();

    final total = segments.fold<int>(0, (sum, s) => sum + s.$1);
    if (total == 0) return;

    const gapRadians = _gapDegrees * math.pi / 180;
    final totalGap = gapRadians * segments.length;
    final availableSweep = 2 * math.pi - totalGap;

    var startAngle = -math.pi / 2; // Start from top

    for (final seg in segments) {
      final sweep = (seg.$1 / total) * availableSweep;
      paint.color = seg.$2;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep + gapRadians;
    }
  }

  @override
  bool shouldRepaint(covariant _BiasRingPainter oldDelegate) {
    return oldDelegate.distribution != distribution ||
        oldDelegate._isLoading != _isLoading ||
        oldDelegate._isEmpty != _isEmpty ||
        oldDelegate._loadingProgress != _loadingProgress;
  }
}
