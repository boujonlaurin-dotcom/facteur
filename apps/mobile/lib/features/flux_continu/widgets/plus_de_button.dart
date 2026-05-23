import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// "Voir tout {thème}" — opens the dedicated theme page (slide-from-right)
/// instead of paginating in-place. Visual cousin of [PlusDeButton] so the
/// bottom-of-section CTA family stays consistent.
class SeeAllSectionButton extends StatelessWidget {
  final String sectionLabel;
  final int totalCount;
  final bool hasMore;
  final VoidCallback onTap;

  const SeeAllSectionButton({
    super.key,
    required this.sectionLabel,
    required this.totalCount,
    required this.hasMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final countSuffix = hasMore ? '+' : '';
    final label = totalCount > 0
        ? 'Voir tout $sectionLabel ($totalCount$countSuffix)'
        : 'Voir tout $sectionLabel';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: colors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  color: colors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Plus de…" expand/collapse button for a Flux Continu section.
///
/// Soft off-white pill, single neutral colour across all sections — section
/// accents stay confined to the hero banner so the bottom-of-section CTA
/// reads as quiet UI chrome rather than as a second hero element.
class PlusDeButton extends StatelessWidget {
  final String sectionLabel;
  final bool isOpen;
  final int hiddenCount;
  final VoidCallback onTap;

  const PlusDeButton({
    super.key,
    required this.sectionLabel,
    required this.isOpen,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = isOpen
        ? 'Replier $sectionLabel'
        : 'Plus de $sectionLabel${hiddenCount > 0 ? " (+$hiddenCount)" : ""}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: colors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOpen ? Icons.expand_less : Icons.expand_more,
                  color: colors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
