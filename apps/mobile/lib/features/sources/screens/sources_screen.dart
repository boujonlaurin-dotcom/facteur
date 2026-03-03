import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

import '../models/source_model.dart';
import '../providers/sources_providers.dart';
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

  static const _themeFilters = <({String? key, String label})>[
    (key: null, label: 'Toutes'),
    (key: 'tech', label: 'Tech'),
    (key: 'society', label: 'Societe'),
    (key: 'environment', label: 'Environnement'),
    (key: 'economy', label: 'Economie'),
    (key: 'politics', label: 'Politique'),
    (key: 'culture', label: 'Culture'),
    (key: 'science', label: 'Sciences'),
    (key: 'international', label: 'International'),
  ];

  static const _typeFilters = <({SourceType? key, String label})>[
    (key: null, label: 'Tous'),
    (key: SourceType.article, label: 'Articles'),
    (key: SourceType.youtube, label: 'YouTube'),
    (key: SourceType.reddit, label: 'Reddit'),
    (key: SourceType.podcast, label: 'Podcasts'),
  ];

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

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources de confiance'),
        actions: const [],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Erreur: $err')),
        data: (sources) {
          // Sort alphabetically
          var allSources = sources.toList()
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          // Apply search filter
          if (_searchQuery.isNotEmpty) {
            allSources = allSources
                .where((s) =>
                    s.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();
          }

          if (allSources.isEmpty && _searchQuery.isEmpty) {
            return Center(
              child: Text(
                'Aucune source disponible',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            );
          }

          // Apply theme + type filters for display
          var filteredSources = allSources.toList();
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

          // Split into 3 groups: custom (non-muted), curated (non-muted), muted
          final customSources = filteredSources
              .where((s) => s.isCustom && !s.isMuted)
              .toList();
          final curatedSources = filteredSources
              .where((s) => s.isCurated && !s.isMuted)
              .toList();
          final mutedSources =
              filteredSources.where((s) => s.isMuted).toList();

          final hasActiveFilter =
              _selectedTheme != null || _selectedType != null;
          final noResults = filteredSources.isEmpty && hasActiveFilter;

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une source...',
                    prefixIcon:
                        Icon(Icons.search, color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                      vertical: FacteurSpacing.space3,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    hintStyle: TextStyle(color: colors.textSecondary),
                  ),
                  style: TextStyle(color: colors.textPrimary),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),

              // Theme filter chips
              _buildThemeFilterRow(allSources, colors),
              const SizedBox(height: 4),
              // Type filter chips
              _buildTypeFilterRow(allSources, colors),
              const SizedBox(height: 8),

              Expanded(
                child: noResults
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.funnel(
                                  PhosphorIconsStyle.regular),
                              size: 40,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Aucune source pour ces filtres',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedTheme = null;
                                  _selectedType = null;
                                });
                              },
                              child: const Text('Reinitialiser les filtres'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (_searchQuery.isEmpty && !hasActiveFilter)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 24.0),
                              child: Text(
                                'Indiquez-nous vos sources de confiance !',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: colors.textSecondary,
                                      height: 1.5,
                                    ),
                              ),
                            ),
                          if (customSources.isNotEmpty) ...[
                            _buildSectionHeader(
                                'Mes sources personnalisees', colors),
                            ...customSources
                                .map((source) => _buildSourceItem(source)),
                            const SizedBox(height: 16),
                          ],
                          if (curatedSources.isNotEmpty) ...[
                            if (customSources.isNotEmpty)
                              _buildSectionHeader(
                                  'Sources suggerees', colors),
                            ...curatedSources
                                .map((source) => _buildSourceItem(source)),
                          ],
                          if (mutedSources.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                children: [
                                  Icon(
                                    PhosphorIcons.eyeSlash(
                                        PhosphorIconsStyle.bold),
                                    size: 16,
                                    color: colors.textTertiary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Sources masquees',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: colors.textTertiary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            ...mutedSources
                                .map((source) => _buildSourceItem(source)),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/settings/sources/add'),
        icon: Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold)),
        label: const Text('Ajouter une source'),
        backgroundColor: colors.primary,
        foregroundColor: colors.surface,
      ),
    );
  }

  Widget _buildSectionHeader(String title, FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildSourceItem(Source source) {
    return SourceListItem(
      source: source,
      onTap: () {
        ref
            .read(userSourcesProvider.notifier)
            .toggleTrust(source.id, source.isTrusted);
      },
      onToggleMute: () {
        ref
            .read(userSourcesProvider.notifier)
            .toggleMute(source.id, source.isMuted);
      },
    );
  }

  Widget _buildThemeFilterRow(List<Source> allSources, FacteurColors colors) {
    // Count sources per theme using sources filtered by type only (cross-filter)
    final typeFiltered = _selectedType != null
        ? allSources.where((s) => s.type == _selectedType).toList()
        : allSources;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _themeFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _themeFilters[index];
          final isSelected = _selectedTheme == filter.key;
          final count = filter.key == null
              ? typeFiltered.length
              : typeFiltered
                  .where((s) => s.theme?.toLowerCase() == filter.key)
                  .length;

          return _buildFilterChip(
            label: filter.label,
            count: count,
            isSelected: isSelected,
            onSelected: () {
              setState(
                  () => _selectedTheme = isSelected ? null : filter.key);
            },
            colors: colors,
          );
        },
      ),
    );
  }

  Widget _buildTypeFilterRow(List<Source> allSources, FacteurColors colors) {
    // Count sources per type using sources filtered by theme only (cross-filter)
    final themeFiltered = _selectedTheme != null
        ? allSources
            .where((s) => s.theme?.toLowerCase() == _selectedTheme)
            .toList()
        : allSources;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _typeFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _typeFilters[index];
          final isSelected = _selectedType == filter.key;
          final count = filter.key == null
              ? themeFiltered.length
              : themeFiltered.where((s) => s.type == filter.key).length;

          return _buildFilterChip(
            label: filter.label,
            count: count,
            isSelected: isSelected,
            onSelected: () {
              setState(
                  () => _selectedType = isSelected ? null : filter.key);
            },
            colors: colors,
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onSelected,
    required FacteurColors colors,
  }) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colors.primary
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? colors.surface : colors.textPrimary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.surface.withValues(alpha: 0.25)
                      : colors.textTertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color:
                        isSelected ? colors.surface : colors.textSecondary,
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
