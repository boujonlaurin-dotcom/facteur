import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../onboarding_strings.dart';
import 'minimal_loader.dart';

/// Attente sobre de l'onboarding : [MinimalLoader] + un titre et un sous-titre
/// qui disent ce qui se passe. Remplace les `CircularProgressIndicator` nus des
/// écrans sources/swipe ; sert aussi de corps à l'overlay de calibration.
class SourceSearchLoader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SourceSearchLoader({
    super.key,
    this.title = OnboardingStrings.sourceSearchLoaderTitle,
    this.subtitle = OnboardingStrings.sourceSearchLoaderSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MinimalLoader(),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              subtitle,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
