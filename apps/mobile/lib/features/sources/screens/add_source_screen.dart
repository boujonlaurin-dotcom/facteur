import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/ui/notification_service.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../widgets/community_gems_strip.dart';
import '../widgets/example_chips.dart';
import '../widgets/smart_search_field.dart';
import '../widgets/source_detail_modal.dart';
import '../widgets/source_result_card.dart';
import '../widgets/source_result_skeleton.dart';

class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  String _currentQuery = '';
  String? _selectedContentType;
  String? _selectedLabel;
  bool _expanded = false;
  bool _sourceAdded = false;
  final Set<String> _addedSourceIds = {};
  String? _lastAddedName;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  bool _searchActive = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(_handleSearchActivity);
    _searchController.addListener(_handleSearchActivity);
  }

  @override
  void dispose() {
    final query = _currentQuery.trim();
    if (query.isNotEmpty && !_sourceAdded) {
      ref.read(sourcesRepositoryProvider).logSearchAbandoned(query);
    }
    _searchFocusNode.removeListener(_handleSearchActivity);
    _searchController.removeListener(_handleSearchActivity);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchActivity() {
    final active =
        _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
    if (active != _searchActive) {
      setState(() => _searchActive = active);
    }
  }

  SmartSearchQuery get _searchParams => (
        query: _currentQuery,
        contentType: _selectedContentType,
        expand: _expanded,
      );

  // ─── Smart Search Actions ──────────────────────────────────────

  void _runSearch([String? query]) {
    final value = (query ?? _searchController.text).trim();
    if (value.isEmpty) return;
    if (_searchController.text != value) {
      _searchController.text = value;
    }
    setState(() {
      _currentQuery = value;
      _expanded = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _currentQuery = '';
      _expanded = false;
    });
  }

  void _onContentTypeToggle(String? value) {
    setState(() {
      _selectedContentType = value;
      _expanded = false;
    });
    if (value != null) {
      ref
          .read(analyticsServiceProvider)
          .trackAddSourceContentTypeFilter(value);
    }
  }

  void _expandSearch() {
    setState(() => _expanded = true);
    ref.read(analyticsServiceProvider).trackAddSourceExpand(_currentQuery);
  }

  Future<void> _addSource(SmartSearchResult result) async {
    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final sourceId = result.sourceId;
      final hasCatalogId =
          sourceId != null && sourceId.isNotEmpty && sourceId != 'null';

      if (hasCatalogId) {
        await repository.trustSource(sourceId);
        setState(() {
          _addedSourceIds.add(sourceId);
          _sourceAdded = true;
          _lastAddedName = result.name;
        });
      } else {
        if (result.feedUrl.isEmpty) {
          NotificationService.showError('URL du flux introuvable');
          return;
        }
        await repository.addCustomSource(result.feedUrl, name: result.name);
        setState(() {
          _sourceAdded = true;
          _lastAddedName = result.name;
        });
      }

      if (!mounted) return;
      ref.invalidate(userSourcesProvider);

      if (hasCatalogId) {
        // Default new sources to max priority (3/3) — user explicitly opted-in.
        await repository.updateSourceWeight(sourceId, 2.0);
        if (!mounted) return;

        // Open modal so user can fine-tune subscription + priority right away.
        final source = Source(
          id: sourceId,
          name: result.name,
          url: result.url,
          type: _parseSourceType(result.type),
          description: result.description,
          logoUrl: result.faviconUrl,
          isCurated: result.isCurated,
          isTrusted: true,
          priorityMultiplier: 2.0,
        );
        await _showSourceModal(source, recentItems: result.recentItems);
        if (!mounted) return;
        _resetForNextAdd();
      } else {
        NotificationService.showSuccess(
            'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
        _resetForNextAdd();
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError('Erreur lors de l\'ajout : $e');
      }
    }
  }

  void _previewSource(SmartSearchResult result) {
    final source = Source(
      id: result.sourceId ?? '',
      name: result.name,
      url: result.url,
      type: _parseSourceType(result.type),
      description: result.description,
      logoUrl: result.faviconUrl,
      isCurated: result.isCurated,
    );
    _showSourceModal(source, recentItems: result.recentItems);
  }

  SourceType _parseSourceType(String type) {
    switch (type) {
      case 'youtube':
        return SourceType.youtube;
      case 'reddit':
        return SourceType.reddit;
      case 'podcast':
        return SourceType.podcast;
      case 'video':
        return SourceType.video;
      default:
        return SourceType.article;
    }
  }

  Future<void> _toggleTrustSource(Source source) async {
    try {
      final repository = ref.read(sourcesRepositoryProvider);
      if (source.isTrusted) {
        await repository.untrustSource(source.id);
      } else {
        await repository.trustSource(source.id);
        if (mounted) {
          NotificationService.showSuccess(
              'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
        }
      }
      ref.invalidate(trendingSourcesProvider);
      ref.invalidate(userSourcesProvider);
    } catch (e) {
      if (mounted) NotificationService.showError('Erreur : $e');
    }
  }

  void _resetForNextAdd() {
    _searchController.clear();
    setState(() {
      _currentQuery = '';
      _expanded = false;
    });
  }

  Future<void> _showSourceModal(
    Source source, {
    List<SmartSearchRecentItem>? recentItems,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceDetailModal(
        source: source,
        recentItems: recentItems,
        onToggleTrust: () => _toggleTrustSource(source),
        onPriorityChanged: source.id.isNotEmpty
            ? (multiplier) {
                ref
                    .read(userSourcesProvider.notifier)
                    .updateWeight(source.id, multiplier);
              }
            : null,
        onToggleSubscription: source.id.isNotEmpty
            ? () {
                final current = ref
                        .read(userSourcesProvider)
                        .valueOrNull
                        ?.firstWhere(
                          (s) => s.id == source.id,
                          orElse: () => source,
                        )
                        .hasSubscription ??
                    source.hasSubscription;
                ref
                    .read(userSourcesProvider.notifier)
                    .toggleSubscription(source.id, current);
              }
            : null,
        onCopyFeedUrl: source.isCustom && (source.url?.isNotEmpty ?? false)
            ? () async {
                await Clipboard.setData(ClipboardData(text: source.url!));
                if (mounted) {
                  NotificationService.showSuccess(
                      'URL du flux copiee dans le presse-papiers !');
                }
              }
            : null,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
          onPressed: () => context.pop(),
        ),
        title: const Text('Ajouter une source'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space2,
          FacteurSpacing.space4,
          FacteurSpacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentQuery.isEmpty) ...[
              const SizedBox(height: FacteurSpacing.space6),
              _buildSearchIntro(),
              const SizedBox(height: FacteurSpacing.space6),
            ],
            _buildBreathingSearch(colors),
            SizedBox(
                height: _currentQuery.isEmpty
                    ? FacteurSpacing.space8
                    : FacteurSpacing.space4),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreathingSearch(FacteurColors colors) {
    final glow = _searchActive ? colors.primary.withValues(alpha: 0.18) : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: [
          BoxShadow(
            color: glow,
            blurRadius: _searchActive ? 28 : 0,
            spreadRadius: _searchActive ? 2 : 0,
          ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: _searchActive ? 1.01 : 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: SmartSearchField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onSubmit: (value) => _runSearch(value),
          onClear: _clearSearch,
          onSearch: () => _runSearch(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_currentQuery.isEmpty) {
      return _buildEmptyState();
    }

    final searchAsync = ref.watch(smartSearchProvider(_searchParams));
    final followedIds = ref
            .watch(userSourcesProvider)
            .valueOrNull
            ?.where((s) => s.isTrusted)
            .map((s) => s.id)
            .toSet() ??
        const <String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterChips(),
        const SizedBox(height: 12),
        searchAsync.when(
          loading: () => const SourceResultSkeleton(),
          error: (error, _) => _buildErrorState(),
          data: (response) {
            if (response.results.isEmpty) return _buildNoResults();
            final canExpand = !_expanded &&
                response.layersCalled.length == 1 &&
                response.layersCalled.first == 'catalog';
            return _buildResults(
              response.results,
              canExpand: canExpand,
              followedIds: followedIds,
            );
          },
        ),
      ],
    );
  }

  void _onExampleTap(String text) {
    _searchController.text = text;
    setState(() => _currentQuery = text);
    ref.read(analyticsServiceProvider).trackAddSourceExampleTap(text);
  }

  Widget _buildEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sourceAdded) ...[
          _buildAddedNudge(),
          const SizedBox(height: FacteurSpacing.space6),
        ],
        ExampleChips(onTap: _onExampleTap),
        const SizedBox(height: FacteurSpacing.space8),
        CommunityGemsStrip(
          onSourceTap: _showSourceModal,
          onGemTap: (sourceId) {
            ref.read(analyticsServiceProvider).trackAddSourceGemTap(sourceId);
          },
        ),
      ],
    );
  }

  Widget _buildAddedNudge() {
    final colors = context.facteurColors;
    final name = _lastAddedName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        onTap: () {
          setState(() {
            _sourceAdded = false;
            _lastAddedName = null;
          });
          _searchFocusNode.requestFocus();
        },
        child: Container(
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                  size: 22, color: colors.primary),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name != null
                          ? '« $name » ajoutée'
                          : 'Source ajoutée',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Une autre à ajouter ?',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                  size: 18, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchIntro() {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Que veux-tu suivre ?',
          textAlign: TextAlign.center,
          style: FacteurTypography.serifTitle(colors.textPrimary)
              .copyWith(fontSize: 28, height: 1.15),
        ),
        const SizedBox(height: FacteurSpacing.space2),
        Text(
          'Tape un nom de média ou colle son URL.\nOn l\'amène dans ton app.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
        ),
        const SizedBox(height: FacteurSpacing.space4),
        _buildSupportedTypesInfo(colors),
      ],
    );
  }

  Widget _buildSupportedTypesInfo(FacteurColors colors) {
    const items = <({String label, int iconIndex})>[
      (label: 'Médias', iconIndex: 0),
      (label: 'Newsletters', iconIndex: 1),
      (label: 'YouTube', iconIndex: 2),
      (label: 'Reddit', iconIndex: 3),
      (label: 'Podcasts', iconIndex: 4),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: items.map((it) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForContentType(it.iconIndex),
              size: 13,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              it.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                  ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildResults(
    List<SmartSearchResult> results, {
    bool canExpand = false,
    Set<String> followedIds = const <String>{},
  }) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${results.length} resultat${results.length > 1 ? 's' : ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...results.map((result) {
          final id = result.sourceId;
          final isAdded = _addedSourceIds.contains(id) ||
              (id != null && followedIds.contains(id));
          return SourceResultCard(
            result: result,
            isAdded: isAdded,
            onAdd: () => _addSource(result),
            onPreview: () => _previewSource(result),
          );
        }),
        if (canExpand) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _expandSearch,
            icon: Icon(
              PhosphorIcons.arrowsOutSimple(PhosphorIconsStyle.regular),
              size: 16,
              color: colors.primary,
            ),
            label: const Text('Élargir la recherche'),
          ),
          const SizedBox(height: 4),
          Text(
            'Cherche aussi sur YouTube, Reddit et le web.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildNoResults() {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                size: 48, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Aucun resultat pour "$_currentQuery"',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Essayez avec une URL directe ou d\'autres mots-cles.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(PhosphorIcons.warning(PhosphorIconsStyle.regular),
                size: 48, color: colors.error),
            const SizedBox(height: 16),
            Text(
              'Impossible de rechercher pour le moment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(smartSearchProvider(_searchParams)),
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared Widgets ────────────────────────────────────────────

  static const _contentTypeOptions =
      <({String label, String apiValue, int iconIndex})>[
    (label: 'Médias', apiValue: 'article', iconIndex: 0),
    (label: 'Newsletters', apiValue: 'article', iconIndex: 1),
    (label: 'YouTube', apiValue: 'youtube', iconIndex: 2),
    (label: 'Reddit', apiValue: 'reddit', iconIndex: 3),
    (label: 'Podcasts', apiValue: 'podcast', iconIndex: 4),
  ];

  IconData _iconForContentType(int idx) {
    switch (idx) {
      case 0:
        return PhosphorIcons.newspaper(PhosphorIconsStyle.fill);
      case 1:
        return PhosphorIcons.envelope(PhosphorIconsStyle.fill);
      case 2:
        return PhosphorIcons.youtubeLogo(PhosphorIconsStyle.fill);
      case 3:
        return PhosphorIcons.redditLogo(PhosphorIconsStyle.fill);
      case 4:
        return PhosphorIcons.microphone(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.newspaper(PhosphorIconsStyle.fill);
    }
  }

  Widget _buildFilterChips() {
    final colors = context.facteurColors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _contentTypeOptions.map((t) {
        // "Médias" et "Newsletters" mappent tous les deux sur `article` —
        // on différencie par `_selectedLabel` pour éviter la confusion.
        final isSelected =
            _selectedContentType == t.apiValue && _selectedLabel == t.label;
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForContentType(t.iconIndex),
                size: 14,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(t.label),
            ],
          ),
          selected: isSelected,
          onSelected: (selected) {
            setState(() => _selectedLabel = selected ? t.label : null);
            _onContentTypeToggle(selected ? t.apiValue : null);
          },
        );
      }).toList(),
    );
  }

}
