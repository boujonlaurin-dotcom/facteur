import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../custom_topics/providers/theme_priority_provider.dart';
import '../models/content_model.dart';

enum FavoriteTabKind { tous, subjectTopic, subjectEntity, theme }

@immutable
class FavoriteTabModel {
  final FavoriteTabKind kind;
  final String? slug; // null for "Tous"
  final String label;
  final String emoji; // empty if none
  final int count;
  final bool active;

  const FavoriteTabModel({
    required this.kind,
    required this.slug,
    required this.label,
    required this.emoji,
    required this.count,
    required this.active,
  });
}

class FavoriteTopicTabs extends ConsumerStatefulWidget {
  final List<Content> items;
  final String? selectedTopicSlug;
  final String? selectedThemeSlug;
  final String? selectedEntitySlug;
  final void Function(FavoriteTabKind kind, String? slug) onTabTap;
  final VoidCallback onTapActiveTab;
  final VoidCallback onAddFavorite;

  const FavoriteTopicTabs({
    super.key,
    required this.items,
    this.selectedTopicSlug,
    this.selectedThemeSlug,
    this.selectedEntitySlug,
    required this.onTabTap,
    required this.onTapActiveTab,
    required this.onAddFavorite,
  });

  @override
  ConsumerState<FavoriteTopicTabs> createState() => _FavoriteTopicTabsState();
}

