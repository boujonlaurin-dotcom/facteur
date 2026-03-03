import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// A row displaying a topic suggestion with a [+ Suivre] button.
class SuggestionRow extends StatelessWidget {
  final String name;
  final VoidCallback onFollow;

  const SuggestionRow({
    super.key,
    required this.name,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space1,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.circle(),
            size: 14,
            color: colors.textTertiary,
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              name,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: onFollow,
            icon: Icon(
              PhosphorIcons.plus(),
              size: 14,
              color: const Color(0xFFE07A5F),
            ),
            label: Text(
              'Suivre',
              style: textTheme.labelSmall?.copyWith(
                color: const Color(0xFFE07A5F),
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
