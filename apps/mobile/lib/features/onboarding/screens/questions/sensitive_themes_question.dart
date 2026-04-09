import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/serein_colors.dart';
import '../../../../config/theme.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/theme_with_subtopics.dart';

/// Étape conditionnelle : sujets sensibles (mode serein uniquement)
/// Affichée après digestMode == 'serein', avant Section 3.
class SensitiveThemesQuestion extends ConsumerStatefulWidget {
  const SensitiveThemesQuestion({super.key});

  @override
  ConsumerState<SensitiveThemesQuestion> createState() =>
      _SensitiveThemesQuestionState();
}

class _SensitiveThemesQuestionState
    extends ConsumerState<SensitiveThemesQuestion> {
  Set<String> _selectedThemes = {};

  @override
  void initState() {
    super.initState();
    final answers = ref.read(onboardingProvider).answers;
    if (answers.sensitiveThemes != null) {
      _selectedThemes = answers.sensitiveThemes!.toSet();
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
    ref.read(onboardingProvider.notifier).selectSensitiveThemes(
          _selectedThemes.toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),

          Text(
            OnboardingStrings.sensitiveThemesTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.sensitiveThemesSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Cloud de thèmes
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

          ElevatedButton(
            onPressed: _continue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 24),
              backgroundColor: SereinColors.sereinColor,
              foregroundColor: Colors.white,
            ),
            child: Text(
              _selectedThemes.isEmpty
                  ? OnboardingStrings.sensitiveThemesSkip
                  : OnboardingStrings.sensitiveThemesContinue(
                      _selectedThemes.length),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
