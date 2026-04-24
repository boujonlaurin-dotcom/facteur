import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../custom_topics/models/topic_models.dart';
import '../../../custom_topics/providers/custom_topics_provider.dart';
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
  final Map<String, List<String>> _customTopics = {};
  String? _addingForTheme;
  final TextEditingController _customController = TextEditingController();
  bool _saving = false;

  late final PageController _pageController;
  int _currentTheme = 0;
  final Set<int> _visitedPages = {0};

  List<String> get _selectedThemes =>
      ref.read(onboardingProvider).answers.themes ?? [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
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

  @override
  void dispose() {
    _customController.dispose();
    _pageController.dispose();
    super.dispose();
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

  void _startAddingCustom(String themeSlug) {
    setState(() {
      _addingForTheme = themeSlug;
      _customController.clear();
    });
  }

  void _submitCustomTopic(String themeSlug) {
    final name = _customController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _customTopics.putIfAbsent(themeSlug, () => []);
      _customTopics[themeSlug]!.add(name);
      _addingForTheme = null;
      _customController.clear();
    });
  }

  void _removeCustomTopic(String themeSlug, String name) {
    setState(() {
      _customTopics[themeSlug]?.remove(name);
    });
  }

  Future<void> _continue() async {
    // Collect custom topics + entities to save via API BEFORE navigating.
    // Non-bloquant : les échecs sont loggués et résumés en fin d'onboarding,
    // jamais opposés à la progression utilisateur.
    final notifier = ref.read(customTopicsProvider.notifier);
    final attempts = <_TopicAttempt>[];

    for (final entry in _customTopics.entries) {
      for (final topicName in entry.value) {
        attempts.add(_TopicAttempt(
          name: topicName,
          future: notifier
              .followTopic(topicName, slugParent: entry.key)
              .then<Object?>((v) => v)
              .catchError((Object e, StackTrace st) {
            debugPrint(
              '[ONBOARDING_TELEMETRY] event=custom_topic_failed '
              'name="$topicName" theme=${entry.key} error=$e',
            );
            return null;
          }),
        ));
      }
    }
    for (final entityName in _selectedEntities) {
      attempts.add(_TopicAttempt(
        name: entityName,
        future: notifier
            .followTopic(entityName)
            .then<Object?>((v) => v)
            .catchError((Object e, StackTrace st) {
          debugPrint(
            '[ONBOARDING_TELEMETRY] event=custom_entity_failed '
            'name="$entityName" error=$e',
          );
          return null;
        }),
      ));
    }

    if (attempts.isNotEmpty) {
      setState(() => _saving = true);
      final results = await Future.wait(attempts.map((a) => a.future));
      final failedNames = <String>[
        for (var i = 0; i < attempts.length; i++)
          if (results[i] == null) attempts[i].name,
      ];

      if (failedNames.isNotEmpty) {
        // Stocke dans l'état — la bottom sheet de synthèse s'affichera
        // après la conclusion, à la place du snackbar éphémère.
        ref
            .read(onboardingProvider.notifier)
            .recordFailedCustomTopics(failedNames);
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
    final isMulti = selectedThemes.length > 1;
    final safeIndex = _currentTheme.clamp(0, selectedThemes.length - 1);
    final currentTheme = selectedThemes.isNotEmpty
        ? _resolveTheme(selectedThemes[safeIndex])
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),

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

          const SizedBox(height: FacteurSpacing.space4),

          if (isMulti && currentTheme != null) ...[
            _buildStickyHeader(currentTheme),
            const SizedBox(height: FacteurSpacing.space3),
            _buildPageIndicator(selectedThemes.length, currentTheme.color),
            const SizedBox(height: FacteurSpacing.space3),
          ],

          Expanded(
            flex: 10,
            child: isMulti
                ? PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _currentTheme = i;
                        _visitedPages.add(i);
                      });
                    },
                    itemCount: selectedThemes.length,
                    itemBuilder: (context, index) {
                      final theme = _resolveTheme(selectedThemes[index]);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildThemeCard(theme, includeHeader: false),
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: currentTheme != null
                        ? _buildThemeCard(currentTheme, includeHeader: true)
                        : const SizedBox.shrink(),
                  ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          ElevatedButton(
            onPressed: _saving ? null : _onContinuePressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 24),
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

  ThemeOption _resolveTheme(String slug) {
    return AvailableThemes.all.firstWhere(
      (t) => t.slug == slug,
      orElse: () => ThemeOption(
        slug: slug,
        label: slug,
        emoji: '📌',
        color: Colors.grey,
      ),
    );
  }

  Widget _buildStickyHeader(ThemeOption theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Row(
        key: ValueKey(theme.slug),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(theme.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              theme.label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: theme.color,
                    fontWeight: FontWeight.w700,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int count, Color activeColor) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == _currentTheme;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isActive ? 24 : 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor
                : colors.textTertiary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }

  Future<void> _onContinuePressed() async {
    final selectedThemes = _selectedThemes;
    final allVisited = _visitedPages.length >= selectedThemes.length;

    if (selectedThemes.length > 1 && !allVisited) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Êtes-vous sûr ?'),
          content: const Text(
            'Vous pourrez toujours définir vos intérêts plus tard dans "Mes intérêts".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voir les autres thèmes'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _continue();
  }

  Widget _buildThemeCard(ThemeOption theme, {bool includeHeader = true}) {
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
    final customs = _customTopics[theme.slug] ?? [];
    final canAddMore = customs.length < 3;
    final colors = context.facteurColors;

    return Container(
      margin: includeHeader
          ? const EdgeInsets.only(bottom: FacteurSpacing.space4)
          : EdgeInsets.zero,
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
          if (includeHeader) ...[
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
          ],

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

          // Custom topics
          if (customs.isNotEmpty) ...[
            const SizedBox(height: FacteurSpacing.space2),
            Wrap(
              spacing: FacteurSpacing.space2,
              runSpacing: FacteurSpacing.space2,
              children: customs
                  .map((name) => _RemovableCustomChip(
                        name: name,
                        themeColor: theme.color,
                        onRemove: () =>
                            _removeCustomTopic(theme.slug, name),
                      ))
                  .toList(),
            ),
          ],

          const SizedBox(height: FacteurSpacing.space2),

          // Add custom topic CTA
          if (_addingForTheme == theme.slug)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    autofocus: true,
                    scrollPadding: const EdgeInsets.all(100),
                    decoration: InputDecoration(
                      hintText: AvailableSubtopics
                              .customTopicPlaceholders[theme.slug] ??
                          OnboardingStrings.addCustomTopicHint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _submitCustomTopic(theme.slug),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _submitCustomTopic(theme.slug),
                  icon: Icon(Icons.check, color: theme.color),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            )
          else if (canAddMore)
            GestureDetector(
              onTap: () => _startAddingCustom(theme.slug),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  border: Border.all(
                    color: colors.primary.withOpacity(0.3),
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

class _TopicAttempt {
  final String name;
  final Future<Object?> future;
  const _TopicAttempt({required this.name, required this.future});
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
              ? themeColor.withOpacity(0.1)
              : context.facteurColors.surfacePaper,
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
          border: Border.all(
            color: isSelected
                ? themeColor.withOpacity(0.5)
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
        color: themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(
          color: themeColor.withOpacity(0.5),
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
