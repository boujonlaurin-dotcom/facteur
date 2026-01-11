import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q10 : "Format préféré ?"
/// Choix du format de contenu préféré
class FormatQuestion extends ConsumerWidget {
  const FormatQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedFormat = state.answers.formatPreference;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '📱',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Format préféré ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Comment préfères-tu consommer du contenu ?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options en grille 2x2
          Row(
            children: [
              Expanded(
                child: BinarySelectionCard(
                  emoji: '📄',
                  label: 'Articles courts',
                  subtitle: '5-10 min',
                  isSelected: selectedFormat == 'short',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectFormatPreference('short');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '📖',
                  label: 'Articles longs',
                  subtitle: '15-30 min',
                  isSelected: selectedFormat == 'long',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectFormatPreference('long');
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Row(
            children: [
              Expanded(
                child: BinarySelectionCard(
                  emoji: '🎧',
                  label: 'Podcasts',
                  subtitle: 'Audio',
                  isSelected: selectedFormat == 'audio',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectFormatPreference('audio');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '🎬',
                  label: 'Vidéos',
                  subtitle: 'YouTube',
                  isSelected: selectedFormat == 'video',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectFormatPreference('video');
                  },
                ),
              ),
            ],
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
