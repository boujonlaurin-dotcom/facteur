import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q1 : Multi-select diagnostic
/// Sélection des problèmes principaux avec l'info (multi-sélection)
class ObjectiveQuestion extends ConsumerStatefulWidget {
  const ObjectiveQuestion({super.key});

  @override
  ConsumerState<ObjectiveQuestion> createState() => _ObjectiveQuestionState();
}

class _ObjectiveQuestionState extends ConsumerState<ObjectiveQuestion> {
  Set<String> _selectedObjectives = {};

  @override
  void initState() {
    super.initState();
    // Restore existing selections if any
    final existing = ref.read(onboardingProvider).answers.objectives;
    if (existing != null && existing.isNotEmpty) {
      _selectedObjectives = existing.toSet();
    }
  }

  void _toggle(String value) {
    setState(() {
      if (_selectedObjectives.contains(value)) {
        _selectedObjectives.remove(value);
      } else {
        _selectedObjectives.add(value);
      }
    });
    // Update provider without advancing
    ref
        .read(onboardingProvider.notifier)
        .selectObjectives(_selectedObjectives.toList());
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

          // Question
          Text(
            OnboardingStrings.q1Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '🔊',
            label: OnboardingStrings.q1NoiseLabel,
            subtitle: OnboardingStrings.q1NoiseSubtitle,
            isSelected: _selectedObjectives.contains('noise'),
            onTap: () => _toggle('noise'),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '⚖️',
            label: OnboardingStrings.q1BiasLabel,
            subtitle: OnboardingStrings.q1BiasSubtitle,
            isSelected: _selectedObjectives.contains('bias'),
            onTap: () => _toggle('bias'),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '👎',
            label: OnboardingStrings.q1AnxietyLabel,
            subtitle: OnboardingStrings.q1AnxietySubtitle,
            isSelected: _selectedObjectives.contains('anxiety'),
            onTap: () => _toggle('anxiety'),
          ),

          const Spacer(flex: 3),

          // Continue button (disabled if empty)
          ElevatedButton(
            onPressed: _selectedObjectives.isEmpty
                ? null
                : () {
                    ref
                        .read(onboardingProvider.notifier)
                        .continueAfterObjectives();
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: colors.primary,
            ),
            child: Text(
              OnboardingStrings.selectedCount(_selectedObjectives.length),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
