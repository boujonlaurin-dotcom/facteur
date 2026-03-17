import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import 'feedback_bottom_sheet.dart';

/// Inline closure block at the end of the editorial digest (D7).
/// Displays closureText + ctaText with a fade-in animation.
class ClosureBlock extends StatefulWidget {
  final String closureText;
  final String? ctaText;

  const ClosureBlock({
    super.key,
    required this.closureText,
    this.ctaText,
  });

  @override
  State<ClosureBlock> createState() => _ClosureBlockState();
}

class _ClosureBlockState extends State<ClosureBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // Start animation after a short delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2C1E10);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.closureText,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.ctaText != null) ...[
                const SizedBox(height: 16),
                Text(
                  widget.ctaText!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const FeedbackBottomSheet(),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Donner un retour'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
