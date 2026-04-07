import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Horizontal bar showing the political spectrum distribution (3 segments).
/// Merges 5 bias categories into 3: Gauche, Centre, Droite.
class BiasSpectrumBar extends StatelessWidget {
  final Map<String, int>? biasDistribution;
  final bool showLabels;

  const BiasSpectrumBar({
    super.key,
    this.biasDistribution,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (biasDistribution == null || biasDistribution!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Merge 5 → 3 (same logic as _BiasRingPainter in perspectives_pill.dart)
    final left = (biasDistribution!['left'] ?? 0) +
        (biasDistribution!['center-left'] ?? 0);
    final center = biasDistribution!['center'] ?? 0;
    final right = (biasDistribution!['center-right'] ?? 0) +
        (biasDistribution!['right'] ?? 0);

    final total = left + center + right;
    if (total == 0) return const SizedBox.shrink();

    final colors = context.facteurColors;

    final segments = <_Segment>[
      if (left > 0) _Segment(left, colors.biasLeft, 'Gauche ($left)'),
      if (center > 0) _Segment(center, colors.biasCenter, 'Centre ($center)'),
      if (right > 0) _Segment(right, colors.biasRight, 'Droite ($right)'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                for (int i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: segments[i].count,
                    child: Container(color: segments[i].color),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gauche ($left)',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textTertiary,
                ),
              ),
              if (center > 0)
                Text(
                  'Centre ($center)',
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.textTertiary,
                  ),
                ),
              Text(
                'Droite ($right)',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Segment {
  final int count;
  final Color color;
  final String label;
  const _Segment(this.count, this.color, this.label);
}
