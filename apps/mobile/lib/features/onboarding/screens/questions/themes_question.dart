import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';

/// Q9 : "Tes thèmes préférés ?"
/// Multi-sélection avec chips (minimum 1 requis)
class ThemesQuestion extends ConsumerStatefulWidget {
  const ThemesQuestion({super.key});

  @override
  ConsumerState<ThemesQuestion> createState() => _ThemesQuestionState();
}

class _ThemesQuestionState extends ConsumerState<ThemesQuestion> {
  Set<String> _selectedThemes = {};

  @override
  void initState() {
    super.initState();
    // Initialiser avec les thèmes déjà sélectionnés
    final existingThemes = ref.read(onboardingProvider).answers.themes;
    if (existingThemes != null) {
      _selectedThemes = existingThemes.toSet();
    }
  }

  void _toggleTheme(String slug) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedThemes.contains(slug)) {
        _selectedThemes.remove(slug);
      } else {
        _selectedThemes.add(slug);
      }
    });
  }

  void _continue() {
    if (_selectedThemes.isNotEmpty) {
      ref
          .read(onboardingProvider.notifier)
          .selectThemes(_selectedThemes.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedThemes.isNotEmpty;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),

          // Illustration
          const Text(
            '🤝',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Question
          Text(
            'Construisons ensemble un front de sources fiables.',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Notre catalogue est co-construit avec notre communauté. Parmi les sources actuellement validées, lesquelles résonnent avec vos exigences ?',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Chips de thèmes
          Wrap(
            spacing: FacteurSpacing.space2,
            runSpacing: FacteurSpacing.space2,
            alignment: WrapAlignment.center,
            children: AvailableThemes.all.map((theme) {
              final isSelected = _selectedThemes.contains(theme.slug);
              return _ThemeChip(
                theme: theme,
                isSelected: isSelected,
                onTap: () => _toggleTheme(theme.slug),
              );
            }).toList(),
          ),

          const Spacer(flex: 2),

          // Bouton continuer
          AnimatedOpacity(
            opacity: canContinue ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed: canContinue ? _continue : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                'Continuer (${_selectedThemes.length} sélectionné${_selectedThemes.length > 1 ? 's' : ''})',
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final ThemeOption theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.facteurColors.primary.withValues(alpha: 0.15)
              : context.facteurColors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
          border: Border.all(
            color: isSelected
                ? context.facteurColors.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(theme.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: FacteurSpacing.space2),
            Text(
              theme.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? context.facteurColors.primary
                    : context.facteurColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
