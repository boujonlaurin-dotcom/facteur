import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../flux_continu/providers/flux_continu_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../providers/feed_provider.dart';
import '../providers/tab_counts_provider.dart';
import 'compact_source_chip.dart';
import 'compact_theme_chip.dart';
import 'favorite_topic_tabs.dart';
import 'filter_collapsible_panel.dart';
import 'interest_filter_sheet.dart';
import 'search_filter_sheet.dart';

/// Compact, self-contained version of `FeedScreen._buildFilterBar`, intended
/// to live as the sticky overlay in the Explorer zone of the Flux Continu
/// screen. Drives `feedProvider` directly — filter changes propagate to any
/// other screen watching the same provider.
///
/// The full `FeedScreen` filter bar adds [FavoriteTopicTabs] + scroll-to-top
/// + a refresh-indicator wrapper; those are tied to scroll/state management
/// that doesn't make sense in the Flux Continu Explorer context, so this
/// widget intentionally omits them. If they are needed in the future, hoist
/// them here behind optional callbacks rather than duplicating the logic.
class FeedFilterBar extends ConsumerStatefulWidget {
  final VoidCallback? onAfterChange;

  const FeedFilterBar({super.key, this.onAfterChange});

  @override
  ConsumerState<FeedFilterBar> createState() => _FeedFilterBarState();
}

class _FeedFilterBarState extends ConsumerState<FeedFilterBar> {
  String? _selectedInterestName;
  bool _selectedIsTheme = false;

