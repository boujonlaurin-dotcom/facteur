import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Terracotta accent color for custom topics.
const Color _terracotta = Color(0xFFE07A5F);

/// 3-cran compact slider for topic priority.
///
/// Maps multiplier values to visual blocks:
/// - 0.5 (Suivi):         [filled] [empty] [empty]
/// - 1.0 (Intéressé):     [filled] [filled] [empty]
/// - 2.0 (Fort intérêt):  [filled] [filled] [filled]
class TopicPrioritySlider extends StatefulWidget {
  final double currentMultiplier;
  final ValueChanged<double> onChanged;
  final double width;

  const TopicPrioritySlider({
    super.key,
    required this.currentMultiplier,
    required this.onChanged,
    this.width = 90,
  });

  @override
  State<TopicPrioritySlider> createState() => _TopicPrioritySliderState();
}

class _TopicPrioritySliderState extends State<TopicPrioritySlider> {
  bool _showLabel = false;
  Timer? _labelTimer;

  static const _multipliers = [0.5, 1.0, 2.0];

  int get _currentCran {
    if (widget.currentMultiplier <= 0.5) return 1;
    if (widget.currentMultiplier <= 1.0) return 2;
    return 3;
  }

  String get _label {
    switch (_currentCran) {
      case 1:
        return 'Suivi';
      case 2:
        return 'Intéressé';
      case 3:
        return 'Fort intérêt';
      default:
        return '';
    }
  }

  void _showLabelBriefly() {
    _labelTimer?.cancel();
    setState(() => _showLabel = true);
    _labelTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showLabel = false);
    });
  }

  void _handleTap(TapDownDetails details) {
    final blockWidth = (widget.width - 6) / 3; // 3 blocks with 2 gaps of 3px
    final tapX = details.localPosition.dx;

    int tappedCran;
    if (tapX < blockWidth + 1.5) {
      tappedCran = 1;
    } else if (tapX < 2 * blockWidth + 4.5) {
      tappedCran = 2;
    } else {
      tappedCran = 3;
    }

    if (tappedCran != _currentCran) {
      widget.onChanged(_multipliers[tappedCran - 1]);
    }
    _showLabelBriefly();
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Floating label with fade + size animation
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: SizedBox(
              height: _showLabel ? 16.0 : 0.0,
              child: AnimatedOpacity(
                opacity: _showLabel ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _terracotta,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: _showLabel ? 2.0 : 0.0),
          // 3 blocks with 44px min touch target
          GestureDetector(
            onTapDown: _handleTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Block(filled: _currentCran >= 1, color: _terracotta, emptyColor: colors.textTertiary),
                  const SizedBox(width: 3),
                  _Block(filled: _currentCran >= 2, color: _terracotta, emptyColor: colors.textTertiary),
                  const SizedBox(width: 3),
                  _Block(filled: _currentCran >= 3, color: _terracotta, emptyColor: colors.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final bool filled;
  final Color color;
  final Color emptyColor;

  const _Block({
    required this.filled,
    required this.color,
    required this.emptyColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 12,
      decoration: BoxDecoration(
        color: filled ? color : emptyColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
