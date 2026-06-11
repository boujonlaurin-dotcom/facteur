import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../../core/providers/analytics_provider.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q9c : « Avec quels médias préférez-vous partir ? »
/// Question légère qui route vers l'une des deux variantes de la page sources :
/// suggestions guidées (curious) ou recherche de ses médias (knows).
class SourcesIntentQuestion extends ConsumerWidget {
  const SourcesIntentQuestion({super.key});

  void _select(WidgetRef ref, String intent) {
    ref.read(analyticsServiceProvider).trackOnboardingSourcesIntent(intent);
    ref.read(onboardingProvider.notifier).selectSourcesIntent(intent);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIntent =
        ref.watch(onboardingProvider).answers.sourcesIntent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: FacteurSpacing.space8),
            Text(
              OnboardingStrings.sourcesIntentTitle,
              style: Theme.of(context).textTheme.displayLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space8),
            Semantics(
              button: true,
              label: '${OnboardingStrings.sourcesIntentCuriousLabel}. '
                  '${OnboardingStrings.sourcesIntentCuriousSubtitle}',
              child: SelectionCard(
                emoji: '🧭',
                label: OnboardingStrings.sourcesIntentCuriousLabel,
                subtitle: OnboardingStrings.sourcesIntentCuriousSubtitle,
                isSelected: selectedIntent == 'curious',
                onTap: () => _select(ref, 'curious'),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Semantics(
              button: true,
              label: '${OnboardingStrings.sourcesIntentKnowsLabel}. '
                  '${OnboardingStrings.sourcesIntentKnowsSubtitle}',
              child: SelectionCard(
                emoji: '📌',
                label: OnboardingStrings.sourcesIntentKnowsLabel,
                subtitle: OnboardingStrings.sourcesIntentKnowsSubtitle,
                isSelected: selectedIntent == 'knows',
                onTap: () => _select(ref, 'knows'),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
          ],
        ),
      ),
    );
  }
}
