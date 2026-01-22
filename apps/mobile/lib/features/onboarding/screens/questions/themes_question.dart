import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../data/available_subtopics.dart';
import '../../onboarding_strings.dart';
import '../../widgets/theme_with_subtopics.dart';

/// Q9 : "Tes thèmes préférés ?"
/// Multi-sélection avec sous-thèmes
class ThemesQuestion extends ConsumerStatefulWidget {
  const ThemesQuestion({super.key});

  @override
  ConsumerState<ThemesQuestion> createState() => _ThemesQuestionState();
}

class _ThemesQuestionState extends ConsumerState<ThemesQuestion> {
  Set<String> _selectedThemes = {};
  Set<String> _selectedSubtopics = {};

  @override
  void initState() {
    super.initState();
    final answers = ref.read(onboardingProvider).answers;
    if (answers.themes != null) {
      _selectedThemes = answers.themes!.toSet();
    }
    if (answers.subtopics != null) {
      _selectedSubtopics = answers.subtopics!.toSet();
    }
  }

  void _toggleTheme(String slug) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedThemes.contains(slug)) {
        _selectedThemes.remove(slug);
        // Clean up subtopics
        final subtopicsForTheme = AvailableSubtopics.byTheme[slug];
        if (subtopicsForTheme != null) {
          for (final sub in subtopicsForTheme) {
            _selectedSubtopics.remove(sub.slug);
          }
        }
      } else {
        _selectedThemes.add(slug);
      }
    });
  }

  void _toggleSubtopic(String themeSlug, String subtopicSlug) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSubtopics.contains(subtopicSlug)) {
        _selectedSubtopics.remove(subtopicSlug);
      } else {
        _selectedSubtopics.add(subtopicSlug);
      }

      if (!_selectedThemes.contains(themeSlug)) {
        _selectedThemes.add(themeSlug);
      }
    });
  }

  void _continue() {
    if (_selectedThemes.isNotEmpty) {
      ref.read(onboardingProvider.notifier).selectThemesAndSubtopics(
          _selectedThemes.toList(), _selectedSubtopics.toList());
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

          Text(
            OnboardingStrings.q10Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q10Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Layout: Cloud de thèmes (Wrap)
          Expanded(
            flex: 10,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxWidth: 600), // Max width for larger screens
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space2),
                    child: Wrap(
                      spacing: FacteurSpacing.space3,
                      runSpacing: FacteurSpacing.space3,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment:
                          WrapCrossAlignment.center, // Vertically center items
                      children: AvailableThemes.all.map((theme) {
                        final isSelected = _selectedThemes.contains(theme.slug);
                        final subtopics =
                            AvailableSubtopics.byTheme[theme.slug] ?? [];

                        return ThemeWithSubtopics(
                          theme: theme,
                          subtopics: subtopics,
                          isSelected: isSelected,
                          selectedSubtopics: _selectedSubtopics.toList(),
                          onThemeToggled: _toggleTheme,
                          onSubtopicToggled: _toggleSubtopic,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          AnimatedOpacity(
            opacity: canContinue ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed: canContinue ? _continue : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                OnboardingStrings.selectedCount(_selectedThemes.length),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
