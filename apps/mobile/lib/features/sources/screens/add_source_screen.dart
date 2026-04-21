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
import '../widgets/theme_explorer.dart';

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
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    final query = _currentQuery.trim();
    if (query.isNotEmpty && !_sourceAdded) {
      ref.read(sourcesRepositoryProvider).logSearchAbandoned(query);
    }
    _searchController.dispose();
    super.dispose();
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
        });
      } else {
        if (result.feedUrl.isEmpty) {
          NotificationService.showError('URL du flux introuvable');
          return;
        }
        await repository.addCustomSource(result.feedUrl, name: result.name);
        setState(() => _sourceAdded = true);
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
        _showSourceModal(source, recentItems: result.recentItems);
      } else {
        NotificationService.showSuccess(
            'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
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

  void _showSourceModal(
    Source source, {
    List<SmartSearchRecentItem>? recentItems,
  }) {
    showModalBottomSheet<void>(
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
        title: Text(
          'Ajouter une source',
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SmartSearchField(
              controller: _searchController,
              onSubmit: (value) => _runSearch(value),
              onClear: _clearSearch,
              onSearch: () => _runSearch(),
            ),
            const SizedBox(height: 16),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_currentQuery.isEmpty) {
      return _buildEmptyState();
    }

    final searchAsync = ref.watch(smartSearchProvider(_searchParams));

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
            return _buildResults(response.results, canExpand: canExpand);
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

  Widget _buildEmptyState() => _buildUrlRssEmptyState();

  Widget _buildUrlRssEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSourceTypesRow(),
        const SizedBox(height: 20),
        ExampleChips(onTap: _onExampleTap),
        const SizedBox(height: 24),
        const ThemeExplorer(),
        const SizedBox(height: 24),
        CommunityGemsStrip(
          onSourceTap: _showSourceModal,
          onGemTap: (sourceId) {
            ref.read(analyticsServiceProvider).trackAddSourceGemTap(sourceId);
          },
        ),
        const SizedBox(height: 24),
        _buildInspirationHints(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildResults(
    List<SmartSearchResult> results, {
    bool canExpand = false,
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
        ...results.map((result) => SourceResultCard(
              result: result,
              isAdded: _addedSourceIds.contains(result.sourceId),
              onAdd: () => _addSource(result),
              onPreview: () => _previewSource(result),
            )),
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

  Widget _buildHelpCard({
    required String title,
    String? description,
  }) {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.lightbulb(PhosphorIconsStyle.regular),
                  size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ],
        ],
      ),
    );
  }

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

  Widget _buildSourceTypesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ajoutez n\'importe quelle source à Facteur !',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: context.facteurColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 10),
        _buildFilterChips(),
      ],
    );
  }

  Widget _buildInspirationHints() {
    final colors = context.facteurColors;
    const hints = <String>[
      'Une newsletter qui s\'accumule dans la boîte mail',
      'Une chaîne YouTube recommandée par un proche',
      'Un compte Instagram ou LinkedIn d\'expert',
      'Un subreddit qui revient souvent dans les conversations',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.lightbulb(PhosphorIconsStyle.fill),
                  size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quelques conseils',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...hints.map((hint) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hint,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.4,
                                ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSourceListTile(Source source) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: source.logoUrl != null
            ? Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(source.logoUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                    PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                    color: colors.primary),
              ),
        title: Text(source.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                source.description?.isNotEmpty == true
                    ? source.description!
                    : source.getThemeLabel(),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (source.followerCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(PhosphorIcons.users(PhosphorIconsStyle.regular),
                      size: 11, color: colors.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    '${source.followerCount} ${source.followerCount == 1 ? 'lecteur' : 'lecteurs'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: source.isTrusted
            ? Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                color: colors.success)
            : Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
                color: colors.textTertiary),
        onTap: () => _showSourceModal(source),
      ),
    );
  }
}
