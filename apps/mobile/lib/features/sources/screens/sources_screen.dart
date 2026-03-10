import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

import '../../settings/providers/paid_content_provider.dart';
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
  // Collapsible section state (open by default)
  bool _premiumExpanded = true;
  bool _customExpanded = true;
  bool _curatedExpanded = true;
  bool _mutedExpanded = true;

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

          // Apply theme + type + weight filters for display
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
          // Split into 4 groups: premium, custom (non-muted), curated (non-muted), muted
          final premiumSources = filteredSources
              .where((s) => s.hasSubscription && !s.isMuted)
              .toList();
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
              // Hide paid content toggle
              _buildPaidContentToggle(colors),

              // Theme dropdown
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDropdown<String?>(
                        value: _selectedTheme,
                        items: _themeFilters
                            .map((f) => DropdownMenuItem<String?>(
                                  value: f.key,
                                  child: Text(f.label),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedTheme = v),
                        hint: 'Theme',
                        icon: PhosphorIcons.tag(PhosphorIconsStyle.regular),
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown<SourceType?>(
                        value: _selectedType,
                        items: _typeFilters
                            .map((f) => DropdownMenuItem<SourceType?>(
                                  value: f.key,
                                  child: Text(f.label),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedType = v),
                        hint: 'Type',
                        icon: PhosphorIcons.funnel(
                            PhosphorIconsStyle.regular),
                        colors: colors,
                      ),
                    ),
                  ],
                ),
              ),

              // Search bar (below selectors)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                            ...mutedSources
                                .map((source) => _buildSourceItem(source)),
                          ],
                        ),
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (premiumSources.isNotEmpty)
                            _buildCollapsibleSection(
                              title: 'Mes abonnements Premium',
                              count: premiumSources.length,
                              isExpanded: _premiumExpanded,
                              onToggle: () => setState(
                                  () => _premiumExpanded = !_premiumExpanded),
                              sources: premiumSources,
                              colors: colors,
                              icon: PhosphorIcons.star(
                                  PhosphorIconsStyle.fill),
                            ),
                          if (customSources.isNotEmpty)
                            _buildCollapsibleSection(
                              title: 'Mes sources personnalisees',
                              count: customSources.length,
                              isExpanded: _customExpanded,
                              onToggle: () => setState(
                                  () => _customExpanded = !_customExpanded),
                              sources: customSources,
                              colors: colors,
                            ),
                          if (curatedSources.isNotEmpty)
                            _buildCollapsibleSection(
                              title: 'Sources suggerees',
                              count: curatedSources.length,
                              isExpanded: _curatedExpanded,
                              onToggle: () => setState(
                                  () => _curatedExpanded = !_curatedExpanded),
                              sources: curatedSources,
                              colors: colors,
                            ),
                          if (mutedSources.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildCollapsibleSection(
                              title: 'Sources masquees',
                              count: mutedSources.length,
                              isExpanded: _mutedExpanded,
                              onToggle: () => setState(
                                  () => _mutedExpanded = !_mutedExpanded),
                              sources: mutedSources,
                              colors: colors,
                              icon: PhosphorIcons.eyeSlash(
                                  PhosphorIconsStyle.bold),
                              isMuted: true,
                            ),
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

  // ─── Paid content toggle ─────────────────────────────────────

  Widget _buildPaidContentToggle(FacteurColors colors) {
    final hidePaid = ref.watch(hidePaidContentProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.lock(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Masquer les articles payants',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: hidePaid,
              onChanged: (value) {
                ref.read(hidePaidContentProvider.notifier).toggle(value);
              },
              activeTrackColor: colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dropdown selector ───────────────────────────────────────

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required String hint,
    required IconData icon,
    required FacteurColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          icon: Icon(
            PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
            size: 14,
            color: colors.textSecondary,
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
          dropdownColor: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
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
    IconData? icon,
    bool isMuted = false,
  }) {
    final titleColor = isMuted ? colors.textTertiary : colors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: titleColor),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: titleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: isExpanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                    size: 14,
                    color: titleColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: sources.map((source) => _buildSourceItem(source)).toList(),
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
      onWeightChanged: source.isTrusted && !source.isMuted
          ? (multiplier) {
              ref
                  .read(userSourcesProvider.notifier)
                  .updateWeight(source.id, multiplier);
            }
          : null,
      onToggleSubscription: () {
        ref
            .read(userSourcesProvider.notifier)
            .toggleSubscription(source.id, source.hasSubscription);
      },
    );
  }
}
