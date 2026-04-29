import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import 'source_logo_avatar.dart';

/// Carte "Pépite" affichée dans le carousel de recommandation de sources.
/// Logo grand format prioritaire, validation sociale (followers), bouton
/// "Suivre" qui passe à l'état "Suivi ✓" sans faire disparaître la carte.
class PepiteCard extends StatelessWidget {
  final Source source;
  final VoidCallback onToggleFollow;
  final VoidCallback onTap;
  final bool isFollowing;

  const PepiteCard({
    super.key,
    required this.source,
    required this.onToggleFollow,
    required this.onTap,
    this.isFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SourceLogoAvatar(source: source, size: 64, radius: 12),
            const SizedBox(height: 10),
            Text(
              source.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(FacteurRadius.small),
              ),
              child: Text(
                source.getThemeLabel(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            if (source.followerCount > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIcons.users(PhosphorIconsStyle.regular),
                    size: 12,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${source.followerCount} '
                      '${source.followerCount > 1 ? "lecteurs" : "lecteur"}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton(
                onPressed: onToggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isFollowing ? colors.backgroundSecondary : colors.primary,
                  foregroundColor:
                      isFollowing ? colors.textPrimary : colors.textPrimary,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                    side: isFollowing
                        ? BorderSide(color: colors.border)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isFollowing) ...[
                      Icon(
                        PhosphorIcons.check(PhosphorIconsStyle.bold),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      isFollowing ? 'Suivi' : 'Suivre',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
