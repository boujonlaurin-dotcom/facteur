import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Wrapper widget that shows a "Lu" (Read) overlay when content is consumed
/// before the card is removed from the feed.
class AnimatedFeedCard extends StatefulWidget {
  final Widget child;
  final bool isConsumed;
  final VoidCallback? onAnimationComplete;

  const AnimatedFeedCard({
    super.key,
    required this.child,
    required this.isConsumed,
    this.onAnimationComplete,
  });

  @override
  State<AnimatedFeedCard> createState() => _AnimatedFeedCardState();
}

class _AnimatedFeedCardState extends State<AnimatedFeedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeInAnimation;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _scaleAnimation;

  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Fade in overlay (0-30%)
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    ));

    // Fade out overlay (70-100%)
    _fadeOutAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
    ));

    // Scale badge (0-40%)
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(AnimatedFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConsumed && !oldWidget.isConsumed && !_showOverlay) {
      setState(() {
        _showOverlay = true;
      });
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _currentOpacity {
    if (_controller.value <= 0.7) {
      return _fadeInAnimation.value;
    } else {
      return _fadeOutAnimation.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show overlay if not consumed
    if (!_showOverlay) {
      return widget.child;
    }

    return Stack(
      children: [
        // Original card
        widget.child,

        // "Lu" overlay
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _currentOpacity,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.checkCircle(
                                  PhosphorIconsStyle.fill),
                              color: Colors.white,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Lu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
