import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/serein_colors.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../shared/widgets/fab_nudge_bubble.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';
import '../providers/personalization_provider.dart';
import '../providers/serein_exclusions_provider.dart';
import '../providers/theme_priority_provider.dart';
import '../widgets/entity_add_sheet.dart';
import '../widgets/theme_section.dart';

/// Settings screen for managing custom topic subscriptions.
///
/// Groups followed topics by parent theme (slug_parent) in ExpansionTiles,
/// with in-situ suggestions per theme.
/// Theme sections are sorted by max user priority on initial load only
/// (no dynamic reordering while the user is on the page).
class MyInterestsScreen extends ConsumerStatefulWidget {
  /// If set, forces the serein toggle ON on first open (typically when the
  /// user arrived from the onboarding "Personnaliser" CTA).
  final bool forceSereinOn;

  const MyInterestsScreen({super.key, this.forceSereinOn = false});

  @override
  ConsumerState<MyInterestsScreen> createState() => _MyInterestsScreenState();
}

class _MyInterestsScreenState extends ConsumerState<MyInterestsScreen> {
  /// Sorted group order, computed once on first data load.
  List<String>? _sortedGroups;

  @override
  void initState() {
    super.initState();
    // Prime the serein exclusions cache so the tri-state headers are correct
    // on first frame, even before the user taps the switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sereinExclusionsProvider.notifier).loadIfNeeded();
      if (widget.forceSereinOn &&
          !ref.read(sereinToggleProvider).enabled) {
        ref.read(sereinToggleProvider.notifier).toggle();
      }
    });
  }

  /// When the user arrived from onboarding, back needs to return to the
  /// questionnaire rather than pop inside the settings shell.
  void _handleBack() {
    if (widget.forceSereinOn) {
      context.goNamed(RouteNames.onboarding);
    } else if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final topicsAsync = ref.watch(customTopicsProvider);
    final themePriorities =
        ref.watch(themePriorityProvider).valueOrNull ?? <String, double>{};

    final sereinMode = ref.watch(sereinToggleProvider).enabled;

    return PopScope(
      canPop: !widget.forceSereinOn,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.forceSereinOn) {
          context.goNamed(RouteNames.onboarding);
        }
      },
      child: Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        title: const Text('Mes Intérêts'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: textTheme.displaySmall,
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Flexible(
            child: FabNudgeBubble(
              text: 'Suivez n\'importe quel sujet pour le faire ressortir dans votre flux !',
            ),
          ),
          const SizedBox(width: 6),
          FloatingActionButton.extended(
            onPressed: () => EntityAddSheet.show(context),
            backgroundColor: const Color(0xFFE07A5F),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add, size: 20),
            label: const Text(
              'Sujet personnalisé',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: topicsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorView(
          error: e,
          onRetry: () => ref.invalidate(customTopicsProvider),
        ),
        data: (topics) {
          // Muted topics grouped by macro-theme
          final mutedTopics =
              ref.watch(personalizationProvider).valueOrNull?.mutedTopics ?? {};
          final mutedByTheme = <String, Map<String, String>>{};
          for (final slug in mutedTopics) {
            var macro = getTopicMacroTheme(slug);
            String? displayLabel;
            if (macro == null) {
              // Entity names (e.g. "donald trump") aren't in _slugToMacroTheme.
              // Try to resolve via followed topics' canonicalName → slugParent.
              final matchingTopic = topics
                  .where((t) =>
                      t.canonicalName?.toLowerCase() == slug.toLowerCase())
                  .firstOrNull;
              if (matchingTopic != null && matchingTopic.slugParent != null) {
                macro = getTopicMacroTheme(matchingTopic.slugParent!);
                displayLabel =
                    matchingTopic.canonicalName ?? matchingTopic.name;
              }
            }
            // For non-entity slugs, also try to recover the original name
            // from followed topics (e.g. "nba" → "NBA").
            displayLabel ??= topics
                .where((t) =>
                    t.canonicalName?.toLowerCase() == slug ||
                    t.name.toLowerCase() == slug)
                .firstOrNull
                ?.canonicalName;
            displayLabel ??= topics
                .where((t) => t.name.toLowerCase() == slug)
                .firstOrNull
                ?.name;
            displayLabel ??= getTopicLabel(slug);
            if (macro != null) {
              mutedByTheme.putIfAbsent(macro, () => {})[slug] = displayLabel;
            }
          }

          // Group topics by macro group
          final grouped = <String, List<_GroupedTheme>>{};
          for (final topic in topics) {
            final slug = topic.slugParent ?? _deriveSlugFromName(topic.name);
            final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
            grouped.putIfAbsent(macroGroup, () => []);

            // Find or create the theme entry within this group
            final existing = grouped[macroGroup]!
                .where((g) => g.slug == slug)
                .toList();
            if (existing.isNotEmpty) {
              existing.first.topics.add(topic);
            } else {
              final label = getTopicLabel(slug);
              grouped[macroGroup]!.add(_GroupedTheme(
                slug: slug,
                label: label.isNotEmpty ? label : topic.name,
                topics: [topic],
              ));
            }
          }

          // Also add groups with no followed topics (for suggestions)
          final existingSlugs = topics
              .map((t) => t.slugParent ?? _deriveSlugFromName(t.name))
              .toSet();
          for (final slug in topicSlugToLabel.keys) {
            if (!existingSlugs.contains(slug)) {
              final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
              grouped.putIfAbsent(macroGroup, () => []);
            }
          }

          // Compute sorted order only once (on initial page load).
          // Uses theme-level priorities (SharedPreferences) when available,
          // falling back to max individual topic priority.
          _sortedGroups ??= macroThemeOrder
              .where((group) => grouped.containsKey(group))
              .toList()
            ..sort((a, b) {
              final aPriority = themePriorities[a] ??
                  _maxPriority(grouped[a] ?? []);
              final bPriority = themePriorities[b] ??
                  _maxPriority(grouped[b] ?? []);
              if (aPriority != bPriority) {
                return bPriority.compareTo(aPriority);
              }
              return macroThemeOrder
                  .indexOf(a)
                  .compareTo(macroThemeOrder.indexOf(b));
            });

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: FacteurSpacing.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero text
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sereinMode
                            ? 'Vos bonnes nouvelles'
                            : 'Vos centres d\'intérêt',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space2),
                      Text(
                        sereinMode
                            ? 'Choisissez ce qui reste dans vos bonnes nouvelles. Cochez pour garder, décochez pour mettre de côté — votre digest ne gardera que les nouvelles qui ont du sens pour vous.'
                            : 'Ajustez vos thèmes et sujets pour les voir plus ou moins apparaître dans l\'Essentiel du jour et votre flux.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Mode Serein toggle (DS aligned with Réglages sheet)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FacteurSpacing.space4,
                    0,
                    FacteurSpacing.space4,
                    FacteurSpacing.space3,
                  ),
                  child: _SereinToggleTile(
                    enabled: sereinMode,
                    onChanged: () =>
                        ref.read(sereinToggleProvider.notifier).toggle(),
                  ),
                ),

                // How it works card — only in serein mode (explains the
                // checkbox semantic). Normal mode relies on inline affordances.
                if (sereinMode) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(FacteurSpacing.space3),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.eco_outlined,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: FacteurSpacing.space2),
                          Expanded(
                            child: Text(
                              'Coché = présent dans votre digest serein. '
                              'Décoché = mis en pause. '
                              'La case du thème agit sur l\'ensemble de ses sujets.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space3),
                ],

                // Theme sections (order fixed on initial load)
                ..._sortedGroups!
                    .where((group) => grouped.containsKey(group))
                    .map((group) {
                  final themes = grouped[group]!;
                  if (themes.isEmpty) {
                    final groupSlugs = topicSlugToLabel.keys
                        .where((s) => getTopicMacroTheme(s) == group)
                        .toList();
                    if (groupSlugs.isEmpty) return const SizedBox.shrink();
                    return ThemeSection(
                      themeSlug: macroThemeToApiSlug[group] ?? groupSlugs.first,
                      themeLabel: group,
                      followedTopics: const [],
                      mutedTopicSlugs: mutedByTheme[group] ?? {},
                      sereinMode: sereinMode,
                    );
                  }
                  final allTopics =
                      themes.expand((t) => t.topics).toList();
                  return ThemeSection(
                    themeSlug: macroThemeToApiSlug[group] ?? themes.first.slug,
                    themeLabel: group,
                    followedTopics: allTopics,
                    mutedTopicSlugs: mutedByTheme[group] ?? {},
                    sereinMode: sereinMode,
                  );
                }),

                // Content types section (hidden in serein mode — not relevant).
                if (!sereinMode) _ContentTypesSection(),

                // Empty state
                if (topics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                      vertical: FacteurSpacing.space6,
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 48,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(height: FacteurSpacing.space3),
                          Text(
                            'Aucun sujet suivi pour le moment.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: FacteurSpacing.space1),
                          Text(
                            'Explorez les suggestions ci-dessous pour personnaliser votre feed.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    );
  }
}

/// Returns the max [priorityMultiplier] across all topics in the given themes.
/// Returns 0.0 if no topics exist (empty/suggestion-only groups sort last).
double _maxPriority(List<_GroupedTheme> themes) {
  double max = 0.0;
  for (final theme in themes) {
    for (final topic in theme.topics) {
      if (topic.priorityMultiplier > max) max = topic.priorityMultiplier;
    }
  }
  return max;
}

/// Reverse-lookup: finds a slug for a topic name from [topicSlugToLabel].
String _deriveSlugFromName(String name) => getTopicSlug(name);

/// Helper to group topics by slug within a macro theme.
class _GroupedTheme {
  final String slug;
  final String label;
  final List<UserTopicProfile> topics;

  _GroupedTheme({
    required this.slug,
    required this.label,
    required this.topics,
  });
}

/// Section at the bottom of MyInterests for toggling content types on/off.
class _ContentTypesSection extends ConsumerWidget {
  static const _contentTypes = <String, String>{
    'article': 'Articles',
    'podcast': 'Podcasts',
    'youtube': 'Vidéos YouTube',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final perso = ref.watch(personalizationProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.surfaceElevated),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TYPES DE CONTENU',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            ..._contentTypes.entries.map((entry) {
              final isMuted =
                  perso?.mutedContentTypes.contains(entry.key) ?? false;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.value,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isMuted ? colors.textTertiary : null,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: !isMuted,
                    activeColor: colors.primary,
                    onChanged: (enabled) async {
                      final repo =
                          ref.read(personalizationRepositoryProvider);
                      if (enabled) {
                        await repo.unmuteContentType(entry.key);
                      } else {
                        await repo.muteContentType(entry.key);
                      }
                      ref.invalidate(personalizationProvider);
                    },
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}


/// Mode Serein toggle, styled like the tile in the Réglages sheet.
class _SereinToggleTile extends StatelessWidget {
  final bool enabled;
  final VoidCallback onChanged;

  const _SereinToggleTile({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final borderRadius = BorderRadius.circular(FacteurRadius.large);
    return Material(
      color: colors.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onChanged,
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: colors.surfaceElevated),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SereinColors.sereinColor.withOpacity(0.12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  SereinColors.sereinIcon,
                  color: SereinColors.sereinColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Serein',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Une lecture plus calme, sans urgence',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeColor: SereinColors.sereinColor,
                onChanged: (_) => onChanged(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
