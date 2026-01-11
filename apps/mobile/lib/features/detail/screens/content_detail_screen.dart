import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/secondary_button.dart';

/// Écran de détail d'un contenu (placeholder)
class ContentDetailScreen extends StatelessWidget {
  final String contentId;

  const ContentDetailScreen({
    super.key,
    required this.contentId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header actions
            Padding(
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                      color: colors.textPrimary,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      PhosphorIcons.textAa(PhosphorIconsStyle.regular),
                      color: colors.textPrimary,
                    ),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(
                      PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.regular),
                      color: colors.textPrimary,
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: FacteurSpacing.space4),

                    // Source badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FacteurSpacing.space3,
                            vertical: FacteurSpacing.space2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius:
                                BorderRadius.circular(FacteurRadius.full),
                            border: Border.all(
                              color: colors.surfaceElevated,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: Colors.red, // Placeholder
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Le Monde',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Il y a 2h',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                        ),
                      ],
                    ),

                    const SizedBox(height: FacteurSpacing.space6),

                    Text(
                      'Titre de l\'article qui peut être assez long sur deux lignes',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),

                    const SizedBox(height: FacteurSpacing.space6),

                    // Content placeholder
                    Text(
                      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\n\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.textSecondary,
                            height: 1.6,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(color: colors.surfaceElevated),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Source originale',
                      onPressed: () {},
                      icon: PhosphorIcons.arrowSquareOut(
                          PhosphorIconsStyle.regular),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
