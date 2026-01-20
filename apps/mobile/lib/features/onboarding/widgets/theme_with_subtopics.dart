import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../data/available_subtopics.dart';
import '../providers/onboarding_provider.dart';

class ThemeWithSubtopics extends StatelessWidget {
  final ThemeOption theme;
  final List<SubtopicOption> subtopics;
  final bool isSelected;
  final List<String> selectedSubtopics;
  final void Function(String themeSlug) onThemeToggled;
  final void Function(String themeSlug, String subtopicSlug) onSubtopicToggled;

  const ThemeWithSubtopics({
    super.key,
    required this.theme,
    required this.subtopics,
    required this.isSelected,
    required this.selectedSubtopics,
    required this.onThemeToggled,
    required this.onSubtopicToggled,
  });

  @override
  Widget build(BuildContext context) {
    // Si on est dans un Wrap, on veut que le widget prenne sa taille intrinsèque
    return Column(
      mainAxisSize: MainAxisSize.min, // Important pour le Wrap
      crossAxisAlignment:
          CrossAxisAlignment.center, // Centré pour l'esthétique "nuage"
      children: [
        // Thème principal (Chip style)
        GestureDetector(
          onTap: () => onThemeToggled(theme.slug),
          child: _ThemeChip(
            theme: theme,
            isSelected: isSelected,
          ),
        ),

        // Sous-thèmes (Si sélectionnés, s'affichent en dessous)
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic, // Smoother curve
          alignment: Alignment.topCenter,
          child: isSelected && subtopics.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(
                    top: FacteurSpacing.space2,
                    bottom: FacteurSpacing.space2,
                  ),
                  child: Container(
                    // Fond subtil pour regrouper les sous-thèmes ? Optionnel.
                    // Pour l'instant on garde simple.
                    constraints:
                        const BoxConstraints(maxWidth: 300), // Limite largeur
                    child: Wrap(
                      spacing: FacteurSpacing.space2,
                      runSpacing: FacteurSpacing.space2,
                      alignment: WrapAlignment.center,
                      children: subtopics.map((subtopic) {
                        final isSubSelected =
                            selectedSubtopics.contains(subtopic.slug);

                        return SubtopicChip(
                          subtopic: subtopic,
                          isSelected: isSubSelected,
                          onTap: () =>
                              onSubtopicToggled(theme.slug, subtopic.slug),
                          themeColor: theme.color,
                        );
                      }).toList(),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final ThemeOption theme;
  final bool isSelected;

  const _ThemeChip({
    required this.theme,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3, // Un peu plus compact
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.color.withValues(alpha: 0.15)
            : context.facteurColors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(
          color: isSelected
              ? theme.color
              : context.facteurColors
                  .surfaceElevated, // Bordure subtile si pas sélectionné
          width: 2,
        ),
        boxShadow: isSelected
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            theme.emoji,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Text(
            theme.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isSelected
                      ? theme.color
                      : context.facteurColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 16, // User wanted better visibility
                ),
          ),
        ],
      ),
    );
  }
}

class SubtopicChip extends StatelessWidget {
  final SubtopicOption subtopic;
  final bool isSelected;
  final VoidCallback onTap;
  final Color themeColor;

  const SubtopicChip({
    super.key,
    required this.subtopic,
    required this.isSelected,
    required this.onTap,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? themeColor.withValues(alpha: 0.1)
              : context.facteurColors.surfacePaper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? themeColor.withValues(alpha: 0.5)
                : context.facteurColors.surfaceElevated,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtopic.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              subtopic.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? themeColor
                        : context.facteurColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13, // Increased font size as requested
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
