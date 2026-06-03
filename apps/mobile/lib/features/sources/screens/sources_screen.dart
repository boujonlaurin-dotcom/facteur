import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../shared/widgets/fab_nudge_bubble.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../../../shared/widgets/states/laurin_fallback_view.dart';

import '../../my_interests/models/user_interests_state.dart' show InterestState;
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../my_interests/widgets/favorites_reorderable_section.dart';
import '../../my_interests/widgets/interest_state_picker_sheet.dart';
import '../../settings/providers/paid_content_provider.dart';
import '../models/source_model.dart';
import '../models/source_theme_filters.dart';
import '../providers/sources_providers.dart';
import '../widgets/pepites_carousel.dart';
import '../widgets/source_list_item.dart';

class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTheme;
  SourceType? _selectedType;
  bool _isSearching = false;
  // Collapsible section state (open by default)
  bool _premiumExpanded = true;
  bool _followedExpanded = true;
  bool _mutedExpanded = true;

  // Compteur d'échecs consécutifs : bascule entre FriendlyErrorView et
  // LaurinFallbackView après 2 échecs (pattern de feed_screen.dart).
  int _consecutiveErrorCount = 0;

  static const _typeFilters = <({SourceType? key, String label})>[
    (key: null, label: 'Tous'),
    (key: SourceType.article, label: 'Articles'),
    (key: SourceType.youtube, label: 'YouTube'),
    (key: SourceType.reddit, label: 'Reddit'),
    (key: SourceType.podcast, label: 'Podcasts'),
  ];

  bool get _hasActiveFilter => _selectedTheme != null || _selectedType != null;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _exitSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _pickSourceState(Source source) async {
    final state = ref.read(userSourcesStateProvider).value;
    final currentState = state?.stateOf(source.id) ?? InterestState.followed;

    final picked = await InterestStatePickerSheet.show(
      context,
      title: source.name,
      currentState: currentState,
    );
    if (picked == null || picked == currentState) return;

    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(source.id, picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de mettre à jour cette source.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);
    final sourcesStateAsync = ref.watch(userSourcesStateProvider);

    // Synchronise le compteur d'échecs consécutifs avec l'état du provider —
    // mêmes règles que feed_screen.dart : incrémente sur 1ère AsyncError,
    // reset sur succès. Évite de muter l'int dans le builder (warning Flutter).
    ref.listen(userSourcesProvider, (previous, next) {
      if (next is AsyncError && previous is! AsyncError) {
        if (mounted) setState(() => _consecutiveErrorCount++);
      } else if (next is AsyncData && _consecutiveErrorCount != 0) {
        if (mounted) setState(() => _consecutiveErrorCount = 0);
      }
    });

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular)),
                onPressed: _exitSearch,
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Rechercher une source...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colors.textTertiary),
                ),
                style: TextStyle(color: colors.textPrimary),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
              actions: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
              ],
            )
          : AppBar(
              title: const Text('Sources de confiance'),
              actions: [
                IconButton(
                  icon: Icon(
                    PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                  ),
                  onPressed: () => setState(() => _isSearching = true),
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        PhosphorIcons.funnel(PhosphorIconsStyle.regular),
                      ),
                      onPressed: () => _showFilterSheet(colors),
                    ),
                    if (_hasActiveFilter)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userSourcesProvider.future),
        color: colors.primary,
        child: sourcesAsync.when(
          loading: () => _scrollableCenter(
            const Center(child: CircularProgressIndicator()),
          ),
          error: (err, stack) => _scrollableCenter(
            _consecutiveErrorCount >= 2
                ? LaurinFallbackView(
                    onRetry: () {
                      setState(() => _consecutiveErrorCount = 0);
                      ref.invalidate(userSourcesProvider);
                    },
                  )
                : FriendlyErrorView(
                    error: err,
                    onRetry: () => ref.invalidate(userSourcesProvider),
                  ),
          ),
          data: (sources) {
            final sourcesState = sourcesStateAsync.value;

            var filteredSources = sources.toList();
            if (_searchQuery.isNotEmpty) {
              filteredSources = filteredSources
                  .where(
                    (s) => s.name.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ),
                  )
                  .toList();
            }
            if (_selectedTheme != null) {
              filteredSources = filteredSources
                  .where((s) => s.theme?.toLowerCase() == _selectedTheme)
                  .toList();
            }
            if (_selectedType != null) {
              filteredSources = filteredSources
                  .where((s) => s.type == _selectedType)
                  .toList();
            }
            filteredSources.sort(_compareByThemeThenName);

            if (sources.isEmpty && _searchQuery.isEmpty) {
              return _scrollableCenter(
                Text(
                  'Aucune source disponible',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                ),
              );
            }

            final followedNonMuted = filteredSources
                .where(
                  (s) => !s.isMuted && _isFollowedSource(s, sourcesState),
                )
                .map((s) => s.copyWith(isTrusted: true))
                .toList();

            final visibleFavoriteIds = followedNonMuted
                .where((s) => _isFavoriteSource(s, sourcesState))
                .map((s) => s.id)
                .toSet();
            final allFavorites = sourcesState?.favorites ?? const [];
            final visibleFavorites = allFavorites
                .where((f) => visibleFavoriteIds.contains(f.sourceId))
                .toList();
            final premiumSources = filteredSources
                .where(
                  (s) =>
                      !s.isMuted &&
                      s.hasSubscription &&
                      _isFollowedSource(s, sourcesState) &&
                      !_isFavoriteSource(s, sourcesState),
                )
                .map((s) => s.copyWith(isTrusted: true))
                .toList();
            final followedSources = followedNonMuted
                .where(
                  (s) =>
                      !s.hasSubscription && !_isFavoriteSource(s, sourcesState),
                )
                .toList();
            final mutedSources = filteredSources
                .where((s) => s.isMuted)
                .toList();

            final noFollowedSources =
                !sources.any((s) => !s.isMuted && _isFollowedSource(s, sourcesState));
            final noResults = followedNonMuted.isEmpty &&
                mutedSources.isEmpty &&
                (_hasActiveFilter || _searchQuery.isNotEmpty);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _IntroBlock(colors: colors),
                const SizedBox(height: 12),
                // Story 22.1 — section Favoris (drag-reorderable, cap 3).
                if (!noFollowedSources || visibleFavorites.isNotEmpty)
                  _SourceFavoritesSection(
                    favorites: visibleFavorites,
                    allSources: followedNonMuted,
                    onReorder: (reordered) async {
                      final messenger = ScaffoldMessenger.of(context);
                      final reorderedIds =
                          reordered.map((f) => f.sourceId).toSet();
                      var reorderedIndex = 0;
                      final mergedFavorites = [
                        for (final favorite in allFavorites)
                          if (reorderedIds.contains(favorite.sourceId))
                            reordered[reorderedIndex++]
                          else
                            favorite,
                      ];
                      try {
                        await ref
                            .read(userSourcesStateProvider.notifier)
                            .reorderFavorites(mergedFavorites);
                      } catch (_) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Impossible de réordonner les favoris.',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 8),
                if (premiumSources.isNotEmpty)
                  _buildCollapsibleSection(
                    title: 'Abonnements premium',
                    count: premiumSources.length,
                    isExpanded: _premiumExpanded,
                    onToggle: () =>
                        setState(() => _premiumExpanded = !_premiumExpanded),
                    sources: premiumSources,
                    colors: colors,
                    sourcesState: sourcesState,
                    icon: PhosphorIcons.star(PhosphorIconsStyle.fill),
                  ),
                const _HidePaidToggleCard(),
                const SizedBox(height: 8),
                if (noResults)
                  _NoSourcesMatchBlock(
                    hasActiveFilter: _hasActiveFilter,
                    hasSearchQuery: _searchQuery.isNotEmpty,
                    onReset: () {
                      setState(() {
                        _selectedTheme = null;
                        _selectedType = null;
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                else if (noFollowedSources)
                  const _NoFollowedSourcesBlock()
                else if (followedSources.isNotEmpty)
                  _buildCollapsibleSection(
                    title: 'Sources suivies',
                    count: followedSources.length,
                    isExpanded: _followedExpanded,
                    onToggle: () =>
                        setState(() => _followedExpanded = !_followedExpanded),
                    sources: followedSources,
                    colors: colors,
                    sourcesState: sourcesState,
                  ),
                const SizedBox(height: 8),
                const PepitesCarousel(alwaysVisible: true),
                if (mutedSources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCollapsibleSection(
                    title: 'Sources masquées',
                    count: mutedSources.length,
                    isExpanded: _mutedExpanded,
                    onToggle: () =>
                        setState(() => _mutedExpanded = !_mutedExpanded),
                    sources: mutedSources,
                    colors: colors,
                    sourcesState: sourcesState,
                    icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.bold),
                    isMuted: true,
                  ),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Flexible(
            child: FabNudgeBubble(
              text: 'Ajoute média, newsletter, vidéo…',
              dismissKey: 'nudge_add_source_v1',
            ),
          ),
          const SizedBox(width: 6),
          FloatingActionButton.extended(
            onPressed: () => context.pushNamed(RouteNames.addSource),
            icon: Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold)),
            label: const Text('Ajouter une source'),
            backgroundColor: colors.primary,
            foregroundColor: colors.surface,
          ),
        ],
      ),
    );
  }

  /// Wraps a non-scrollable child (loading, error, empty state) so it can
  /// participate in [RefreshIndicator] — pull-to-refresh requires a scrollable
  /// descendant with [AlwaysScrollableScrollPhysics].
  Widget _scrollableCenter(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  bool _isFollowedSource(Source source, UserSourcesState? state) {
    final sourceState = state?.stateOf(source.id);
    return source.isTrusted ||
        sourceState == InterestState.followed ||
        sourceState == InterestState.favorite;
  }

  bool _isFavoriteSource(Source source, UserSourcesState? state) {
    return state?.stateOf(source.id) == InterestState.favorite ||
        (state?.favorites.any((f) => f.sourceId == source.id) ?? false);
  }

  static int _compareByThemeThenName(Source a, Source b) {
    final themeCompare = a.getThemeLabel().compareTo(b.getThemeLabel());
    if (themeCompare != 0) return themeCompare;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  // ─── Filter bottom sheet ───────────────────────────────────

  void _showFilterSheet(FacteurColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilterSheetContent(
        selectedTheme: _selectedTheme,
        selectedType: _selectedType,
        themeFilters: sourceThemeFilters,
        typeFilters: _typeFilters,
        hasActiveFilter: _hasActiveFilter,
        onThemeChanged: (v) => setState(() => _selectedTheme = v),
        onTypeChanged: (v) => setState(() => _selectedType = v),
        onReset: () => setState(() {
          _selectedTheme = null;
          _selectedType = null;
        }),
      ),
    );
  }

  // ─── Collapsible section ─────────────────────────────────────

  Widget _buildCollapsibleSection({
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Source> sources,
    required FacteurColors colors,
    required UserSourcesState? sourcesState,
    IconData? icon,
    bool isMuted = false,
  }) {
    final titleColor = isMuted ? colors.textTertiary : colors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: titleColor),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                      size: 15,
                      color: titleColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: sources
                .map((source) => _buildSourceItem(source, sourcesState))
                .toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSourceItem(Source source, UserSourcesState? sourcesState) {
    final isFavorite =
        sourcesState?.favorites.any((f) => f.sourceId == source.id) ?? false;
    final displaySource = source.copyWith(
      isTrusted: source.isMuted
          ? source.isTrusted
          : _isFollowedSource(source, sourcesState),
    );
    return SourceListItem(
      source: displaySource,
      isFavorite: isFavorite,
      onPickInterestState: () => _pickSourceState(displaySource),
      onTap: () {
        ref
            .read(userSourcesProvider.notifier)
            .toggleTrust(displaySource.id, displaySource.isTrusted);
      },
      onToggleMute: () {
        ref
            .read(userSourcesProvider.notifier)
            .toggleMute(displaySource.id, displaySource.isMuted);
      },
    );
  }
}

/// Story 22.1 — bloc Favoris pour les sources.
class _SourceFavoritesSection extends StatelessWidget {
  final List<SourceFavoriteRef> favorites;
  final List<Source> allSources;
  final void Function(List<SourceFavoriteRef> reordered) onReorder;

  const _SourceFavoritesSection({
    required this.favorites,
    required this.allSources,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final byId = {for (final s in allSources) s.id: s};

    return FavoritesReorderableSection<SourceFavoriteRef>(
      items: favorites,
      keyOf: (r) => ValueKey('source:${r.sourceId}'),
      emptyStateText:
          'Aucune source favorite — marquez-en une pour l\'épingler dans Flâner.',
      padding: EdgeInsets.zero,
      itemBuilder: (context, refItem) {
        final source = byId[refItem.sourceId];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.star(PhosphorIconsStyle.fill),
                color: colors.primary,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source?.name ?? 'Source',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
      onReorder: onReorder,
    );
  }
}

class _NoFollowedSourcesBlock extends StatelessWidget {
  const _NoFollowedSourcesBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.plusCircle(PhosphorIconsStyle.regular),
            size: 24,
            color: colors.primary,
          ),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Text(
              'Aucune source suivie pour le moment. Ajoutez une source pour personnaliser votre veille.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSourcesMatchBlock extends StatelessWidget {
  final bool hasActiveFilter;
  final bool hasSearchQuery;
  final VoidCallback onReset;

  const _NoSourcesMatchBlock({
    required this.hasActiveFilter,
    required this.hasSearchQuery,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = hasSearchQuery
        ? 'Aucune source suivie ne correspond à cette recherche.'
        : 'Aucune source suivie pour ces filtres.';

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Column(
        children: [
          Icon(
            PhosphorIcons.funnel(PhosphorIconsStyle.regular),
            size: 34,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (hasActiveFilter || hasSearchQuery) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onReset, child: const Text('Réinitialiser')),
          ],
        ],
      ),
    );
  }
}

// ─── Filter sheet widget ─────────────────────────────────────

class _FilterSheetContent extends ConsumerWidget {
  final String? selectedTheme;
  final SourceType? selectedType;
  final List<({String? key, String label})> themeFilters;
  final List<({SourceType? key, String label})> typeFilters;
  final bool hasActiveFilter;
  final ValueChanged<String?> onThemeChanged;
  final ValueChanged<SourceType?> onTypeChanged;
  final VoidCallback onReset;

  const _FilterSheetContent({
    required this.selectedTheme,
    required this.selectedType,
    required this.themeFilters,
    required this.typeFilters,
    required this.hasActiveFilter,
    required this.onThemeChanged,
    required this.onTypeChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Filtres',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  if (hasActiveFilter)
                    TextButton(
                      onPressed: () {
                        onReset();
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Réinitialiser',
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Theme section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'THÈME',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: themeFilters.map((f) {
                  final isSelected = selectedTheme == f.key;
                  return ChoiceChip(
                    label: Text(f.label),
                    selected: isSelected,
                    onSelected: (_) {
                      onThemeChanged(f.key);
                      Navigator.pop(context);
                    },
                    selectedColor: colors.primary,
                    backgroundColor: colors.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : colors.textSecondary,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? colors.primary : colors.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Type section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TYPE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: typeFilters.map((f) {
                  final isSelected = selectedType == f.key;
                  return ChoiceChip(
                    label: Text(f.label),
                    selected: isSelected,
                    onSelected: (_) {
                      onTypeChanged(f.key);
                      Navigator.pop(context);
                    },
                    selectedColor: colors.primary,
                    backgroundColor: colors.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : colors.textSecondary,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? colors.primary : colors.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Intro block ─────────────────────────────────────────────

class _IntroBlock extends StatelessWidget {
  final FacteurColors colors;
  const _IntroBlock({required this.colors});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vos sources de confiance',
            style: FacteurTypography.serifTitle(
              colors.textPrimary,
            ).copyWith(fontSize: 20, height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            'Gérez vos préférences par sources. Ajoutez certaines en favoris pour les voir apparaitre plus souvent. Masquez celles que vous souhaitez filtrer de vos flux.',
            style: textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hide paid toggle card ──────────────────────────────────

class _HidePaidToggleCard extends ConsumerWidget {
  const _HidePaidToggleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final hidePaid = ref.watch(hidePaidContentProvider);
    final borderRadius = BorderRadius.circular(FacteurRadius.large);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: colors.surface,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: () =>
              ref.read(hidePaidContentProvider.notifier).toggle(!hidePaid),
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
                    color: colors.primary.withValues(alpha: 0.10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PhosphorIcons.lock(PhosphorIconsStyle.regular),
                    color: colors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Masquer les articles payants*',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '*: Sauf abonnements connectés.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: hidePaid,
                  activeThumbColor: colors.primary,
                  onChanged: (v) =>
                      ref.read(hidePaidContentProvider.notifier).toggle(v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
