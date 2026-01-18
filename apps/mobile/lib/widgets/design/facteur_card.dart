import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:facteur/config/theme.dart';

class FacteurCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final ScrollPhysics?
      scrollPhysics; // For cases where we might want to pass physics down
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  const FacteurCard({
    super.key,
    required this.child,
    this.onTap,
    this.scrollPhysics,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
  });

  @override
  State<FacteurCard> createState() => _FacteurCardState();
}

class _FacteurCardState extends State<FacteurCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FacteurDurations.fast, // Quick response for touch
      reverseDuration: FacteurDurations.medium, // Slower release for "weight"
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine color based on context if not provided
    final cardColor = widget.backgroundColor ?? context.facteurColors.surface;

    final Widget cardContent = Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius:
            BorderRadius.circular(widget.borderRadius ?? FacteurRadius.medium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: widget.padding ?? const EdgeInsets.all(FacteurSpacing.space4),
      child: widget.child,
    );

    if (widget.onTap == null) {
      return cardContent;
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () async {
        // Haptic Feedback "Opening Envelope" feel
        await HapticFeedback.mediumImpact();
        widget.onTap?.call();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: cardContent,
      ),
    );
  }
}
