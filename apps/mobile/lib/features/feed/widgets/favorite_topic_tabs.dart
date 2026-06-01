import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';

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
  final TabCounts? serverCounts;
  final String? selectedTopicSlug;
  final String? selectedThemeSlug;
  final String? selectedEntitySlug;
  final void Function(FavoriteTabKind kind, String? slug) onTabTap;
  final VoidCallback onTapActiveTab;
  final VoidCallback onTapActiveTabRefresh;
  final VoidCallback onAddFavorite;

  const FavoriteTopicTabs({
    super.key,
    required this.items,
    this.serverCounts,
    this.selectedTopicSlug,
    this.selectedThemeSlug,
    this.selectedEntitySlug,
    required this.onTabTap,
    required this.onTapActiveTab,
    required this.onTapActiveTabRefresh,
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
    final interestsAsync = ref.watch(userInterestsProvider);

    final topics = topicsAsync.valueOrNull ?? const <UserTopicProfile>[];
    final favorites =
        interestsAsync.valueOrNull?.favorites ?? const <FavoriteRef>[];

    final tabs = _buildTabModels(
      topics: topics,
      favorites: favorites,
      items: widget.items,
      serverCounts: widget.serverCounts,
      selectedTopicSlug: widget.selectedTopicSlug,
      selectedThemeSlug: widget.selectedThemeSlug,
      selectedEntitySlug: widget.selectedEntitySlug,
    );

    _activeKey = null;

    return SizedBox(
      height: 38,
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
                  if (tab.count >= 3) {
                    widget.onTapActiveTabRefresh();
                  } else {
                    widget.onTapActiveTab();
                  }
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

@visibleForTesting
List<FavoriteTabModel> buildFavoriteTabModelsForTest({
  required List<UserTopicProfile> topics,
  required List<FavoriteRef> favorites,
  required List<Content> items,
  TabCounts? serverCounts,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
}) =>
    _buildTabModels(
      topics: topics,
      favorites: favorites,
      items: items,
      serverCounts: serverCounts,
      selectedTopicSlug: selectedTopicSlug,
      selectedThemeSlug: selectedThemeSlug,
      selectedEntitySlug: selectedEntitySlug,
    );

/// Onglets Flâner = uniquement les *sujets épinglés* (custom topics + entités
/// favoris). Les *thèmes/veille* pilotent la Tournée du jour et ne sont donc
/// pas rendus en onglet ici — ils restent filtrables via la chip thème.
List<FavoriteTabModel> _buildTabModels({
  required List<UserTopicProfile> topics,
  required List<FavoriteRef> favorites,
  required List<Content> items,
  TabCounts? serverCounts,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
}) {
  final useServer = serverCounts != null && serverCounts.total > 0;

  final favoriteCustomIds = <String>{
    for (final f in favorites)
      if (f is CustomTopicFavoriteRef) f.id,
  };

  final entitySubjects = topics
      .where((t) => t.entityType != null && favoriteCustomIds.contains(t.id))
      .toList()
    ..sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

  final topicSubjects = topics
      .where((t) =>
          t.entityType == null && favoriteCustomIds.contains(t.id))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final cutoff = DateTime.now().subtract(const Duration(hours: 48));
  final tabs = <FavoriteTabModel>[];

  // 1. Tous (always first).
  tabs.add(FavoriteTabModel(
    kind: FavoriteTabKind.tous,
    slug: null,
    label: 'Tous',
    emoji: '',
    count: useServer
        ? serverCounts.total
        : _countUnreadRecent(items,
            cutoff: cutoff, kind: FavoriteTabKind.tous, slug: null),
    active: selectedTopicSlug == null &&
        selectedThemeSlug == null &&
        selectedEntitySlug == null,
  ));

  // 2. Onglets favoris (entités + sujets épinglés) triés par nombre
  // d'articles disponibles décroissant.
  final favoriteTabs = <FavoriteTabModel>[];

  for (final entity in entitySubjects) {
    final slug = entity.canonicalName ?? entity.name;
    favoriteTabs.add(FavoriteTabModel(
      kind: FavoriteTabKind.subjectEntity,
      slug: slug,
      label: entity.name,
      emoji: '',
      count: useServer
          ? (serverCounts.entities[slug.toLowerCase()] ?? 0)
          : _countUnreadRecent(items,
              cutoff: cutoff, kind: FavoriteTabKind.subjectEntity, slug: slug),
      active: selectedEntitySlug != null && selectedEntitySlug == slug,
    ));
  }

  for (final topic in topicSubjects) {
    final slug = topic.slugParent ?? topic.id;
    favoriteTabs.add(FavoriteTabModel(
      kind: FavoriteTabKind.subjectTopic,
      slug: slug,
      label: topic.name,
      emoji: '',
      count: useServer
          ? (serverCounts.topics[slug] ?? 0)
          : _countUnreadRecent(items,
              cutoff: cutoff, kind: FavoriteTabKind.subjectTopic, slug: slug),
      active: selectedTopicSlug != null && selectedTopicSlug == slug,
    ));
  }

  favoriteTabs.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });

  tabs.addAll(favoriteTabs);
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
        // Les thèmes ne sont plus rendus en onglet Flâner (ils pilotent la
        // Tournée). Valeur conservée dans l'enum pour la chip thème.
        return false;
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
    final showBadge = tab.count >= 3;
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
                    height: 2,
                    decoration: BoxDecoration(
                      color: tab.active ? colors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            if (showBadge) ...[
              const SizedBox(width: 5),
              Transform.translate(
                offset: const Offset(0, -6),
                child: tab.active
                    ? Container(
                        width: 6.5,
                        height: 6.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary,
                        ),
                      )
                    : Text(
                        tab.count > 10 ? '10+' : '${tab.count}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.textTertiary,
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
        width: 34,
        height: 38,
        child: Center(
          child: Icon(
            PhosphorIcons.plus(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
