import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final Set<String> _addedSourceIds = {};

  // ─── Smart Search Actions ──────────────────────────────────────

  Future<void> _addSource(SmartSearchResult result) async {
    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final sourceId = result.sourceId;

      if (sourceId != null && sourceId.isNotEmpty && sourceId != 'null') {
        await repository.trustSource(sourceId);
        setState(() => _addedSourceIds.add(sourceId));
      } else {
        if (result.feedUrl.isEmpty) {
          NotificationService.showError('URL du flux introuvable');
          return;
        }
        await repository.addCustomSource(result.feedUrl, name: result.name);
      }

      if (mounted) {
        NotificationService.showSuccess(
            'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
        ref.invalidate(userSourcesProvider);
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
    _showSourceModal(source);
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

  void _openAtlasFlux() async {
    final Uri url = Uri.parse('https://atlasflux.saynete.net/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        NotificationService.showError('Impossible d\'ouvrir AtlasFlux');
      }
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

  void _showSourceModal(Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceDetailModal(
        source: source,
        onToggleTrust: () => _toggleTrustSource(source),
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
              onSearch: (query) => setState(() => _currentQuery = query),
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

    final searchAsync = ref.watch(smartSearchProvider(_currentQuery));

    return searchAsync.when(
      loading: () => const SourceResultSkeleton(),
      error: (error, _) => _buildErrorState(),
      data: (results) {
        if (results.isEmpty) return _buildNoResults();
        return _buildResults(results);
      },
    );
  }

  void _onExampleTap(String text) {
    setState(() => _currentQuery = text);
    ref.read(analyticsServiceProvider).trackAddSourceExampleTap(text);
  }

  Widget _buildEmptyState() => _buildUrlRssEmptyState();

  Widget _buildUrlRssEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        _buildAtlasFluxCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildResults(List<SmartSearchResult> results) {
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
                  ref.invalidate(smartSearchProvider(_currentQuery)),
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

  Widget _buildAtlasFluxCard() {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(PhosphorIcons.books(PhosphorIconsStyle.light),
              size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            'Toujours en manque d\'inspiration ?',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Plongez dans la bibliotheque francophone AtlasFlux.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openAtlasFlux,
            icon: Icon(
                PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular),
                size: 18,
                color: colors.primary),
            label: Text('Explorer AtlasFlux',
                style: TextStyle(color: colors.primary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          )
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
