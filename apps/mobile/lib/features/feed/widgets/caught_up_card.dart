import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// "Tu es à jour" nudge card displayed inline in the feed
/// when the user has consumed enough articles for the day.
///
/// Provides positive closure without blocking or frustrating the user.
class CaughtUpCard extends StatefulWidget {
  final VoidCallback? onDismiss;

  const CaughtUpCard({super.key, this.onDismiss});

  @override
  State<CaughtUpCard> createState() => _CaughtUpCardState();
}

class _CaughtUpCardState extends State<CaughtUpCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Animate in on mount
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    setState(() => _isDismissed = true);
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
            padding: const EdgeInsets.all(FacteurSpacing.space6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(
                color: colors.success.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIcons.coffee(PhosphorIconsStyle.duotone),
                    size: 28,
                    color: colors.success,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // Title
                Text(
                  'Tu es à jour !',
                  style: textTheme.displaySmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FacteurSpacing.space2),

                // Message
                Text(
                  'Que dis-tu d\'une pause ?\nRien ne vaut un point de temps loin des écrans.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // Dismiss hint
                Text(
                  'Appuie pour continuer',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
