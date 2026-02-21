import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Wraps a card to allow swiping right to trigger navigation.
///
/// Provides visual feedback: the card slides right, revealing
/// an arrow icon on a tinted background. On release past the
/// threshold (or with sufficient fling velocity), [onSwipeOpen]
/// is called. Otherwise the card springs back.
class SwipeToOpenCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeOpen;

  const SwipeToOpenCard({
    super.key,
    required this.child,
    required this.onSwipeOpen,
  });

  @override
  State<SwipeToOpenCard> createState() => _SwipeToOpenCardState();
}

class _SwipeToOpenCardState extends State<SwipeToOpenCard>
    with SingleTickerProviderStateMixin {
  double _dragExtent = 0;
  bool _dragUnderway = false;
  bool _hasTriggered = false;

  late AnimationController _resetController;
  double _resetStartExtent = 0;

  /// Fraction of screen width the card must be dragged to trigger open.
  static const double _openThreshold = 0.25;

  /// Minimum fling velocity (px/s) to trigger open regardless of distance.
  static const double _flingVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onResetTick);
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onResetTick() {
    setState(() {
      _dragExtent = _resetStartExtent * (1 - _resetController.value);
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _dragUnderway = true;
    _hasTriggered = false;
    _resetController.stop();
    setState(() => _dragExtent = 0);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragUnderway) return;
    final delta = details.primaryDelta ?? 0;
    setState(() {
      // Only allow right swipe (positive values)
      _dragExtent = (_dragExtent + delta).clamp(0.0, double.infinity);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragUnderway) return;
    _dragUnderway = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0;
    final ratio = _dragExtent / screenWidth;

    if (!_hasTriggered &&
        (ratio > _openThreshold || velocity > _flingVelocity)) {
      _hasTriggered = true;
      HapticFeedback.mediumImpact();
      widget.onSwipeOpen();

      // The callback may have unmounted the widget (e.g. navigation).
      // Do not touch the AnimationController after disposal.
      if (!mounted) return;
    }

    _snapBack();
  }

  void _snapBack() {
    if (_dragExtent <= 0) return;
    _resetStartExtent = _dragExtent;
    _resetController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progress =
        (_dragExtent / (screenWidth * _openThreshold)).clamp(0.0, 1.0);
    final colors = context.facteurColors;

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        // Clip.hardEdge: card is clipped at its right edge as it slides
        children: [
          // Background revealed by the swipe
          if (_dragExtent > 0)
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 24),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.06 * progress),
                  borderRadius: BorderRadius.circular(FacteurRadius.small),
                ),
                child: Opacity(
                  opacity: progress,
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
