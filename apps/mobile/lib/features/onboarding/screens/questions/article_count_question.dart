import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Article Count question: 3/5/7 articles per day
class ArticleCountQuestion extends ConsumerWidget {
  const ArticleCountQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedCount = state.answers.dailyArticleCount;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          Text(
            OnboardingStrings.articleCountTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.articleCountSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // 3 articles
          SelectionCard(
            emoji: '🌱',
            label: OnboardingStrings.articleCount3Label,
            subtitle: OnboardingStrings.articleCount3Subtitle,
            isSelected: selectedCount == 3,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectDailyArticleCount(3);
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // 5 articles (recommended)
          Stack(
            clipBehavior: Clip.none,
            children: [
              SelectionCard(
                emoji: '🪴',
                label: OnboardingStrings.articleCount5Label,
                subtitle: OnboardingStrings.articleCount5Subtitle,
                isSelected: selectedCount == 5,
                onTap: () {
                  ref
                      .read(onboardingProvider.notifier)
                      .selectDailyArticleCount(5);
                },
              ),
              Positioned(
                top: -8,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space2,
                    vertical: FacteurSpacing.space1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                  child: Text(
                    OnboardingStrings.articleCount5Recommended,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // 7 articles
          SelectionCard(
            emoji: '🌳',
            label: OnboardingStrings.articleCount7Label,
            subtitle: OnboardingStrings.articleCount7Subtitle,
            isSelected: selectedCount == 7,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectDailyArticleCount(7);
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