class _FavoriteTopicTabsState extends ConsumerState<FavoriteTopicTabs> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  GlobalKey? _activeKey;

  @override
  void didUpdateWidget(covariant FavoriteTopicTabs old) {
    super.didUpdateWidget(old);
    final selectionChanged =
        old.selectedTopicSlug != widget.selectedTopicSlug ||
            old.selectedThemeSlug != widget.selectedThemeSlug ||
            old.selectedEntitySlug != widget.selectedEntitySlug;
    if (selectionChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollActiveIntoView();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollActiveIntoView() {
    final ctx = _activeKey?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
  }

  GlobalKey _keyFor(FavoriteTabModel tab) {
    final id = '${tab.kind.name}:${tab.slug ?? '_'}';
    final key = _itemKeys.putIfAbsent(id, () => GlobalKey());
    if (tab.active) _activeKey = key;
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final topicsAsync = ref.watch(customTopicsProvider);
    final themePriorityAsync = ref.watch(themePriorityProvider);

    final topics = topicsAsync.valueOrNull ?? const <UserTopicProfile>[];
    final themePriority =
        themePriorityAsync.valueOrNull ?? const <String, double>{};

    final tabs = _buildTabModels(
      topics: topics,
      themePriority: themePriority,
      items: widget.items,
      selectedTopicSlug: widget.selectedTopicSlug,
      selectedThemeSlug: widget.selectedThemeSlug,
      selectedEntitySlug: widget.selectedEntitySlug,
    );

    _activeKey = null;

    return SizedBox(
      height: 32,
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.92, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 16),
          itemCount: tabs.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 2),
          itemBuilder: (ctx, i) {
            if (i == tabs.length) {
              return _AddFavoritePill(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onAddFavorite();
                },
                colors: colors,
              );
            }
            final tab = tabs[i];
            return _FavoriteTabItem(
              key: _keyFor(tab),
              tab: tab,
              colors: colors,
              onTap: () {
                if (tab.active) {
                  widget.onTapActiveTab();
                } else {
                  HapticFeedback.selectionClick();
                  widget.onTabTap(tab.kind, tab.slug);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

final Map<String, String> _apiSlugToMacroLabel = {
  for (final e in macroThemeToApiSlug.entries) e.value: e.key,
};

@visibleForTesting
List<FavoriteTabModel> buildFavoriteTabModelsForTest({
  required List<UserTopicProfile> topics,
  required Map<String, double> themePriority,
  required List<Content> items,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
}) =>
    _buildTabModels(
      topics: topics,
      themePriority: themePriority,
      items: items,
      selectedTopicSlug: selectedTopicSlug,
      selectedThemeSlug: selectedThemeSlug,
      selectedEntitySlug: selectedEntitySlug,
    );

List<FavoriteTabModel> _buildTabModels({
  required List<UserTopicProfile> topics,
  required Map<String, double> themePriority,
  required List<Content> items,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
}) {
  final themeApiSlugs = macroThemeToApiSlug.values.toSet();

  final entitySubjects = topics
      .where((t) => t.entityType != null && t.priorityMultiplier == 2.0)
      .toList()
    ..sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

  final topicSubjects = topics
      .where((t) =>
          t.entityType == null &&
          t.priorityMultiplier == 2.0 &&
          !themeApiSlugs.contains(t.slugParent))
      .toList()
    ..sort((a, b) {
      final byPriority = b.priorityMultiplier.compareTo(a.priorityMultiplier);
      if (byPriority != 0) return byPriority;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final favoriteThemes = macroThemeOrder
      .where((label) => (themePriority[label] ?? 1.0) == 2.0)
      .toList();

  final cutoff = DateTime.now().subtract(const Duration(hours: 48));
  final tabs = <FavoriteTabModel>[];

  // 1. Tous (always first).
  tabs.add(FavoriteTabModel(
    kind: FavoriteTabKind.tous,
    slug: null,
    label: 'Tous',
    emoji: '',
    count: _countUnreadRecent(items,
        cutoff: cutoff, kind: FavoriteTabKind.tous, slug: null),
    active: selectedTopicSlug == null &&
        selectedThemeSlug == null &&
        selectedEntitySlug == null,
  ));

  // 2. Sujets favoris : entités puis topics.
  for (final entity in entitySubjects) {
    final slug = entity.canonicalName ?? entity.name;
    tabs.add(FavoriteTabModel(
      kind: FavoriteTabKind.subjectEntity,
      slug: slug,
      label: entity.name,
      emoji: '',
      count: _countUnreadRecent(items,
          cutoff: cutoff, kind: FavoriteTabKind.subjectEntity, slug: slug),
      active: selectedEntitySlug != null && selectedEntitySlug == slug,
    ));
  }

  for (final topic in topicSubjects) {
    final slug = topic.slugParent ?? topic.id;
    tabs.add(FavoriteTabModel(
      kind: FavoriteTabKind.subjectTopic,
      slug: slug,
      label: topic.name,
      emoji: '',
      count: _countUnreadRecent(items,
          cutoff: cutoff, kind: FavoriteTabKind.subjectTopic, slug: slug),
      active: selectedTopicSlug != null && selectedTopicSlug == slug,
    ));
  }

  // 3. Thèmes favoris.
  for (final label in favoriteThemes) {
    final apiSlug = macroThemeToApiSlug[label];
    if (apiSlug == null) continue;
    tabs.add(FavoriteTabModel(
      kind: FavoriteTabKind.theme,
      slug: apiSlug,
      label: label,
      emoji: getMacroThemeEmoji(label),
      count: _countUnreadRecent(items,
          cutoff: cutoff, kind: FavoriteTabKind.theme, slug: apiSlug),
      active: selectedThemeSlug != null && selectedThemeSlug == apiSlug,
    ));
  }

  return tabs;
}

int _countUnreadRecent(
  List<Content> items, {
  required DateTime cutoff,
  required FavoriteTabKind kind,
  required String? slug,
}) {
  bool matches(Content c) {
    switch (kind) {
      case FavoriteTabKind.tous:
        return true;
      case FavoriteTabKind.subjectTopic:
        return slug != null && c.topics.contains(slug);
      case FavoriteTabKind.subjectEntity:
        if (slug == null) return false;
        final lower = slug.toLowerCase();
        return c.entities.any((e) => e.text.toLowerCase() == lower);
      case FavoriteTabKind.theme:
        if (slug == null) return false;
        final label = _apiSlugToMacroLabel[slug];
        if (label == null) return false;
        final themeSlugs = getSlugsForMacroTheme(label);
        return c.topics.any(themeSlugs.contains);
    }
  }

  return items
      .where((c) =>
          c.status == ContentStatus.unseen &&
          c.publishedAt.isAfter(cutoff) &&
          matches(c))
      .length;
}

class _FavoriteTabItem extends StatelessWidget {
  final FavoriteTabModel tab;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _FavoriteTabItem({
    super.key,
    required this.tab,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        tab.active ? colors.textPrimary : colors.textSecondary;
    final labelWeight = tab.active ? FontWeight.w700 : FontWeight.w500;
    final countColor =
        tab.active ? colors.primary : colors.textTertiary;
    final showLabel =
        tab.emoji.isNotEmpty ? '${tab.emoji} ${tab.label}' : tab.label;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IntrinsicWidth(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    showLabel,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: labelWeight,
                      color: labelColor,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: tab.active ? colors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            if (tab.count > 0) ...[
              const SizedBox(width: 4),
              Transform.translate(
                offset: const Offset(0, -6),
                child: Text(
                  '${tab.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: countColor,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddFavoritePill extends StatelessWidget {
  final VoidCallback onTap;
  final FacteurColors colors;

  const _AddFavoritePill({
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 32,
        child: Center(
          child: Icon(
            PhosphorIcons.plus(PhosphorIconsStyle.regular),
            size: 16,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
