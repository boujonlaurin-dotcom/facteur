import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

class ExampleChips extends StatelessWidget {
  final void Function(String text) onTap;

  const ExampleChips({super.key, required this.onTap});

  static const _examples = [
    "Lenny's newsletter",
    'r/france',
    '@fireship',
    'Stratechery',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIcons.lightbulb(PhosphorIconsStyle.regular),
                size: 16, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Essaie :',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _examples
              .map((example) => ActionChip(
                    label: Text(example),
                    labelStyle: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.primary),
                    side: BorderSide(color: colors.primary.withOpacity(0.3)),
                    backgroundColor: colors.primary.withOpacity(0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                    onPressed: () => onTap(example),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
