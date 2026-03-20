import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../data/available_subtopics.dart';
import '../providers/onboarding_provider.dart';

class ThemeWithSubtopics extends StatelessWidget {
  final ThemeOption theme;
  final List<SubtopicOption> subtopics;
  final bool isSelected;
  final List<String> selectedSubtopics;
  final List<PopularEntity> popularEntities;
  final Set<String> selectedEntities;
  final void Function(String themeSlug) onThemeToggled;
  final void Function(String themeSlug, String subtopicSlug) onSubtopicToggled;
  final void Function(String entityName)? onEntityToggled;

  const ThemeWithSubtopics({
    super.key,
    required this.theme,
    required this.subtopics,
    required this.isSelected,
    required this.selectedSubtopics,
    this.popularEntities = const [],
    this.selectedEntities = const {},
    required this.onThemeToggled,
    required this.onSubtopicToggled,
    this.onEntityToggled,
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
          child: isSelected && (subtopics.isNotEmpty || popularEntities.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.only(
                    top: FacteurSpacing.space2,
                    bottom: FacteurSpacing.space2,
                  ),
                  child: Container(
                    constraints:
                        const BoxConstraints(maxWidth: 300),
                    child: Wrap(
                      spacing: FacteurSpacing.space2,
                      runSpacing: FacteurSpacing.space2,
                      alignment: WrapAlignment.center,
                      children: [
                        ...subtopics.map((subtopic) {
                          final isSubSelected =
                              selectedSubtopics.contains(subtopic.slug);

                          return SubtopicChip(
                            subtopic: subtopic,
                            isSelected: isSubSelected,
                            onTap: () =>
                                onSubtopicToggled(theme.slug, subtopic.slug),
                            themeColor: theme.color,
                          );
                        }),
                        ...popularEntities.map((entity) {
                          final isEntitySelected =
                              selectedEntities.contains(entity.name);
                          return _EntityChip(
                            entity: entity,
                            isSelected: isEntitySelected,
                            onTap: () => onEntityToggled?.call(entity.name),
                            themeColor: theme.color,
                          );
                        }),
                      ],
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
                  color: Colors.black.withValues(alpha: 0.05),
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

class _EntityChip extends StatelessWidget {
  final PopularEntity entity;
  final bool isSelected;
  final VoidCallback onTap;
  final Color themeColor;

  const _EntityChip({
    required this.entity,
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
            Text(
              entity.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? themeColor
                        : context.facteurColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
            ),
            const SizedBox(width: 4),
            Text(
              getEntityTypeLabel(entity.type),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.facteurColors.textTertiary,
                    fontSize: 9,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
