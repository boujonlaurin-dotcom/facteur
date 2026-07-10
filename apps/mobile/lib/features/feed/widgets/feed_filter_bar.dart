import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../sources/providers/sources_providers.dart';
import '../providers/feed_provider.dart';
import '../providers/tab_counts_provider.dart';
import 'compact_source_chip.dart';
import 'compact_theme_chip.dart';
import 'favorite_topic_tabs.dart';
import 'filter_collapsible_panel.dart';
import 'pin_subjects_sheet.dart';
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

  const FeedFilterBar({
    super.key,
    this.onAfterChange,
  });

  @override
  ConsumerState<FeedFilterBar> createState() => _FeedFilterBarState();
}

class _FeedFilterBarState extends ConsumerState<FeedFilterBar> {
  /// Label affiché par la chip "thème/sujet" — défini quand la sélection vient
  /// du sheet (`InterestFilterSheet`) qui connaît le `name`. Quand la
  /// sélection vient d'un onglet [FavoriteTopicTabs], on ne le surcharge pas :
  /// la chip retombe sur 'Thème' / 'Sujet' par défaut.
  String? _selectedInterestNameOverride;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(feedProvider.notifier);
    final selection = ref.watch(feedFilterSelectionProvider);
    final hasSearch =
        selection.keyword != null && selection.keyword!.isNotEmpty;
    final feedItems =
        ref.watch(feedProvider).valueOrNull?.items ?? const <dynamic>[];
    final serverCounts = ref.watch(tabCountsProvider).valueOrNull;
    return FilterCollapsiblePanel(
      activeCount: selection.activeCount,
      chipsRow: _buildChipsRow(context, selection),
      collapsedContentBuilder: (filterTrigger) => FavoriteTopicTabs(
        items: feedItems.cast(),
        serverCounts: serverCounts,
        selectedTopicSlug: selection.topic,
        selectedThemeSlug: selection.theme,
        selectedEntitySlug: selection.entity,
        selectedSourceId: selection.sourceId,
        onTabTap: (kind, slug) async {
          // Sheet owns this override ; clear it so the chip label rebuilds
          // from the tapped tab's name on next layout.
          if (mounted) {
            setState(() => _selectedInterestNameOverride = null);
          }
          switch (kind) {
            case FavoriteTabKind.subjectTopic:
              await notifier.setTopic(slug);
              break;
            case FavoriteTabKind.subjectEntity:
              await notifier.setEntity(slug);
              break;
            case FavoriteTabKind.theme:
              await notifier.setTheme(slug);
              break;
            case FavoriteTabKind.source:
              await notifier.setSource(slug);
              break;
          }
          widget.onAfterChange?.call();
        },
        // Taper l'onglet actif vide toute la sélection (feed non filtré). On
        // remet aussi `setSource(null)` — oublié historiquement — pour bien
        // désélectionner un onglet source actif.
        onTapActiveTab: () async {
          await HapticFeedback.selectionClick();
          await notifier.setTopic(null);
          await notifier.setTheme(null);
          await notifier.setEntity(null);
          await notifier.setSource(null);
          widget.onAfterChange?.call();
        },
        // Le « + » des onglets épingle des sujets précis (custom topics) —
        // le filtrage par thème/source reste assuré par les chips ci-dessous.
        onAddFavorite: () {
          HapticFeedback.mediumImpact();
          showPinSubjectsSheet(context);
        },
        trailingFilterTrigger: filterTrigger,
      ),
      leadingTrigger: _SearchTrigger(
        active: hasSearch,
        keyword: selection.keyword,
        onTap: () {
          HapticFeedback.mediumImpact();
          SearchFilterSheet.show(
            context,
            currentKeyword: selection.keyword,
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

  Widget _buildChipsRow(BuildContext context, FeedFilterSelection selection) {
    final notifier = ref.read(feedProvider.notifier);

    if (selection.theme == null &&
        selection.topic == null &&
        selection.entity == null) {
      _selectedInterestNameOverride = null;
    }

    final allSources = ref.watch(userSourcesProvider).valueOrNull ?? [];
    final followedSources = allSources
        .where((s) => (s.isTrusted || s.isCustom) && !s.isMuted)
        .toList();
    final selectedSourceId = selection.sourceId;
    final selectedSource = selectedSourceId != null
        ? followedSources.where((s) => s.id == selectedSourceId).firstOrNull
        : null;

    final selectedInterestSlug =
        selection.topic ?? selection.theme ?? selection.entity;
    final selectedIsTheme = selection.theme != null;

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
            selectedSlug: selectedInterestSlug,
            selectedName: _selectedInterestNameOverride,
            selectedIsTheme: selectedIsTheme,
            discreet: true,
            onInterestChanged: (
              slug,
              name, {
              bool isTheme = false,
              bool isEntity = false,
            }) async {
              setState(() {
                _selectedInterestNameOverride = name;
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
/// (34 px tall, primary accent when active).
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
          height: 34,
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
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  keyword ?? '',
                  style: TextStyle(
                    fontSize: 12.5,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 7,
                  ),
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
        height: 34,
        width: 34,
        child: Icon(
          PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
          // Loupe agrandie (16 → 22) : l'état inactif n'affiche que l'icône
          // (pas de placeholder), la boîte 34×34 l'accueille largement.
          size: 22,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
