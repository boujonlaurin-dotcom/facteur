import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';

/// Bottom sheet "Personnaliser ton Essentiel" (Story 9.2, composant 1 bis).
///
/// Affichée depuis le bouton config en haut-droite de la carte hi-fi
/// `EssentielHiFiCard`. Propose deux choix :
///   - "Tes intérêts" → `RouteNames.myInterests` (`/settings/interests`)
///   - "Tes sources"  → `RouteNames.sources`     (`/settings/sources`)
///
/// Tap hors / `[×]` referme sans navigation.
class EssentielPersonalizeSheet extends StatelessWidget {
  const EssentielPersonalizeSheet({super.key});

  /// Helper d'affichage aligné sur le pattern `InterestStatePickerSheet.show`.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const EssentielPersonalizeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Personnaliser ton Essentiel',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.textTertiary),
                    splashRadius: 20,
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _ChoiceTile(
              icon: Icons.favorite_outline,
              accent: colors.sectionEssentiel,
              title: 'Tes intérêts',
              subtitle: 'Choisis les thèmes qui guident ton Essentiel.',
              onTap: () {
                Navigator.of(context).pop();
                context.pushNamed(RouteNames.myInterests);
              },
            ),
            _ChoiceTile(
              icon: Icons.rss_feed,
              accent: colors.sectionVeille1,
              title: 'Tes sources',
              subtitle: 'Suis ou masque les médias qui te parlent.',
              onTap: () {
                Navigator.of(context).pop();
                context.pushNamed(RouteNames.sources);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
