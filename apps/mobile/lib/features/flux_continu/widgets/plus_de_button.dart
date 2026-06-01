import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// "Plus d'articles" — opens the dedicated theme page (slide-from-right)
/// instead of paginating in-place. Visual cousin of [PlusDeButton] so the
/// bottom-of-section CTA family stays consistent.
class SeeAllSectionButton extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onTap;

  const SeeAllSectionButton({
    super.key,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = hiddenCount > 0
        ? 'Tout lire (+$hiddenCount)'
        : 'Tout lire';
    return _ButtonShell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
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
    return _ButtonShell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOpen ? Icons.expand_less : Icons.expand_more,
            color: colors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared shell for [SeeAllSectionButton] and [PlusDeButton]: same soft
/// off-white Material + InkWell + full-width padded container.
class _ButtonShell extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _ButtonShell({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: colors.surfaceElevated.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: child,
        ),
      ),
    );
  }
}
