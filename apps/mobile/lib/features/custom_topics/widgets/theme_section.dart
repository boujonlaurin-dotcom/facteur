import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../../../config/topic_labels.dart';
import '../models/topic_models.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../providers/algorithm_profile_provider.dart';
import '../providers/custom_topics_provider.dart';
import '../providers/personalization_provider.dart';
import '../providers/serein_exclusions_provider.dart';
import '../providers/theme_priority_provider.dart';
import 'entity_add_sheet.dart';
import 'suggestion_row.dart';
import 'topic_priority_slider.dart';
import 'topic_row.dart';

/// Surfaces the real backend detail (or status) for serein-mode mutations so
/// the user can understand why a toggle didn't stick (e.g. staging without the
/// `excluded_from_serein` column deployed yet).
void _showSereinError(BuildContext context, DioException e) {
  final data = e.response?.data;
  String? detail;
  if (data is Map) {
    final raw = data['detail'];
    if (raw is String) {
      detail = raw;
    } else if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map && first['msg'] is String) {
        detail = first['msg'] as String;
      }
    }
  }
  final status = e.response?.statusCode;
  final message = detail != null
      ? 'Erreur${status != null ? ' $status' : ''} : $detail'
      : 'Erreur${status != null ? ' $status' : ''} — mise à jour refusée';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// A collapsible section grouping followed topics and suggestions under a macro theme.
class ThemeSection extends ConsumerWidget {
  final String themeSlug;
  final String themeLabel;
  final List<UserTopicProfile> followedTopics;
  /// slug → display label (preserves original casing, e.g. "NBA").
  final Map<String, String> mutedTopicSlugs;
  final bool sereinMode;