  int _activeFilterCount() {
    final notifier = ref.read(feedProvider.notifier);
    var count = 0;
    if (notifier.selectedSourceId != null) count++;
    if (notifier.selectedKeyword != null &&
        notifier.selectedKeyword!.isNotEmpty) {
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(feedProvider.notifier);
    final hasSearch = notifier.selectedKeyword != null &&
        notifier.selectedKeyword!.isNotEmpty;
    final feedItems =
        ref.watch(feedProvider).valueOrNull?.items ?? const <dynamic>[];
    final serverCounts = ref.watch(tabCountsProvider).valueOrNull;
    final tourneeSlugs = ref
            .watch(fluxContinuProvider)
            .valueOrNull
            ?.tourneeThemeSlugs ??
        const <String>[];
    return FilterCollapsiblePanel(
      activeCount: _activeFilterCount(),
      chipsRow: _buildChipsRow(context),
      leadingContent: FavoriteTopicTabs(
        items: feedItems.cast(),
        serverCounts: serverCounts,
        selectedTopicSlug: notifier.selectedTopic,
        selectedThemeSlug: notifier.selectedTheme,
        selectedEntitySlug: notifier.selectedEntity,
        excludedThemeSlugs: tourneeSlugs,
        onTabTap: (kind, slug) async {
          switch (kind) {
            case FavoriteTabKind.tous:
              await notifier.setTopic(null);
              await notifier.setTheme(null);
              await notifier.setEntity(null);
              break;
            case FavoriteTabKind.subjectTopic:
              await notifier.setTopic(slug);
              break;
            case FavoriteTabKind.subjectEntity:
              await notifier.setEntity(slug);
              break;
            case FavoriteTabKind.theme:
              await notifier.setTheme(slug);
              break;
          }
          if (mounted) {
            setState(() {
              _selectedInterestName = null;
              _selectedIsTheme = kind == FavoriteTabKind.theme;
            });
          }
          widget.onAfterChange?.call();
        },
        onTapActiveTab: () => widget.onAfterChange?.call(),
        onTapActiveTabRefresh: () {
          HapticFeedback.mediumImpact();
          widget.onAfterChange?.call();
        },
        onAddFavorite: () {
          HapticFeedback.mediumImpact();
          InterestFilterSheet.show(
            context,
            currentTopicSlug: notifier.selectedTopic ??
                notifier.selectedTheme ??
                notifier.selectedEntity,
            currentIsTheme: notifier.selectedTheme != null,
            onInterestSelected:
                (slug, name, {bool isTheme = false, bool isEntity = false}) async {
              setState(() {
                _selectedInterestName = name;
                _selectedIsTheme = isTheme;
              });
              if (isTheme) {
                await notifier.setTheme(slug);
              } else if (isEntity) {
                await notifier.setEntity(slug);
              } else {
                await notifier.setTopic(slug);
              }
              widget.onAfterChange?.call();
            },
          );
        },
      ),
      leadingTrigger: _SearchTrigger(
        active: hasSearch,
        keyword: notifier.selectedKeyword,
        onTap: () {
          HapticFeedback.mediumImpact();
          SearchFilterSheet.show(
            context,
            currentKeyword: notifier.selectedKeyword,
            onSearchSubmitted: (keyword, {bool fromTrending = false}) async {
              await notifier.setKeyword(
                keyword,
                includeUnfollowed: fromTrending,
              );
              widget.onAfterChange?.call();
            },
          );
        },
        onClear: () async {
          await HapticFeedback.mediumImpact();
          await notifier.setKeyword(null);
          widget.onAfterChange?.call();
        },
      ),
    );
  }

  Widget _buildChipsRow(BuildContext context) {
    final notifier = ref.read(feedProvider.notifier);

    if (notifier.selectedTheme == null &&
        notifier.selectedTopic == null &&
        notifier.selectedEntity == null) {
      _selectedInterestName = null;
      _selectedIsTheme = false;
    }

    final allSources = ref.watch(userSourcesProvider).valueOrNull ?? [];
    final followedSources = allSources
        .where((s) => (s.isTrusted || s.isCustom) && !s.isMuted)
        .toList();
    final selectedSourceId = notifier.selectedSourceId;
    final selectedSource = selectedSourceId != null
        ? followedSources.where((s) => s.id == selectedSourceId).firstOrNull
        : null;

    return Row(
      children: [
        Flexible(
          child: CompactSourceChip(
            followedSources: followedSources,
            selectedSourceId: selectedSourceId,
            selectedSourceName: selectedSource?.name,
            selectedSourceLogoUrl: selectedSource?.logoUrl,
            discreet: true,
            onSourceChanged: (sourceId) async {
              await notifier.setSource(sourceId);
              widget.onAfterChange?.call();
            },
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: CompactThemeChip(
            selectedSlug: notifier.selectedTopic ??
                notifier.selectedTheme ??
                notifier.selectedEntity,
            selectedName: _selectedInterestName,
            selectedIsTheme: _selectedIsTheme,
            discreet: true,
            onInterestChanged: (slug, name,
                {bool isTheme = false, bool isEntity = false}) async {
              setState(() {
                _selectedInterestName = name;
                _selectedIsTheme = isTheme;
              });
              if (slug == null) {
                await notifier.setTopic(null);
                await notifier.setTheme(null);
                await notifier.setEntity(null);
              } else if (isTheme) {
                await notifier.setTheme(slug);
              } else if (isEntity) {
                await notifier.setEntity(slug);
              } else {
                await notifier.setTopic(slug);
              }
              widget.onAfterChange?.call();
            },
          ),
        ),
      ],
    );
  }
}

/// Minimal search trigger — magnifier icon when idle, keyword pill with clear
/// button when a search is active. Visually aligned with `FilterCollapsiblePanel`
/// (32 px tall, primary accent when active).
class _SearchTrigger extends StatelessWidget {
  final bool active;
  final String? keyword;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _SearchTrigger({
    required this.active,
    required this.keyword,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final primary = colors.primary;
    if (active) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            border: Border.all(color: primary),
            borderRadius: BorderRadius.circular(FacteurRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                size: 14,
                color: primary,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  keyword ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.bold),
                    size: 12,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 32,
        width: 32,
        child: Icon(
          PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
          size: 18,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
