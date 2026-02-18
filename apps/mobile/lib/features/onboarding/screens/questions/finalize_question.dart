import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/theme.dart';
import '../../../../config/routes.dart';
import '../../../digest/models/digest_mode.dart';
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

    final themesCount = answers.themes?.length ?? 0;
    final sourcesCount = answers.preferredSources?.length ?? 0;
    final articleCount = answers.dailyArticleCount ?? 5;
    final digestModeKey = answers.digestMode ?? 'pour_vous';
    final digestMode = DigestMode.fromKey(digestModeKey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          Text(
            OnboardingStrings.finalizeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.finalizeSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  emoji: '🎨',
                  label: OnboardingStrings.finalizeThemeSummary(themesCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: '📰',
                  label: OnboardingStrings.finalizeSourcesSummary(sourcesCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: '📋',
                  label: OnboardingStrings.finalizeArticleCountSummary(
                      articleCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: digestMode.emoji,
                  label: 'Mode : ${digestMode.label}',
                ),
              ],
            ),
          ),

          const Spacer(flex: 3),

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
}

class _SummaryRow extends StatelessWidget {
  final String emoji;
  final String label;

  const _SummaryRow({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Icon(Icons.check_circle, color: colors.success, size: 20),
      ],
    );
  }
}
