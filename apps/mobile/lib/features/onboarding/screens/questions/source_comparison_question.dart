import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';

/// Q11 : "Tu préfères lire..."
/// Comparaison rapide entre deux types de sources
class SourceComparisonQuestion extends ConsumerStatefulWidget {
  const SourceComparisonQuestion({super.key});

  @override
  ConsumerState<SourceComparisonQuestion> createState() =>
      _SourceComparisonQuestionState();
}

class _SourceComparisonQuestionState
    extends ConsumerState<SourceComparisonQuestion> {
  String? _selectedOption;

  void _selectOption(String option) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedOption = option;
    });

    // Auto-transition après sélection
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        ref.read(onboardingProvider.notifier).continueAfterSourceComparison();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '⚖️',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Tu préfères lire...',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Pour mieux personnaliser ton feed',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options de comparaison
          _ComparisonOption(
            emoji: '🎓',
            title: 'Du contenu éducatif',
            subtitle: 'Explications, tutoriels, analyses',
            isSelected: _selectedOption == 'educational',
            onTap: () => _selectOption('educational'),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          _ComparisonOption(
            emoji: '📰',
            title: 'De l\'actualité décryptée',
            subtitle: 'News, tendances, réactions',
            isSelected: _selectedOption == 'news',
            onTap: () => _selectOption('news'),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          _ComparisonOption(
            emoji: '💡',
            title: 'Des opinions et débats',
            subtitle: 'Points de vue, tribunes, controverses',
            isSelected: _selectedOption == 'opinions',
            onTap: () => _selectOption('opinions'),
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _ComparisonOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _ComparisonOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        decoration: BoxDecoration(
          color: isSelected
              ? context.facteurColors.primary.withValues(alpha: 0.15)
              : context.facteurColors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color:
                isSelected ? context.facteurColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.facteurColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: context.facteurColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
