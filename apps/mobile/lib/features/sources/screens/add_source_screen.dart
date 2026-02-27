import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../core/ui/notification_service.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../widgets/source_detail_modal.dart';
import '../widgets/source_preview_card.dart';

class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  final _searchController = TextEditingController();
  int _currentTab = 0;
  bool _isLoading = false;
  Map<String, dynamic>? _previewData;
  List<Source>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Shared Logic ──────────────────────────────────────────────

  Future<void> _detectOrSearchSource() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    // Smart transform for Reddit tab
    String resolvedQuery = query;
    if (_currentTab == 2) {
      resolvedQuery = _transformRedditInput(query);
    }

    setState(() => _isLoading = true);
    _resetResults();

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final data = await repository.detectSource(resolvedQuery);

      setState(() {
        if (data.containsKey('results')) {
          final resultsList = data['results'] as List<dynamic>;
          _searchResults = resultsList
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        } else {
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

  String _transformRedditInput(String input) {
    final trimmed = input.trim();

    // Already a full URL
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    // reddit.com/r/... without protocol
    if (trimmed.startsWith('reddit.com/') ||
        trimmed.startsWith('www.reddit.com/') ||
        trimmed.startsWith('old.reddit.com/')) {
      return 'https://$trimmed';
    }

    // r/subreddit format
    final rSlashMatch = RegExp(r'^r/(\w+)$').firstMatch(trimmed);
    if (rSlashMatch != null) {
      return 'https://www.reddit.com/r/${rSlashMatch.group(1)}';
    }

    // Plain subreddit name
    if (RegExp(r'^\w+$').hasMatch(trimmed)) {
      return 'https://www.reddit.com/r/$trimmed';
    }

    return trimmed;
  }

  Future<void> _confirmSourceFromPreview() async {
    if (_previewData == null) return;

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final sourceId = _previewData!['source_id'] as String?;

      if (sourceId != null && sourceId.isNotEmpty && sourceId != 'fallback') {
        await repository.trustSource(sourceId);
      } else {
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
            'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
        ref.invalidate(userSourcesProvider);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError('Erreur lors de l\'ajout : $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
      if (mounted && _searchResults != null) {
        setState(() {
          _searchResults = _searchResults!
              .map((s) => s.id == source.id
                  ? s.copyWith(isTrusted: !source.isTrusted)
                  : s)
              .toList();
        });
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
            // SegmentedControl
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _currentTab,
                onValueChanged: (value) {
                  setState(() {
                    _currentTab = value!;
                    _resetAll();
                  });
                },
                backgroundColor: colors.surface,
                thumbColor: colors.backgroundPrimary,
                children: {
                  0: _buildSegment(
                    PhosphorIcons.globe(PhosphorIconsStyle.regular),
                    'URL / RSS',
                  ),
                  1: _buildSegment(
                    PhosphorIcons.youtubeLogo(PhosphorIconsStyle.regular),
                    'YouTube',
                  ),
                  2: _buildSegment(
                    PhosphorIcons.redditLogo(PhosphorIconsStyle.regular),
                    'Reddit',
                  ),
                },
              ),
            ),
            const SizedBox(height: 20),

            // Tab content
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _currentTab == 0
                  ? _buildUrlRssPage()
                  : _currentTab == 1
                      ? _buildYouTubePage()
                      : _buildRedditPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Tab 0: URL / RSS ──────────────────────────────────────────

  Widget _buildUrlRssPage() {
    return Column(
      key: const ValueKey('url_rss'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          hint: 'Rechercher ou coller une URL...',
          icon: PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          _buildLoadingIndicator()
        else if (_previewData != null)
          _buildPreviewCard()
        else if (_searchResults != null)
          _buildSearchResults()
        else
          _buildUrlRssEmptyState(),
      ],
    );
  }

  Widget _buildUrlRssEmptyState() {
    final colors = context.facteurColors;
    final trendingAsyncValue = ref.watch(trendingSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'Rechercher',
          onPressed: _detectOrSearchSource,
          isLoading: false,
        ),
        const SizedBox(height: 16),
        _buildHelpCard(
          title: 'Ajouter un site ou flux RSS',
          examples: const [
            'lemonde.fr',
            'techcrunch.com',
            'leplongeoir.substack.com',
            'arstechnica.com',
          ],
          description:
              'La plupart des sites d\'actualite, blogs et newsletters Substack ont un flux RSS automatiquement detecte.',
        ),
        const SizedBox(height: 40),
        Text(
          'Pepites de la communaute',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        trendingAsyncValue.when(
          data: (sources) {
            if (sources.isEmpty) {
              return Text(
                'Aucune pepite pour le moment.',
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
        _buildAtlasFluxCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Tab 1: YouTube ────────────────────────────────────────────

  Widget _buildYouTubePage() {
    return Column(
      key: const ValueKey('youtube'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          hint: 'Coller le lien d\'une chaine YouTube...',
          icon: PhosphorIcons.youtubeLogo(PhosphorIconsStyle.regular),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          _buildLoadingIndicator()
        else if (_previewData != null)
          _buildPreviewCard()
        else ...[
          PrimaryButton(
            label: 'Rechercher',
            onPressed: _detectOrSearchSource,
            isLoading: false,
          ),
          const SizedBox(height: 16),
          _buildHelpCard(
            title: 'Comment trouver le lien',
            steps: const [
              'Ouvrez YouTube',
              'Allez sur la chaine souhaitee',
              'Copiez l\'URL de la barre d\'adresse',
            ],
          ),
          const SizedBox(height: 16),
          _buildHelpCard(
            title: 'Exemples de chaines',
            examples: const [
              'youtube.com/@ScienceEtonnante',
              'youtube.com/@Heu7reka',
              'youtube.com/@Fouloscopie',
              'youtube.com/@HugoDecrypte',
            ],
            description:
                'Facteur recupere les dernieres videos publiees sur la chaine.',
          ),
        ],
        const SizedBox(height: 40),
        _buildAtlasFluxCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Tab 2: Reddit ─────────────────────────────────────────────

  Widget _buildRedditPage() {
    final colors = context.facteurColors;

    return Column(
      key: const ValueKey('reddit'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          hint: 'Nom du subreddit ou URL...',
          icon: PhosphorIcons.redditLogo(PhosphorIconsStyle.regular),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          _buildLoadingIndicator()
        else if (_previewData != null)
          _buildPreviewCard()
        else ...[
          PrimaryButton(
            label: 'Rechercher',
            onPressed: _detectOrSearchSource,
            isLoading: false,
          ),
          const SizedBox(height: 16),
          Container(
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
                  'Vous pouvez entrer :',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                _buildBulletPoint(context, 'Le nom : technology'),
                const SizedBox(height: 4),
                _buildBulletPoint(
                    context, 'L\'URL : reddit.com/r/technology'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildHelpCard(
            title: 'Exemples de subreddits',
            examples: const [
              'r/technology',
              'r/worldnews',
              'r/selfhosted',
              'r/science',
            ],
            description:
                'Facteur recupere les 25 derniers posts du subreddit.',
          ),
        ],
        const SizedBox(height: 40),
        _buildAtlasFluxCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Shared Widgets ────────────────────────────────────────────

  Widget _buildInputField({
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.fill)),
          onPressed: _resetAll,
        ),
      ),
      keyboardType: keyboardType,
      autocorrect: false,
      enabled: !_isLoading,
      style: Theme.of(context).textTheme.bodyMedium,
      onSubmitted: (_) => _detectOrSearchSource(),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return SourcePreviewCard(
      data: _previewData!,
      onConfirm: _confirmSourceFromPreview,
      onCancel: _resetAll,
      isLoading: _isLoading,
    );
  }

  Widget _buildHelpCard({
    required String title,
    List<String>? examples,
    List<String>? steps,
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
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
          ),
          if (steps != null) ...[
            const SizedBox(height: 12),
            ...steps.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${entry.key + 1}.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.4,
                                  ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (examples != null) ...[
            const SizedBox(height: 12),
            ...examples.map((ex) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildBulletPoint(context, ex),
                )),
          ],
          if (description != null) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
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
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
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
                'Aucun resultat trouve',
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
          'Resultats de la recherche',
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
}
