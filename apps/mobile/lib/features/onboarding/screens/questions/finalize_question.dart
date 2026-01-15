import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../config/routes.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Écran de finalisation avant l'animation de conclusion
class FinalizeQuestion extends ConsumerWidget {
  const FinalizeQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final answers = state.answers;
    final colors = context.facteurColors;

    // Résumé des préférences
    final themesCount = answers.themes?.length ?? 0;
    final hasGamification = answers.gamificationEnabled == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Titre
          Text(
            OnboardingStrings.finalizeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.finalizeSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Résumé des choix
          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  icon: PhosphorIcons.paintBrush(PhosphorIconsStyle.fill),
                  label: OnboardingStrings.finalizeThemeSummary(themesCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  icon: _getFormatIcon(answers.formatPreference),
                  label: _getFormatLabel(answers.formatPreference),
                ),
                if (hasGamification) ...[
                  const SizedBox(height: FacteurSpacing.space3),
                  _SummaryRow(
                    icon: PhosphorIcons.target(PhosphorIconsStyle.fill),
                    label: OnboardingStrings.finalizeGoalSummary(
                      answers.weeklyGoal ?? 10,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Spacer(flex: 3),

          // Bouton finaliser
          ElevatedButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).finalizeOnboarding();
              context.goNamed(RouteNames.onboardingConclusion);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  OnboardingStrings.finalizeButton,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: FacteurSpacing.space2),
                Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }

  IconData _getFormatIcon(String? format) {
    switch (format) {
      case 'short':
        return PhosphorIcons.fileText(PhosphorIconsStyle.fill);
      case 'long':
        return PhosphorIcons.bookOpen(PhosphorIconsStyle.fill);
      case 'audio':
        return PhosphorIcons.headphones(PhosphorIconsStyle.fill);
      case 'video':
        return PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.fileText(PhosphorIconsStyle.fill);
    }
  }

  String _getFormatLabel(String? format) {
    switch (format) {
      case 'short':
        return OnboardingStrings.finalizeFormatShort;
      case 'long':
        return OnboardingStrings.finalizeFormatLong;
      case 'audio':
        return OnboardingStrings.finalizeFormatAudio;
      case 'video':
        return OnboardingStrings.finalizeFormatVideo;
      default:
        return OnboardingStrings.finalizeFormatMixed;
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Icon(icon, size: 24, color: colors.primary),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
            color: colors.success, size: 20),
      ],
    );
  }
}
