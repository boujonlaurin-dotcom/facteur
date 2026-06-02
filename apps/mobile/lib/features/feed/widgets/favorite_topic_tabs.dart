import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/content_model.dart';
import '../providers/tab_order_prefs_provider.dart';
import '../repositories/feed_repository.dart';

enum FavoriteTabKind { subjectTopic, subjectEntity, theme, source }

/// Nombre maximum d'onglets épinglés rendus dans la barre Flâner. Au-delà, on
/// garde les [kMaxFavoriteTabs] premiers dans l'ordre validé par l'utilisateur
/// (drag de la modal) ; le surplus reste gérable dans la modal d'épinglage.
const int kMaxFavoriteTabs = 10;

@immutable
class FavoriteTabModel {
  final FavoriteTabKind kind;
  final String? slug; // null for "Tous"
  final String label;
  final String emoji; // empty if none
  final int count;
  final bool active;

  /// Renseigné uniquement pour [FavoriteTabKind.source] : sert à rendre le logo
  /// (avec fallback initiales) via [SourceLogoAvatar].
  final Source? source;

  const FavoriteTabModel({
    required this.kind,
    required this.slug,
    required this.label,
    required this.emoji,
    required this.count,
    required this.active,
    this.source,
  });
}

class FavoriteTopicTabs extends ConsumerStatefulWidget {
  final List<Content> items;
  final TabCounts? serverCounts;
  final String? selectedTopicSlug;
  final String? selectedThemeSlug;
  final String? selectedEntitySlug;
  final String? selectedSourceId;
  final void Function(FavoriteTabKind kind, String? slug) onTabTap;
  final VoidCallback onTapActiveTab;
  final VoidCallback onAddFavorite;

