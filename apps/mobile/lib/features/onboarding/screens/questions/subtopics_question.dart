import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../../config/topic_labels.dart';
import '../../../custom_topics/models/topic_models.dart';
import '../../../custom_topics/providers/custom_topics_provider.dart';
import '../../../custom_topics/widgets/entity_add_sheet.dart';
import '../../providers/onboarding_provider.dart';
import '../../data/available_subtopics.dart';
import '../../onboarding_strings.dart';
import '../../widgets/theme_with_subtopics.dart';

/// Q9b : "Affine tes centres d'intérêt"
/// Cards structurées par thème avec subtopics, entities et custom topics
class SubtopicsQuestion extends ConsumerStatefulWidget {
  const SubtopicsQuestion({super.key});

  @override
  ConsumerState<SubtopicsQuestion> createState() => _SubtopicsQuestionState();
}

class _SubtopicsQuestionState extends ConsumerState<SubtopicsQuestion> {
  Set<String> _selectedSubtopics = {};
  final Set<String> _selectedEntities = {};
  bool _saving = false;

  List<String> get _selectedThemes =>
      ref.read(onboardingProvider).answers.themes ?? [];

  @override
  void initState() {
    super.initState();
    final answers = ref.read(onboardingProvider).answers;

    if (answers.subtopics != null && answers.subtopics!.isNotEmpty) {
      // Restart: restore saved subtopics
      _selectedSubtopics = answers.subtopics!.toSet();
    } else {
      // First visit: pre-select popular subtopics for selected themes
      final selectedThemes = answers.themes ?? [];
      for (final themeSlug in selectedThemes) {
        final subs = AvailableSubtopics.byTheme[themeSlug] ?? [];
        for (final sub in subs) {
          if (sub.isPopular) _selectedSubtopics.add(sub.slug);
        }
      }
    }
  }

  void _toggleSubtopic(String slug) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSubtopics.contains(slug)) {
        _selectedSubtopics.remove(slug);
      } else {
        _selectedSubtopics.add(slug);
      }
    });
  }

  void _toggleEntity(String entityName) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedEntities.contains(entityName)) {
        _selectedEntities.remove(entityName);
      } else {
        _selectedEntities.add(entityName);
      }
    });
  }

  Future<void> _continue() async {
    // Save selected entities via API BEFORE navigating
    // (Custom topics are already followed via EntityAddSheet)
    final notifier = ref.read(customTopicsProvider.notifier);
    final futures = <Future<dynamic>>[];

    for (final entityName in _selectedEntities) {
      futures.add(
        notifier.followTopic(entityName).catchError((_) => null),
      );
    }

    if (futures.isNotEmpty) {
      setState(() => _saving = true);
      final results = await Future.wait(futures);
      final failed = results.where((r) => r == null).length;

      if (mounted && failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == results.length
                  ? 'Impossible de sauvegarder les sujets personnalisés'
                  : '$failed sujet(s) n\'ont pas pu être sauvegardés',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    // Save subtopics LAST — this triggers navigation to the next step
    ref.read(onboardingProvider.notifier).selectSubtopics(
          _selectedSubtopics.toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final selectedThemes = _selectedThemes;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),

          Text(
            OnboardingStrings.subtopicsTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.subtopicsSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          Expanded(
            flex: 10,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: selectedThemes.map((themeSlug) {
                  final theme = AvailableThemes.all.firstWhere(
                    (t) => t.slug == themeSlug,
                    orElse: () => ThemeOption(
                      slug: themeSlug,
                      label: themeSlug,
                      emoji: '📌',
                      color: Colors.grey,
                    ),
                  );
                  return _buildThemeCard(theme);
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          ElevatedButton(
            onPressed: _saving ? null : _continue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(OnboardingStrings.continueButton),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }

  Widget _buildThemeCard(ThemeOption theme) {
    final subtopics = AvailableSubtopics.byTheme[theme.slug] ?? [];
    final backendEntities =
        ref.watch(popularEntitiesProvider(theme.slug)).valueOrNull ??
            <PopularEntity>[];
    final defaultEnts =
        AvailableSubtopics.defaultEntities[theme.slug] ?? <PopularEntity>[];
    // Merge: backend first, then defaults not already present (by name)
    final backendNames =
        backendEntities.map((e) => e.name.toLowerCase()).toSet();
    final entities = [
      ...backendEntities,
      ...defaultEnts
          .where((d) => !backendNames.contains(d.name.toLowerCase())),
    ];
    final colors = context.facteurColors;

    return Container(
      margin: const EdgeInsets.only(bottom: FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surfacePaper,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.color, width: 2.5),
        ),
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: emoji + label
          Row(
            children: [
              Text(theme.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                theme.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: theme.color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Subtopics wrap
          if (subtopics.isNotEmpty)
            Wrap(
              spacing: FacteurSpacing.space2,
              runSpacing: FacteurSpacing.space2,
              children: subtopics.map((subtopic) {
                final isSelected = _selectedSubtopics.contains(subtopic.slug);
                return SubtopicChip(
                  subtopic: subtopic,
                  isSelected: isSelected,
                  onTap: () => _toggleSubtopic(subtopic.slug),
                  themeColor: theme.color,
                );
              }).toList(),
            ),

          // Popular entities
          if (entities.isNotEmpty) ...[
            const SizedBox(height: FacteurSpacing.space2),
            Wrap(
              spacing: FacteurSpacing.space2,
              runSpacing: FacteurSpacing.space2,
              children: [
                ...entities.map((entity) {
                  final isSelected = _selectedEntities.contains(entity.name);
                  return _EntityChip(
                    entity: entity,
                    isSelected: isSelected,
                    onTap: () => _toggleEntity(entity.name),
                    themeColor: theme.color,
                  );
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Text(
                    '...',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Custom topics from API (followed via EntityAddSheet)
          Consumer(
            builder: (context, ref, _) {
              final topicsAsync = ref.watch(customTopicsProvider);
              final customTopics = topicsAsync.valueOrNull
                      ?.where((t) {
                        final macroLabel =
                            getTopicMacroTheme(t.slugParent ?? '');
                        return macroLabel != null &&
                            macroThemeToApiSlug[macroLabel] == theme.slug;
                      })
                      .toList() ??
                  [];

              if (customTopics.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(top: FacteurSpacing.space2),
                child: Wrap(
                  spacing: FacteurSpacing.space2,
                  runSpacing: FacteurSpacing.space2,
                  children: customTopics.map((topic) {
                    return _RemovableCustomChip(
                      name: topic.canonicalName ?? topic.name,
                      themeColor: theme.color,
                      onRemove: () {
                        if (!topic.id.startsWith('temp_')) {
                          ref
                              .read(customTopicsProvider.notifier)
                              .unfollowTopic(topic.id);
                        }
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: FacteurSpacing.space2),

          // Add custom topic CTA — opens EntityAddSheet
          GestureDetector(
            onTap: () => EntityAddSheet.show(context, themeSlug: theme.slug),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FacteurRadius.pill),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: colors.primary),
                  const SizedBox(width: 4),
                  Text(
                    OnboardingStrings.addCustomTopicHint,
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? themeColor.withValues(alpha: 0.1)
              : context.facteurColors.surfacePaper,
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
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
                    fontSize: 12,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemovableCustomChip extends StatelessWidget {
  final String name;
  final Color themeColor;
  final VoidCallback onRemove;

  const _RemovableCustomChip({
    required this.name,
    required this.themeColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: themeColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: themeColor),
          ),
        ],
      ),
    );
  }
}
