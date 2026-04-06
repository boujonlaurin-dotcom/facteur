import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';
import '../../widgets/theme_with_subtopics.dart';

/// Q9 : "Quels sont vos centres d'intérêt ?"
/// Cloud de thèmes pur (sans subtopics ni entities)
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
    final answers = ref.read(onboardingProvider).answers;
    if (answers.themes != null) {
      _selectedThemes = answers.themes!.toSet();
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
      ref.read(onboardingProvider.notifier).selectThemes(
            _selectedThemes.toList(),
          );
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
          const SizedBox(height: FacteurSpacing.space6),

          Text(
            OnboardingStrings.q10Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q10Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Cloud de thèmes (Wrap)
          Expanded(
            flex: 10,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space2),
                    child: Wrap(
                      spacing: FacteurSpacing.space3,
                      runSpacing: FacteurSpacing.space3,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: AvailableThemes.all.map((theme) {
                        final isSelected =
                            _selectedThemes.contains(theme.slug);
                        return GestureDetector(
                          onTap: () => _toggleTheme(theme.slug),
                          child: ThemeChip(
                            theme: theme,
                            isSelected: isSelected,
                          ),
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
                padding: const EdgeInsets.symmetric(vertical: 24),
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
