import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/serein_colors.dart';
import '../providers/serein_toggle_provider.dart';

/// iOS Settings-style 2-segment toggle: "Normal" / "Serein".
///
/// The selected segment's indicator fills the pill edge-to-edge (minimal
/// internal padding). A spring animation with scale bounce drives the
/// sliding transition. Animation starts immediately on tap (not deferred
/// to post-frame) so it's never killed by parent rebuilds.
class SereinToggleChip extends ConsumerStatefulWidget {
  const SereinToggleChip({super.key});

  static const double _width = 148;
  static const double _height = 28;
  // Minimal padding — indicator almost flush with pill border
  static const double _padding = 1.5;

  @override
  ConsumerState<SereinToggleChip> createState() => _SereinToggleChipState();
}

class _SereinToggleChipState extends ConsumerState<SereinToggleChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _scaleAnimation;

  bool _isSerein = false;

  static double get _innerWidth =>
      SereinToggleChip._width - SereinToggleChip._padding * 2;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _isSerein = ref.read(sereinToggleProvider).enabled;
    _controller.value = _isSerein ? 1.0 : 0.0;

    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeOutBack.flipped,
    );

    // Scale: 1.0 → 1.08 at midpoint → 1.0 at end
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 65),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  /// Toggle animation + provider in one shot.
  /// Animation starts IMMEDIATELY on tap — no post-frame delay.
  void _toggle() {
    final newValue = !_isSerein;
    HapticFeedback.mediumImpact();

    // 1. Start animation immediately (same frame as tap)
    setState(() => _isSerein = newValue);
    if (newValue) {
      _controller.forward();
    } else {
      _controller.reverse();
    }

    // 2. Update provider (triggers parent rebuild, but our state is already set)
    ref.read(sereinToggleProvider.notifier).toggle();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sync with external state changes (e.g. initFromApi on first load)
    final externalSerein = ref.watch(
      sereinToggleProvider.select((s) => s.enabled),
    );
    if (externalSerein != _isSerein && !_controller.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && externalSerein != _isSerein) {
          setState(() => _isSerein = externalSerein);
          _controller.value = externalSerein ? 1.0 : 0.0;
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return SizedBox(
      width: SereinToggleChip._width,
      height: SereinToggleChip._height,
      child: Container(
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _slideAnimation.value;
            final scale = _scaleAnimation.value;

            // Accent color interpolation
            final accent = Color.lerp(
              SereinColors.normalColor,
              SereinColors.sereinColor,
              t,
            )!;

            // Indicator slides from left to right
            final halfWidth = _innerWidth * 0.5;
            final indicatorLeft =
                SereinToggleChip._padding + t * halfWidth;

            return Stack(
              children: [
                // Sliding indicator — flush with pill edges
                Positioned(
                  left: indicatorLeft,
                  top: SereinToggleChip._padding,
                  bottom: SereinToggleChip._padding,
                  width: halfWidth,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                                alpha: isDark ? 0.20 : 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Segment labels
                Row(
                  children: [
                    const SizedBox(width: SereinToggleChip._padding),
                    _buildSegment(
                      width: halfWidth,
                      icon: SereinColors.normalIcon,
                      label: 'Normal',
                      selectedColor: SereinColors.normalColor,
                      isDark: isDark,
                      t: 1.0 - t,
                      onTap: _isSerein ? _toggle : null,
                    ),
                    _buildSegment(
                      width: halfWidth,
                      icon: SereinColors.sereinIcon,
                      label: 'Serein',
                      selectedColor: SereinColors.sereinColor,
                      isDark: isDark,
                      t: t,
                      onTap: !_isSerein ? _toggle : null,
                    ),
                    const SizedBox(width: SereinToggleChip._padding),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSegment({
    required double width,
    required IconData icon,
    required String label,
    required Color selectedColor,
    required bool isDark,
    required double t,
    required VoidCallback? onTap,
  }) {
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.40);
    final color = Color.lerp(unselectedColor, selectedColor, t)!;
    final fontWeight = t > 0.5 ? FontWeight.w600 : FontWeight.w400;
    final iconSize = 11.0 + t;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: SereinToggleChip._height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: fontWeight,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
