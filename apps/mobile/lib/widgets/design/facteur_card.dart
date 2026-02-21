import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:facteur/config/theme.dart';

class FacteurCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final ScrollPhysics?
      scrollPhysics; // For cases where we might want to pass physics down
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final List<BoxShadow>? boxShadow;

  const FacteurCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.scrollPhysics,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
    this.boxShadow,
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius:
            BorderRadius.circular(widget.borderRadius ?? FacteurRadius.medium),
        boxShadow: widget.boxShadow ?? [
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

    if (widget.onTap == null && widget.onLongPressStart == null) {
      return cardContent;
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap != null
          ? () async {
              await HapticFeedback.mediumImpact();
              widget.onTap?.call();
            }
          : null,
      onLongPressStart: widget.onLongPressStart != null
          ? (details) async {
              await HapticFeedback.mediumImpact();
              widget.onLongPressStart?.call(details);
            }
          : null,
      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPressEnd,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: cardContent,
      ),
    );
  }
}
