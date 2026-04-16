import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../config/theme.dart';

/// Terracotta accent color for priority indicators.
const Color _terracotta = Color(0xFFE07A5F);

/// 3-cran compact slider for priority weighting.
///
/// Maps multiplier values to visual blocks:
/// - 0.2 (Moins):   [filled] [empty] [empty]
/// - 1.0 (Normal):  [filled] [filled] [empty]
/// - 2.0 (Plus):    [filled] [filled] [filled]
///
/// Each block encodes two layers:
/// - **Border** = intentional setting (terracotta if active, grey otherwise)
/// - **Internal fill** = learned usage weight (proportional, theme primary color)
///
/// If [usageWeight] is null, behaves exactly as before (no internal fill).
class PrioritySlider extends StatefulWidget {
  final double currentMultiplier;
  final ValueChanged<double> onChanged;
  final List<String> labels;
  final double? usageWeight;
  final VoidCallback? onReset;

  const PrioritySlider({
    super.key,
    required this.currentMultiplier,
    required this.onChanged,
    this.labels = const ['Moins', 'Normal', 'Plus'],
    this.usageWeight,
    this.onReset,
  });

  @override
  State<PrioritySlider> createState() => _PrioritySliderState();
}

class _PrioritySliderState extends State<PrioritySlider>
    with SingleTickerProviderStateMixin {
  static const _multipliers = [0.2, 1.0, 2.0];
  static const _blockWidth = 28.0;
  static const _blockHeight = 12.0;
  static const _blockGap = 3.0;

  late AnimationController _popController;
  late Animation<double> _popAnimation;
  int _poppedBlock = -1;

  int get _currentCran {
    if (widget.currentMultiplier <= 0.5) return 1;
    if (widget.currentMultiplier <= 1.0) return 2;
    return 3;
  }

  String get _label {
    final index = _currentCran - 1;
    if (index < widget.labels.length) return widget.labels[index];
    return '';
  }

  /// Normalize a multiplier (0.2/1.0/2.0) to 0.0-1.0 range for comparison.
  double _multiplierToNormalized(double m) {
    if (m <= 0.5) return 0.0;
    if (m <= 1.0) return 0.5;
    return 1.0;
  }

  /// Whether the reset button should be visible.
  bool get _showReset {
    if (widget.usageWeight == null || widget.onReset == null) return false;
    final settingNorm = _multiplierToNormalized(widget.currentMultiplier);
    return (widget.usageWeight! - settingNorm).abs() > 0.15;
  }

  /// Fill ratio for a single block based on usageWeight.
  double _blockFillRatio(int cran) {
    if (widget.usageWeight == null) return 0.0;
    final w = widget.usageWeight!.clamp(0.0, 1.0);
    final blockStart = (cran - 1) / 3.0;
    final blockEnd = cran / 3.0;
    if (w <= blockStart) return 0.0;
    if (w >= blockEnd) return 1.0;
    return (w - blockStart) / (blockEnd - blockStart);
  }

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _popAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _popController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    // Blocks are right-aligned; compute tap relative to block area
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final totalWidth = renderBox.size.width;
    const blocksWidth = _blockWidth * 3 + _blockGap * 2;
    final blocksStart = totalWidth - blocksWidth;
    final tapX = details.localPosition.dx - blocksStart;

    if (tapX < 0) return; // Tapped on label area, ignore

    const blockArea = blocksWidth / 3;
    int tappedCran;
    if (tapX < blockArea) {
      tappedCran = 1;
    } else if (tapX < 2 * blockArea) {
      tappedCran = 2;
    } else {
      tappedCran = 3;
    }

    if (tappedCran != _currentCran) {
      widget.onChanged(_multipliers[tappedCran - 1]);
      setState(() => _poppedBlock = tappedCran);
      _popController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTapDown: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Persistent label
            Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 6),
            // 3 blocks with pop animation
            AnimatedBuilder(
              animation: _popAnimation,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBlock(1, colors),
                    const SizedBox(width: _blockGap),
                    _buildBlock(2, colors),
                    const SizedBox(width: _blockGap),
                    _buildBlock(3, colors),
                  ],
                );
              },
            ),
            // Reset button
            if (_showReset)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: GestureDetector(
                  onTap: widget.onReset,
                  child: Icon(
                    PhosphorIcons.arrowCounterClockwise(PhosphorIconsStyle.regular),
                    size: 16,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(int cran, FacteurColors colors) {
    final filled = _currentCran >= cran;
    final shouldPop = _poppedBlock == cran && _popController.isAnimating;
    final scale = shouldPop ? _popAnimation.value : 1.0;
    final fillRatio = _blockFillRatio(cran);
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: _blockWidth,
        height: _blockHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // Base layer: border/background (existing behavior)
              Container(
                width: _blockWidth,
                height: _blockHeight,
                color: filled
                    ? _terracotta
                    : colors.textTertiary.withOpacity(0.3),
              ),
              // Overlay: internal fill proportional to usage weight
              if (fillRatio > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _blockWidth * fillRatio,
                  child: Container(
                    color: colors.textSecondary.withOpacity(filled ? 0.5 : 0.3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
