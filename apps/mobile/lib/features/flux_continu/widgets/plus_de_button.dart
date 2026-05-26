import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// "Voir tout {thème}" — opens the dedicated theme page (slide-from-right)
/// instead of paginating in-place. Visual cousin of [PlusDeButton] so the
/// bottom-of-section CTA family stays consistent.
class SeeAllSectionButton extends StatelessWidget {
  final String sectionLabel;
  final int hiddenCount;
  final bool hasMore;
  final VoidCallback onTap;

  const SeeAllSectionButton({
    super.key,
    required this.sectionLabel,
    required this.hiddenCount,
    required this.hasMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final countSuffix = hasMore ? '+' : '';
    final label = hiddenCount > 0
        ? 'Voir tout $sectionLabel (+$hiddenCount$countSuffix)'
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

/// "Sujet suivant →" — bottom-of-section CTA that marks the section as
/// consumed for the next session and scrolls smoothly to the next section.
/// When [isMarked] is true, the button switches to a non-interactive
/// "Lu ✓" state showing the section has been validated in this session.
///
/// Visual variant: outlined/ghost (transparent fill with a 1px divider
/// border) so it reads as a quieter cousin of [PlusDeButton] — the two
/// can sit side by side without competing.
class NextSectionButton extends StatelessWidget {
  final bool isMarked;
  final VoidCallback? onTap;

  const NextSectionButton({
    super.key,
    required this.isMarked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final foreground =
        isMarked ? colors.success : colors.textSecondary;
    final label = isMarked ? 'Lu' : 'Sujet suivant';
    final icon = isMarked ? Icons.check : Icons.arrow_forward;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colors.border,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 6),
                Icon(icon, color: foreground, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
