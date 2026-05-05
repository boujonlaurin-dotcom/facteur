import 'package:flutter/material.dart';

import '../../../widgets/design/priority_slider.dart';

/// 3-cran compact slider for topic priority.
///
/// Delegates to the shared [PrioritySlider] widget with topic-specific labels.
class TopicPrioritySlider extends StatelessWidget {
  final double currentMultiplier;
  final ValueChanged<double> onChanged;
  final double? usageWeight;
  final VoidCallback? onReset;
  final bool fillWidth;

  const TopicPrioritySlider({
    super.key,
    required this.currentMultiplier,
    required this.onChanged,
    this.usageWeight,
    this.onReset,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return PrioritySlider(
      currentMultiplier: currentMultiplier,
      onChanged: onChanged,
      labels: const ['Moins', 'Normal', 'Plus'],
      usageWeight: usageWeight,
      onReset: onReset,
      fillWidth: fillWidth,
    );
  }
}
