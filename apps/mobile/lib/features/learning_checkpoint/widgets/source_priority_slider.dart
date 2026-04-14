import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Slider à 3 niveaux pour `source_priority` : `●○○` (1) / `●●○` (2) / `●●●` (3).
/// Affiche la valeur courante grisée, puis la valeur proposée pré-active,
/// modifiable au tap sur une pastille.
class SourcePrioritySlider extends StatelessWidget {
  final int current;
  final int proposed;
  final ValueChanged<int> onChange;

  const SourcePrioritySlider({
    super.key,
    required this.current,
    required this.proposed,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DotGroup(level: current, faded: true, colors: colors),
        const SizedBox(width: 4),
        Text(
          '→',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        _DotGroup(
          level: proposed,
          faded: false,
          colors: colors,
          onTap: onChange,
        ),
      ],
    );
  }
}

class _DotGroup extends StatelessWidget {
  final int level;
  final bool faded;
  final FacteurColors colors;
  final ValueChanged<int>? onTap;

  const _DotGroup({
    required this.level,
    required this.faded,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final group = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final filled = i < level;
        final color = filled
            ? (faded ? colors.textTertiary : colors.primary)
            : colors.border;

        final dot = Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        );
        if (onTap == null) return dot;
        return Semantics(
          button: true,
          label: 'Niveau ${i + 1} sur 3',
          child: InkWell(
            onTap: () => onTap!(i + 1),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: dot,
            ),
          ),
        );
      }),
    );
    if (onTap == null) return group;
    return Semantics(
      value: 'Proposé $level sur 3',
      child: group,
    );
  }
}
