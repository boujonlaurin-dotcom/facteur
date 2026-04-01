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
  bool _isSearching = false;
  // Collapsible section state (open by default)
  bool _premiumExpanded = true;
  bool _customExpanded = true;
  bool _curatedExpanded = true;
  bool _mutedExpanded = true;

  static const _themeFilters = <({String? key, String label})>[
    (key: null, label: 'Toutes'),
    (key: 'tech', label: 'Tech'),
    (key: 'society', label: 'Société'),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: Icon(
                    PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular)),
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
                    icon: Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.regular)),
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
                  icon: Icon(PhosphorIcons.magnifyingGlass(
                      PhosphorIconsStyle.regular)),
                  onPressed: () => setState(() => _isSearching = true),
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(PhosphorIcons.funnel(
                          PhosphorIconsStyle.regular)),
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

          final noResults = filteredSources.isEmpty && _hasActiveFilter;

          if (noResults) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.funnel(PhosphorIconsStyle.regular),
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
                    child: const Text('Réinitialiser les filtres'),
                  ),
                  ...mutedSources
                      .map((source) => _buildSourceItem(source)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  icon: PhosphorIcons.star(PhosphorIconsStyle.fill),
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
                  icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.bold),
                  isMuted: true,
                ),
              ],
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

  // ─── Filter bottom sheet ───────────────────────────────────

  void _showFilterSheet(FacteurColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilterSheetContent(
        selectedTheme: _selectedTheme,
        selectedType: _selectedType,
        themeFilters: _themeFilters,
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
    final hidePaid = ref.watch(hidePaidContentProvider);
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

            // Paid content toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colors.textPrimary,
                                ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: Switch.adaptive(
                        value: hidePaid,
                        onChanged: (value) {
                          ref
                              .read(hidePaidContentProvider.notifier)
                              .toggle(value);
                        },
                        activeTrackColor: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

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