  const ThemeSection({
    super.key,
    required this.themeSlug,
    required this.themeLabel,
    required this.followedTopics,
    this.mutedTopicSlugs = const {},
    this.sereinMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final themePriorities =
        ref.watch(themePriorityProvider).valueOrNull ?? <String, double>{};
    final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
    final perso = ref.watch(personalizationProvider).valueOrNull;
    final isMuted = perso?.mutedThemes.contains(themeSlug.toLowerCase()) ?? false;

    // Muted theme: collapsed, greyed out, with unmute action
    if (isMuted) {
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
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space4,
              vertical: FacteurSpacing.space1,
            ),
            title: Text(
              '${getMacroThemeEmoji(themeLabel)} ${themeLabel.toUpperCase()} (masqué)',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary.withOpacity(0.5),
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: GestureDetector(
              onTap: () async {
                await ref
                    .read(personalizationRepositoryProvider)
                    .unmuteTheme(themeSlug);
                if (!context.mounted) return;
                ref.invalidate(personalizationProvider);
              },
              child: Icon(
                PhosphorIcons.plusCircle(PhosphorIconsStyle.regular),
                size: 20,
                color: colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

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
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space4,
              vertical: FacteurSpacing.space1,
            ),
            childrenPadding: const EdgeInsets.only(
              bottom: FacteurSpacing.space3,
            ),
            title: _ThemeHeader(
              themeSlug: themeSlug,
              themeLabel: themeLabel,
              followedTopics: followedTopics,
              sereinMode: sereinMode,
              themePriorities: themePriorities,
              algoProfile: algoProfile,
            ),
            children: [
              // Followed topics
              ...followedTopics.map((topic) {
                final topicSlug = topic.slugParent;
                final topicMuted = topicSlug != null &&
                    (perso?.mutedTopics.contains(topicSlug.toLowerCase()) ?? false);
                final topicUsage = algoProfile != null &&
                        topicSlug != null &&
                        algoProfile.subtopicWeights.containsKey(topicSlug)
                    ? algoProfile
                        .normalizeWeight(algoProfile.subtopicWeights[topicSlug]!)
                    : null;
                return DismissibleTopicRow(
                    topic: topic,
                    usageWeight: topicUsage,
                    isMuted: topicMuted,
                    sereinMode: sereinMode,
                    sereinShown: !topic.excludedFromSerein,
                    onSereinToggle: sereinMode
                        ? (shown) async {
                            try {
                              await ref
                                  .read(customTopicsProvider.notifier)
                                  .setExcludedFromSerein(topic.id, !shown);
                            } on DioException catch (e) {
                              if (!context.mounted) return;
                              _showSereinError(context, e);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Impossible de mettre à jour ce sujet.',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        : null,
                    onMute: () async {
                      // For entities, mute by canonical name (matches backend entity filtering).
                      // For regular topics, mute by slug_parent.
                      final slug = topic.canonicalName?.toLowerCase() ??
                          topicSlug ??
                          getTopicSlug(topic.name);
                      final repo = ref.read(personalizationRepositoryProvider);
                      try {
                        await repo.muteTopic(slug);
                        if (!context.mounted) return;
                        await ref
                            .read(customTopicsProvider.notifier)
                            .unfollowTopic(topic.id);
                        if (!context.mounted) return;
                        ref.invalidate(personalizationProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sujet masqué'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Erreur lors du masquage'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    onUnmute: topicSlug != null
                        ? () async {
                            await ref
                                .read(personalizationRepositoryProvider)
                                .unmuteTopic(topicSlug);
                            if (!context.mounted) return;
                            ref.invalidate(personalizationProvider);
                          }
                        : null,
                    onReset: topicSlug != null && topicUsage != null
                        ? () async {
                            final client = ref.read(apiClientProvider);
                            await client.post('/users/subtopics/$topicSlug/reset');
                            if (!context.mounted) return;
                            ref.invalidate(algorithmProfileProvider);
                          }
                        : null,
                    onPriorityChanged: (multiplier) async {
                      try {
                        await ref
                            .read(customTopicsProvider.notifier)
                            .updatePriority(topic.id, multiplier);
                      } on DioException catch (e) {
                        if (context.mounted) {
                          final detail = e.response?.data;
                          final msg =
                              (detail is Map && detail['detail'] is String)
                                  ? detail['detail'] as String
                                  : 'Erreur lors de la mise à jour';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    onUnfollow: () async {
                      await ref
                          .read(customTopicsProvider.notifier)
                          .unfollowTopic(topic.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Sujet retiré'),
                            duration: const Duration(seconds: 4),
                            action: SnackBarAction(
                              label: 'Annuler',
                              onPressed: () {
                                ref
                                    .read(customTopicsProvider.notifier)
                                    .followTopic(
                                      topic.name,
                                      slugParent: topic.slugParent,
                                      priorityMultiplier: topic.priorityMultiplier,
                                    );
                              },
                            ),
                          ),
                        );
                      }
                    },
                  );
              }),

              // Mute theme button
              if (!sereinMode)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space1,
                  ),
                  child: GestureDetector(
                    onTap: () async {
                      await ref
                          .read(personalizationRepositoryProvider)
                          .muteTheme(themeSlug);
                      if (!context.mounted) return;
                      ref.invalidate(personalizationProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thème masqué'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      '\u{1F441}\u{0338} Masquer ce thème',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),

              // Suggestions divider + suggestions
              if (!sereinMode)
                _SuggestionsBlock(
                  themeSlug: themeSlug,
                  followedTopics: followedTopics,
                ),

              // Muted topics for this theme
              if (!sereinMode && mutedTopicSlugs.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space2,
                  ),
                  child: Divider(
                    color: colors.textTertiary.withOpacity(0.15),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: FacteurSpacing.space4,
                    bottom: FacteurSpacing.space1,
                  ),
                  child: Text(
                    'Sujets masqués',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary.withOpacity(0.5),
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...mutedTopicSlugs.entries.map((entry) {
                  final slug = entry.key;
                  final label = entry.value;
                  return Opacity(
                    opacity: 0.5,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4,
                      ),
                      title: Text(
                        label,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      trailing: GestureDetector(
                        onTap: () async {
                          await ref
                              .read(personalizationRepositoryProvider)
                              .unmuteTopic(slug);
                          if (!context.mounted) return;
                          ref.invalidate(personalizationProvider);
                        },
                        child: Icon(
                          PhosphorIcons.plusCircle(
                            PhosphorIconsStyle.regular,
                          ),
                          size: 18,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // "Ajouter un sujet personnalisé" button
              if (!sereinMode)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space2,
                  ),
                  child: GestureDetector(
                    onTap: () =>
                        EntityAddSheet.show(context, themeSlug: themeSlug),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.plus(PhosphorIconsStyle.bold),
                          size: 14,
                          color: const Color(0xFFE07A5F),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ajouter un sujet personnalisé',
                          style: textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFE07A5F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme-section header row. Normal mode shows the usual mute + priority
/// controls; serein mode shows a tri-state checkbox that cascades to every
/// topic in the section.
class _ThemeHeader extends ConsumerWidget {
  final String themeSlug;
  final String themeLabel;
  final List<UserTopicProfile> followedTopics;
  final bool sereinMode;
  final Map<String, double> themePriorities;
  final AlgorithmProfile? algoProfile;

  const _ThemeHeader({
    required this.themeSlug,
    required this.themeLabel,
    required this.followedTopics,
    required this.sereinMode,
    required this.themePriorities,
    required this.algoProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final titleText = Expanded(
      child: Text(
        '${getMacroThemeEmoji(themeLabel)} ${themeLabel.toUpperCase()}',
        style: textTheme.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (sereinMode) {
      // Tri-state reflects theme-level exclusion first; topic-level overrides
      // show as indeterminate.
      final excl = ref.watch(sereinExclusionsProvider);
      final themeExcluded = excl.effectiveExclusions.contains(themeSlug);
      final topicsShown = followedTopics.where((t) => !t.excludedFromSerein);
      final topicsHidden = followedTopics.where((t) => t.excludedFromSerein);

      bool? checkValue;
      if (themeExcluded) {
        // Theme hidden → check state reflects topic overrides:
        //   all hidden  → false
        //   some hidden → null (indeterminate)
        if (topicsShown.isEmpty) {
          checkValue = false;
        } else {
          checkValue = null;
        }
      } else {
        // Theme shown → check state reflects topic overrides:
        //   none hidden → true
        //   some hidden → null
        if (topicsHidden.isEmpty) {
          checkValue = true;
        } else {
          checkValue = null;
        }
      }

      return Row(
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              tristate: true,
              value: checkValue,
              onChanged: (v) async {
                // Tri-state cascade:
                //   false/null → show everything (uncheck → check)
                //   true       → hide everything
                final shown = (checkValue != true);
                try {
                  await ref
                      .read(sereinExclusionsProvider.notifier)
                      .setThemeShownCascade(
                          themeSlug: themeSlug, shown: shown);
                  final topicsNotifier =
                      ref.read(customTopicsProvider.notifier);
                  for (final t in followedTopics) {
                    if (t.excludedFromSerein == shown) {
                      await topicsNotifier.setExcludedFromSerein(
                          t.id, !shown);
                    }
                  }
                } on DioException catch (e) {
                  if (!context.mounted) return;
                  _showSereinError(context, e);
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Impossible de mettre à jour ce thème.',
                      ),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          titleText,
        ],
      );
    }

    return Row(
      children: [
        titleText,
        GestureDetector(
          onTap: () async {
            await ref
                .read(personalizationRepositoryProvider)
                .muteTheme(themeSlug);
            if (!context.mounted) return;
            ref.invalidate(personalizationProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thème retiré'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              PhosphorIcons.minusCircle(PhosphorIconsStyle.regular),
              size: 16,
              color: const Color(0xFFE07A5F),
            ),
          ),
        ),
        TopicPrioritySlider(
          currentMultiplier: themePriorities[themeLabel] ?? 1.0,
          onChanged: (multiplier) async {
            await setThemePriority(themeLabel, multiplier);
            if (!context.mounted) return;
            ref.invalidate(themePriorityProvider);
          },
          usageWeight: algoProfile != null &&
                  algoProfile!.interestWeights.containsKey(themeSlug)
              ? algoProfile!
                  .normalizeWeight(algoProfile!.interestWeights[themeSlug]!)
              : null,
          onReset: algoProfile != null &&
                  algoProfile!.interestWeights.containsKey(themeSlug)
              ? () async {
                  final client = ref.read(apiClientProvider);
                  await client.post('/users/interests/$themeSlug/reset');
                  if (!context.mounted) return;
                  ref.invalidate(algorithmProfileProvider);
                }
              : null,
        ),
      ],
    );
  }
}

class _SuggestionsBlock extends ConsumerStatefulWidget {
  final String themeSlug;
  final List<UserTopicProfile> followedTopics;

  const _SuggestionsBlock({
    required this.themeSlug,
    required this.followedTopics,
  });

  @override
  ConsumerState<_SuggestionsBlock> createState() => _SuggestionsBlockState();
}

class _SuggestionsBlockState extends ConsumerState<_SuggestionsBlock> {
  static const int _initialLimit = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final suggestionsAsync =
        ref.watch(topicSuggestionsProvider(widget.themeSlug));

    return suggestionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        // Filter out already-followed topics
        final followedNames =
            widget.followedTopics.map((t) => t.name.toLowerCase()).toSet();
        final followedSlugs = widget.followedTopics
            .map((t) => t.slugParent)
            .whereType<String>()
            .toSet();
        final available = suggestions
            .where((s) => !followedNames.contains(s.toLowerCase()))
            .toList();

        // Supplement with local slugs when API returns few suggestions
        if (available.length < 5) {
          final macroTheme = getTopicMacroTheme(widget.themeSlug);
          if (macroTheme != null) {
            final localSlugs = getSlugsForMacroTheme(macroTheme);
            for (final slug in localSlugs) {
              if (available.length >= 8) break;
              if (followedSlugs.contains(slug)) continue;
              final label = getTopicLabel(slug);
              if (followedNames.contains(label.toLowerCase())) continue;
              if (available.any(
                  (s) => s.toLowerCase() == label.toLowerCase())) {
                continue;
              }
              available.add(label);
            }
          }
        }

        if (available.isEmpty) return const SizedBox.shrink();

        final visible =
            _expanded ? available : available.take(_initialLimit).toList();
        final hasMore = available.length > _initialLimit;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4,
                vertical: FacteurSpacing.space2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: colors.textTertiary.withOpacity(0.2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space2,
                    ),
                    child: Text(
                      'Suggestions',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: colors.textTertiary.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
            ),
            ...visible.map((name) => SuggestionRow(
                  name: name,
                  onFollow: () {
                    ref
                        .read(customTopicsProvider.notifier)
                        .followTopic(name);
                  },
                  onMute: () async {
                    final slug = getTopicSlug(name);
                    final repo = ref.read(personalizationRepositoryProvider);
                    try {
                      await repo.muteTopic(slug);
                      if (!mounted) return;
                      ref.invalidate(personalizationProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sujet masqué'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Erreur lors du masquage'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                )),
            if (hasMore && !_expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space2,
                  ),
                  child: Text(
                    'Voir plus...',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
