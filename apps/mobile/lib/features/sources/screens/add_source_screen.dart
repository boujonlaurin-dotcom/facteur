import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../core/ui/notification_service.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../widgets/source_preview_card.dart';

/// Écran d'ajout de source
class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _previewData;
  List<Source>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _detectOrSearchSource() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    _resetResults();

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final data = await repository.detectSource(query);

      setState(() {
        if (data.containsKey('results')) {
          // C'est une recherche par mots clés
          final resultsList = data['results'] as List<dynamic>;
          _searchResults = resultsList
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        } else {
          // C'est une URL valide détectée
          _previewData = data;
        }
      });
    } catch (e) {
      NotificationService.showError(
          'Impossible de trouver une source avec cette recherche');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmSourceFromPreview() async {
    if (_previewData == null) return;

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final sourceId = _previewData!['source_id'] as String?;

      if (sourceId != null && sourceId.isNotEmpty && sourceId != 'fallback') {
        // Known source in DB, just associate it
        await repository.trustSource(sourceId);
      } else {
        // Unknown source, add it
        final feedUrl = _previewData!['feed_url'] as String?;
        if (feedUrl == null || feedUrl.isEmpty) {
          NotificationService.showError('URL du flux introuvable');
          return;
        }
        await repository.addCustomSource(feedUrl,
            name: _previewData!['name'] as String?);
      }

      if (mounted) {
        NotificationService.showSuccess(
            'Source ajoutée ! Ses articles apparaîtront dans ton feed.');
        ref.invalidate(userSourcesProvider);
        context.pop();
      }
    } catch (e) {
      if (mounted)
        NotificationService.showError('Erreur lors de l\'ajout : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmSourceFromSearchResult(Source source) async {
    // Build preview locally from the Source object (avoids redundant detect call)
    setState(() {
      _previewData = {
        'source_id': source.id,
        'name': source.name,
        'description': source.description,
        'logo_url': source.logoUrl,
        'detected_type': source.type.name,
        'theme': source.theme,
        'feed_url': source.url,
        'preview': null,
      };
      _searchResults = null;
    });
  }

  void _resetResults() {
    setState(() {
      _previewData = null;
      _searchResults = null;
    });
  }

  void _resetAll() {
    _resetResults();
    _searchController.clear();
  }

  void _openAtlasFlux() async {
    final Uri url = Uri.parse('https://atlasflux.saynete.net/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        NotificationService.showError('Impossible d\'ouvrir AtlasFlux');
      }
    }
  }

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
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher ou coller une URL...',
                prefixIcon: Icon(
                  PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                ),
                suffixIcon: IconButton(
                  icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.fill)),
                  onPressed: _resetAll,
                ),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !_isLoading,
              style: Theme.of(context).textTheme.bodyMedium,
              onSubmitted: (_) => _detectOrSearchSource(),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_previewData != null)
              SourcePreviewCard(
                data: _previewData!,
                onConfirm: _confirmSourceFromPreview,
                onCancel: _resetAll,
                isLoading: _isLoading,
              )
            else if (_searchResults != null)
              _buildSearchResults()
            else
              _buildEmptyState(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final colors = context.facteurColors;

    if (_searchResults!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                  size: 48, color: colors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'Aucun résultat trouvé',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Résultats de la recherche',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        ..._searchResults!.map((source) => _buildSourceListTile(source)),
      ],
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
                child: Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                    color: colors.primary),
              ),
        title: Text(source.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(source.theme ?? 'Général',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.primary)),
        trailing: source.isTrusted
            ? Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                color: colors.success)
            : IconButton(
                icon: Icon(PhosphorIcons.plusCircle(PhosphorIconsStyle.fill),
                    color: colors.primary),
                onPressed: () => _confirmSourceFromSearchResult(source),
              ),
      ),
    );
  }

  Widget _buildBulletPoint(BuildContext context, String text) {
    final colors = context.facteurColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.primary)),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final colors = context.facteurColors;
    final trendingAsyncValue = ref.watch(trendingSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 En manque d\'idées ? Ajoute par exemple :',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                ),
                const SizedBox(height: 12),
                _buildBulletPoint(
                    context, 'Le nom de ton blog ou newsletter préférée'),
                const SizedBox(height: 8),
                _buildBulletPoint(context,
                    'Le lien direct vers un site de niche (ex: heidi.news)'),
                const SizedBox(height: 8),
                _buildBulletPoint(
                    context, 'Le lien d\'un profil Substack connu'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Rechercher',
          onPressed: _detectOrSearchSource,
          isLoading: false,
        ),
        const SizedBox(height: 40),
        Text(
          'Pépites de la communauté',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        trendingAsyncValue.when(
          data: (sources) {
            if (sources.isEmpty) {
              return Text(
                'Aucune pépite pour le moment.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textTertiary),
              );
            }
            return Column(
              children: sources.map((s) => _buildSourceListTile(s)).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            'Impossible de charger les tendances.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.error),
          ),
        ),
        const SizedBox(height: 40),
        Container(
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
                'Plongez dans la bibliothèque francophone AtlasFlux.',
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
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
