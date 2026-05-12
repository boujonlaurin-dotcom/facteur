import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Terracotta accent — discreet "removal" semantic shared with the inline
/// feedback banner that replaces a dismissed card.
const Color _terracotta = Color(0xFFE07A5F);

/// Wraps a card to allow swiping right to open and optionally left to dismiss.
///
/// Right swipe: reveals a blue "Lire" background. Past threshold → [onSwipeOpen].
/// Left swipe: reveals a discreet terracotta "Masquer" background. Past
/// threshold → card snaps back and [onSwipeDismiss] fires (parent typically
/// replaces the card with an inline feedback banner). Left swipe only active
/// when [onSwipeDismiss] is non-null (backwards compatible).
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
  final bool _isDismissing = false;

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
      duration: const Duration(milliseconds: 2800),
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
    Future.delayed(const Duration(milliseconds: 2200), () {
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

  final double _dismissStartExtent = 0;

  void _onHintTick() {
    if (!_dragUnderway && !_isDismissing) {
      setState(() {
        // Séquence bidirectionnelle douce : glisse à droite puis à gauche.
        // Amplitude réduite (45 px) + courbe ease-in-out lente pour rester
        // discrète et non-intimidante.
        final t = _hintController.value;
        final phase = t < 0.5 ? t * 2 : (t - 0.5) * 2;
        final direction = t < 0.5 ? 1.0 : -1.0;
        final shape = phase <= 0.5 ? phase * 2 : (1.0 - phase) * 2;
        _dragExtent =
            direction * 45.0 * Curves.easeInOutSine.transform(shape);
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
    if (!_hasTriggered &&
        _dragExtent > 0 &&
        (ratio > _threshold || velocity > _flingVelocity)) {
      _hasTriggered = true;
      HapticFeedback.mediumImpact();
      widget.onSwipeOpen();
      if (!mounted) return;
      _snapBack();
      return;
    }

    // Left swipe: snap back and fire callback (Epic 12: opens bottom sheet)
    if (!_hasTriggered &&
        _dragExtent < 0 &&
        widget.onSwipeDismiss != null &&
        (ratio < -_threshold || velocity < -_flingVelocity)) {
      _hasTriggered = true;
      HapticFeedback.mediumImpact();
      _snapBack();
      widget.onSwipeDismiss!();
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
                  color: colors.primary.withOpacity(0.06 * rightProgress),
                  borderRadius: BorderRadius.circular(FacteurRadius.small),
                ),
                child: Opacity(
                  opacity: rightProgress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                        color: colors.primary.withOpacity(0.5),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lire',
                        style: TextStyle(
                          color: colors.primary.withOpacity(0.5),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Left-swipe background: discreet terracotta "Masquer"
          if (_dragExtent < 0)
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: _terracotta.withOpacity(0.07 * leftProgress),
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
                          color: _terracotta.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        PhosphorIcons.eyeClosed(PhosphorIconsStyle.bold),
                        color: _terracotta.withOpacity(0.7),
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
