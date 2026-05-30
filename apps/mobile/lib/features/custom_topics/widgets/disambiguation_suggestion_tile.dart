import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../models/topic_models.dart';

const Color _accent = Color(0xFFE07A5F);

/// Ligne de suggestion de désambiguïsation réutilisable : nom canonique +
/// badge type d'entité + description + bouton « Suivre ».
///
/// Partagée entre `EntityAddSheet` (modal « Ajouter un sujet ») et la section
/// « Sujets » de la recherche de sources (`SourceAddPanel`), pour éviter de
/// dupliquer le rendu.
class DisambiguationSuggestionTile extends StatelessWidget {
  final DisambiguationSuggestion suggestion;

  /// Affiche un spinner à la place du bouton « Suivre » pendant l'ajout.
  final bool isFollowing;

  /// `null` désactive le bouton (un autre suivi est déjà en cours).
  final VoidCallback? onFollow;

  const DisambiguationSuggestionTile({
    super.key,
    required this.suggestion,
    required this.isFollowing,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final s = suggestion;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.canonicalName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (s.entityType != null) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      getEntityTypeLabel(s.entityType!),
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
                if (s.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isFollowing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _accent,
              ),
            )
          else
            TextButton.icon(
              onPressed: onFollow,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 14,
                color: _accent,
              ),
              label: Text(
                'Suivre',
                style: textTheme.labelSmall?.copyWith(
                  color: _accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
