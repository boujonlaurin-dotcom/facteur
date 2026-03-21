import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Empty state affiché quand un filtre (thème, topic, entity, source)
/// ne retourne aucun article. Propose des CTAs contextuels pour
/// réduire la frustration et guider l'utilisateur.
class EmptyFilterState extends StatelessWidget {
  final String? filterName;
  final bool isTheme;
  final bool isEntity;
  final bool isSource;
  final VoidCallback onClearFilter;
  final VoidCallback? onBrowseThemes;

  const EmptyFilterState({
    super.key,
    this.filterName,
    this.isTheme = false,
    this.isEntity = false,
    this.isSource = false,
    required this.onClearFilter,
    this.onBrowseThemes,
  });

  String get _emoji {
    if (isEntity) return '🔍';
    if (isSource) return '📰';
    return '📭';
  }

  String get _title {
    if (filterName != null) {
      return 'Rien sur « $filterName »';
    }
    return 'Aucun article trouvé';
  }

  String get _subtitle {
    if (isEntity) {
      return 'Aucun article récent ne mentionne ce sujet.\nDe nouveaux contenus peuvent arriver bientôt.';
    }
    if (isSource) {
      return 'Aucun article récent de cette source.';
    }
    return 'Aucun article récent ne correspond à ce filtre.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji
            Text(_emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: FacteurSpacing.space4),

            // Title
            Text(
              _title,
              style: textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space2),

            // Subtitle
            Text(
              _subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space6),

            // Primary CTA: clear filter
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClearFilter,
                icon: Icon(
                  PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold),
                  size: 18,
                ),
                label: const Text('Revenir au feed'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.medium),
                  ),
                ),
              ),
            ),

            // Secondary CTA: browse other themes (only if current filter is theme/topic/entity)
            if (onBrowseThemes != null && !isSource) ...[
              const SizedBox(height: FacteurSpacing.space3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onBrowseThemes,
                  icon: Icon(
                    PhosphorIcons.compass(PhosphorIconsStyle.regular),
                    size: 18,
                  ),
                  label: const Text('Explorer un autre thème'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