  const FavoriteTopicTabs({
    super.key,
    required this.items,
    this.serverCounts,
    this.selectedTopicSlug,
    this.selectedThemeSlug,
    this.selectedEntitySlug,
    this.selectedSourceId,
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
            old.selectedEntitySlug != widget.selectedEntitySlug ||
            old.selectedSourceId != widget.selectedSourceId;
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
    final sourcesStateAsync = ref.watch(userSourcesStateProvider);
    final sourcesAsync = ref.watch(userSourcesProvider);
    final order = ref.watch(tabOrderPrefsProvider);

    final topics = topicsAsync.valueOrNull ?? const <UserTopicProfile>[];
    final favorites =
        interestsAsync.valueOrNull?.favorites ?? const <FavoriteRef>[];
    final sourceFavorites =
        sourcesStateAsync.valueOrNull?.favorites ?? const <SourceFavoriteRef>[];
    final sourceById = <String, Source>{
      for (final s in sourcesAsync.valueOrNull ?? const <Source>[]) s.id: s,
    };

    final tabs = _buildTabModels(
      topics: topics,
      favorites: favorites,
      sourceFavorites: sourceFavorites,
      sourceById: sourceById,
      order: order,
      items: widget.items,
      serverCounts: widget.serverCounts,
      selectedTopicSlug: widget.selectedTopicSlug,
      selectedThemeSlug: widget.selectedThemeSlug,
      selectedEntitySlug: widget.selectedEntitySlug,
      selectedSourceId: widget.selectedSourceId,
    );

    _activeKey = null;
    // > 4 onglets épinglés → l'affordance d'ajout devient un engrenage
    // (« gérer ») plutôt qu'un « + ». Même action (ouvre la modal).
    final showGear = tabs.length > 4;

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
                showGear: showGear,
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
                // Taper l'onglet actif = vider la sélection (feed non filtré) ;
                // le refresh est assuré par le pull-to-refresh de la page.
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

@visibleForTesting
List<FavoriteTabModel> buildFavoriteTabModelsForTest({
  required List<UserTopicProfile> topics,
  required List<FavoriteRef> favorites,
  required List<Content> items,
  List<SourceFavoriteRef> sourceFavorites = const [],
  Map<String, Source> sourceById = const {},
  List<String> order = const [],
  TabCounts? serverCounts,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
  String? selectedSourceId,
}) =>
    _buildTabModels(
      topics: topics,
      favorites: favorites,
      sourceFavorites: sourceFavorites,
      sourceById: sourceById,
      order: order,
      items: items,
      serverCounts: serverCounts,
      selectedTopicSlug: selectedTopicSlug,
      selectedThemeSlug: selectedThemeSlug,
      selectedEntitySlug: selectedEntitySlug,
      selectedSourceId: selectedSourceId,
    );

/// Onglets Flâner = *sujets épinglés* (custom topics + entités favoris) **et**
/// *sources épinglées* (favoris sources), mélangés selon l'ordre unifié
/// [order] (cf. [tabOrderPrefsProvider]). Les *thèmes/veille* pilotent la
/// Tournée du jour et ne sont donc pas rendus en onglet ici — ils restent
/// filtrables via la chip thème.
List<FavoriteTabModel> _buildTabModels({
  required List<UserTopicProfile> topics,
  required List<FavoriteRef> favorites,
  required List<SourceFavoriteRef> sourceFavorites,
  required Map<String, Source> sourceById,
  required List<String> order,
  required List<Content> items,
  TabCounts? serverCounts,
  String? selectedTopicSlug,
  String? selectedThemeSlug,
  String? selectedEntitySlug,
  String? selectedSourceId,
}) {
  final useServer = serverCounts != null && serverCounts.total > 0;

  final favoriteCustomIds = <String>{
    for (final f in favorites)
      if (f is CustomTopicFavoriteRef) f.id,
  };

  // Diagnostic : un sujet favori sans `UserTopicProfile` correspondant dans
  // `topics` ne produira aucun onglet (hypothèse : `customTopicsProvider`
  // incomplet vs `userInterestsProvider.favorites`).
  if (kDebugMode) {
    final knownTopicIds = {for (final t in topics) t.id};
    final orphanFavorites =
        favoriteCustomIds.where((id) => !knownTopicIds.contains(id)).toList();
    if (orphanFavorites.isNotEmpty) {
      debugPrint(
        '[FavoriteTabs] ${orphanFavorites.length} sujet(s) favori(s) sans '
        'UserTopicProfile (customTopicsProvider incomplet ?) : $orphanFavorites',
      );
    }
  }

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

  // Onglets favoris (sujets + sources épinglés). On garde la clé d'ordre unifié
  // (`topic:<id>` / `source:<id>`) à côté de chaque modèle pour pouvoir
  // appliquer [order] ensuite. L'ordre d'insertion (entités, sujets, sources)
  // reflète celui de la section « ÉPINGLÉS » de la modal : barre et modal
  // passent ensuite par le même [applyOrder] avec les mêmes prefs.
  final favoriteTabs = <({FavoriteTabModel tab, String key})>[];

  for (final entity in entitySubjects) {
    final slug = entity.canonicalName ?? entity.name;
    favoriteTabs.add((
      key: tabOrderTopicKey(entity.id),
      tab: FavoriteTabModel(
        kind: FavoriteTabKind.subjectEntity,
        slug: slug,
        label: entity.name,
        emoji: '',
        count: useServer
            ? (serverCounts.entities[slug.toLowerCase()] ?? 0)
            : _countUnreadRecent(items,
                cutoff: cutoff,
                kind: FavoriteTabKind.subjectEntity,
                slug: slug),
        active: selectedEntitySlug != null && selectedEntitySlug == slug,
      ),
    ));
  }

  for (final topic in topicSubjects) {
    final slug = topic.slugParent ?? topic.id;
    favoriteTabs.add((
      key: tabOrderTopicKey(topic.id),
      tab: FavoriteTabModel(
        kind: FavoriteTabKind.subjectTopic,
        slug: slug,
        label: topic.name,
        emoji: '',
        count: useServer
            ? (serverCounts.topics[slug] ?? 0)
            : _countUnreadRecent(items,
                cutoff: cutoff,
                kind: FavoriteTabKind.subjectTopic,
                slug: slug),
        active: selectedTopicSlug != null && selectedTopicSlug == slug,
      ),
    ));
  }

  // Sources épinglées (favoris sources). Pas de count serveur par source pour
  // l'instant → count 0 (pas de badge). On skippe les sources inconnues du
  // catalogue (logo/nom non résolus).
  final sortedSourceFavorites = [...sourceFavorites]
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final ref in sortedSourceFavorites) {
    final source = sourceById[ref.sourceId];
    if (source == null) continue;
    favoriteTabs.add((
      key: tabOrderSourceKey(ref.sourceId),
      tab: FavoriteTabModel(
        kind: FavoriteTabKind.source,
        slug: ref.sourceId,
        label: source.name,
        emoji: '',
        count: 0,
        active: selectedSourceId != null && selectedSourceId == ref.sourceId,
        source: source,
      ),
    ));
  }

  // Ordre unifié voulu par l'utilisateur (drag dans la modal d'épinglage). Plus
  // de tri par count : il reléguait les sources (count: 0 codé en dur) derrière
  // tout sujet ayant des non-lus → elles finissaient en fin de liste, cachées
  // derrière le fade (« sujets/sources disparus »). On conserve l'ordre
  // d'insertion comme base, puis on applique l'ordre custom.
  final ordered = applyOrder(favoriteTabs, order, (e) => e.key);

  // Cap : garder les [kMaxFavoriteTabs] premiers dans l'ordre utilisateur. Pas
  // de troncature silencieuse — on logge les clés du surplus en debug.
  final capped = ordered.take(kMaxFavoriteTabs).toList();
  if (kDebugMode && ordered.length > kMaxFavoriteTabs) {
    final dropped = ordered.skip(kMaxFavoriteTabs).map((e) => e.key).toList();
    debugPrint(
      '[FavoriteTabs] cap $kMaxFavoriteTabs atteint — '
      '${dropped.length} onglet(s) tronqué(s) : $dropped',
    );
  }

  tabs.addAll(capped.map((e) => e.tab));
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
      case FavoriteTabKind.source:
        // Pas de count local par source — les onglets source affichent 0.
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
    final sourceAvatar =
        tab.kind == FavoriteTabKind.source && tab.source != null
            ? tab.source
            : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (sourceAvatar != null) ...[
              SourceLogoAvatar(source: sourceAvatar, size: 20, radius: 5),
              const SizedBox(width: 6),
            ],
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
  final bool showGear;
  final VoidCallback onTap;
  final FacteurColors colors;

  const _AddFavoritePill({
    required this.showGear,
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
            showGear
                ? PhosphorIcons.gear(PhosphorIconsStyle.regular)
                : PhosphorIcons.plus(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
