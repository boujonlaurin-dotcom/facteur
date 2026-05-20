import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// In-place pagination button for [FeedThemeSection]s. Tapping appends
/// the next 10 articles in the same section.
class LoadMoreButton extends StatelessWidget {
  final String sectionLabel;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onTap;

  const LoadMoreButton({
    super.key,
    required this.sectionLabel,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final String label;
    if (isLoadingMore) {
      label = 'Chargement…';
    } else if (hasMore) {
      label = 'Voir +10 de $sectionLabel';
    } else {
      label = 'Plus rien à voir';
    }
    final bool enabled = hasMore && !isLoadingMore;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: colors.surfaceElevated
            .withValues(alpha: enabled ? 0.5 : 0.25),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoadingMore) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: enabled
                            ? colors.textSecondary
                            : colors.textSecondary.withValues(alpha: 0.5),
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
