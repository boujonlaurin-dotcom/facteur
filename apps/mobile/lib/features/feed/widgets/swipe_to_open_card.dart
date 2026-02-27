import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Wraps a card to allow swiping right to open and optionally left to dismiss.
///
/// Right swipe: reveals a blue "Lire" background. Past threshold → [onSwipeOpen].
/// Left swipe: reveals a gray "Masquer" background. Past threshold → card slides
/// out and [onSwipeDismiss] fires. Left swipe only active when [onSwipeDismiss]
/// is non-null (backwards compatible).
///
/// [enableHintAnimation]: plays a subtle micro-slide to hint at left-swipe
/// discoverability. Should only be true once per app lifetime.
class SwipeToOpenCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeOpen;
  final VoidCallback? onSwipeDismiss;
  final bool enableHintAnimation;
  final VoidCallback? onHintAnimationComplete;

  const SwipeToOpenCard({
    super.key,
    required this.child,
    required this.onSwipeOpen,
    this.onSwipeDismiss,
    this.enableHintAnimation = false,
    this.onHintAnimationComplete,
  });

  @override
  State<SwipeToOpenCard> createState() => _SwipeToOpenCardState();
}

class _SwipeToOpenCardState extends State<SwipeToOpenCard>
    with TickerProviderStateMixin {
  double _dragExtent = 0;
  bool _dragUnderway = false;
  bool _hasTriggered = false;
  bool _isDismissing = false;

  late AnimationController _resetController;
  double _resetStartExtent = 0;

  late AnimationController _dismissController;
  late AnimationController _hintController;
  bool _hintPlayed = false;

  /// Fraction of screen width the card must be dragged to trigger.
  static const double _threshold = 0.25;

  /// Minimum fling velocity (px/s) to trigger regardless of distance.
  static const double _flingVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onResetTick);

    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onDismissTick);

    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onHintTick);

    if (widget.enableHintAnimation && widget.onSwipeDismiss != null) {
      _scheduleHintAnimation();
    }
  }

  @override
  void didUpdateWidget(SwipeToOpenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-schedule hint if enableHintAnimation flipped to true after init
    if (widget.enableHintAnimation &&
        !oldWidget.enableHintAnimation &&
        widget.onSwipeDismiss != null &&
        !_hintPlayed) {
      _scheduleHintAnimation();
    }
  }

  @override
  void dispose() {
    _resetController.dispose();
    _dismissController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _scheduleHintAnimation() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_hintPlayed && !_dragUnderway) {
        _hintPlayed = true;
        _hintController.forward().then((_) {
          if (mounted) {
            widget.onHintAnimationComplete?.call();
          }
        });
      }
    });
  }

  void _onResetTick() {
    if (!_isDismissing) {
      setState(() {
        _dragExtent = _resetStartExtent * (1 - _resetController.value);
      });
    }
  }

  void _onDismissTick() {
    setState(() {
      final screenWidth = MediaQuery.of(context).size.width;
      // Animate from current drag extent to -screenWidth
      _dragExtent = _dismissStartExtent +
          (_dismissController.value * (-screenWidth - _dismissStartExtent));
    });
  }

  double _dismissStartExtent = 0;

  void _onHintTick() {
    if (!_dragUnderway && !_isDismissing) {
      setState(() {
        // Sine wave: 0 → -20 → 0
        final t = _hintController.value;
        _dragExtent = -40.0 * Curves.easeInOut.transform(
          t <= 0.5 ? t * 2 : (1.0 - t) * 2,
        );
      });
    }
  }

  void _handleDragStart(DragStartDetails details) {
    if (_isDismissing) return;
    _dragUnderway = true;
    _hasTriggered = false;
    _resetController.stop();
    _hintController.stop();
    setState(() => _dragExtent = 0);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragUnderway || _isDismissing) return;
    final delta = details.primaryDelta ?? 0;
    setState(() {
      if (widget.onSwipeDismiss != null) {
        // Bidirectional: allow both positive (right) and negative (left)
        _dragExtent = _dragExtent + delta;
      } else {
        // Only allow right swipe (original behavior)
        _dragExtent = (_dragExtent + delta).clamp(0.0, double.infinity);
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragUnderway || _isDismissing) return;
    _dragUnderway = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0;
    final ratio = _dragExtent / screenWidth;

    // Right swipe: open
    if (!_hasTriggered && _dragExtent > 0 &&
        (ratio > _threshold || velocity > _flingVelocity)) {
      _hasTriggered = true;
      HapticFeedback.mediumImpact();
      widget.onSwipeOpen();
      if (!mounted) return;
      _snapBack();
      return;
    }

    // Left swipe: dismiss
    if (!_hasTriggered && _dragExtent < 0 && widget.onSwipeDismiss != null &&
        (ratio < -_threshold || velocity < -_flingVelocity)) {
      _hasTriggered = true;
      _isDismissing = true;
      HapticFeedback.mediumImpact();
      _dismissStartExtent = _dragExtent;
      _dismissController.forward(from: 0).then((_) {
        if (mounted) {
          widget.onSwipeDismiss!();
        }
      });
      return;
    }

    _snapBack();
  }

  void _snapBack() {
    if (_dragExtent == 0) return;
    _resetStartExtent = _dragExtent;
    _resetController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final colors = context.facteurColors;

    // Right swipe progress (0..1)
    final rightProgress = _dragExtent > 0
        ? (_dragExtent / (screenWidth * _threshold)).clamp(0.0, 1.0)
        : 0.0;

    // Left swipe progress (0..1)
    final leftProgress = _dragExtent < 0
        ? (-_dragExtent / (screenWidth * _threshold)).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        children: [
          // Right-swipe background: blue "Lire"
          if (_dragExtent > 0)
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 24),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.06 * rightProgress),
                  borderRadius: BorderRadius.circular(FacteurRadius.small),
                ),
                child: Opacity(
                  opacity: rightProgress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                        color: colors.primary.withValues(alpha: 0.5),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lire',
                        style: TextStyle(
                          color: colors.primary.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Left-swipe background: gray "Masquer"
          if (_dragExtent < 0)
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: colors.textSecondary
                      .withValues(alpha: 0.08 * leftProgress),
                  borderRadius: BorderRadius.circular(FacteurRadius.small),
                ),
                child: Opacity(
                  opacity: leftProgress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Masquer',
                        style: TextStyle(
                          color: colors.textSecondary.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.bold),
                        color: colors.textSecondary.withValues(alpha: 0.5),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // The card, translated horizontally
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
