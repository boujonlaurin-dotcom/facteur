import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Full-width progress bar for digest completion with contextual messages
/// and pulse animation on increment.
///
/// Shows a continuous bar (not dots) + "X/N" counter + contextual message.
/// Designed to sit fixed above scrollable digest content.
class DigestProgressBar extends StatefulWidget {
  final int processedCount;
  final int totalCount;

  const DigestProgressBar({
    super.key,
    required this.processedCount,
    required this.totalCount,
  });

  @override
  State<DigestProgressBar> createState() => _DigestProgressBarState();
}

class _DigestProgressBarState extends State<DigestProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _previousCount = widget.processedCount;
  }

  @override
  void didUpdateWidget(DigestProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.processedCount > _previousCount) {
      _pulseController.forward().then((_) => _pulseController.reverse());
    }
    _previousCount = widget.processedCount;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  double get _progress =>
      widget.totalCount > 0 ? widget.processedCount / widget.totalCount : 0;

  String get _message {
    if (widget.processedCount == 0) return "C'est parti !";
    if (_progress < 0.5) return 'Bon début';
    if (_progress < 1.0) return 'Encore un peu...';
    return 'Bravo !';
  }

  Color _progressColor(FacteurColors colors) {
    if (_progress >= 1.0) return colors.success;
    if (_progress >= 0.6) return FacteurColors.sWarning;
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = _progressColor(colors);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_pulseController.value * 0.03),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bar + counter row
            Row(
              children: [
                // Continuous progress bar
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        // Background
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // Filled portion
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          height: 6,
                          width: _progress *
                              (MediaQuery.of(context).size.width -
                                  FacteurSpacing.space4 * 2 -
                                  // account for counter text + spacing
                                  50),
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space3),
                // Counter "X/N"
                Text(
                  '${widget.processedCount}/${widget.totalCount}',
                  style: TextStyle(
                    color: _progress >= 1.0 ? colors.success : colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Contextual message
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _message,
                key: ValueKey(_message),
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
