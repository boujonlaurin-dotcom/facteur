import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/ui/notification_service.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/add_source_bridge.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/search_result.dart';
import '../providers/feed_provider.dart';
import '../providers/search_history_provider.dart';
import '../providers/trending_topics_provider.dart';
import '../utils/search_results_builder.dart';

/// Origines analytics de l'ouverture de la sheet (`search_opened`).
const String kSearchOriginHeader = 'header';
const String kSearchOriginFilterBar = 'filter_bar';

/// Onglets analytiques (`search_opened.tab`).
const String kSearchTabFlaner = 'flaner';
const String kSearchTabEssentiel = 'essentiel';

/// Délai avant recalcul des résultats. Le calcul est purement local (aucun
/// appel réseau), le debounce sert uniquement à éviter de reconstruire la liste
/// à chaque frappe rapide.
const Duration _kDebounce = Duration(milliseconds: 180);

/// Recherche universelle (story 30.1) : un seul champ pour retrouver un
/// **article**, une **source** (suivie ou à ajouter), un **sujet suivi** ou un
/// **thème**.
///
/// La sheet applique elle-même le filtre sur `feedProvider` — les filtres sont
/// partagés par les deux onglets — mais **ne navigue pas** : le hôte sait d'où
/// il ouvre la sheet et décide via [onApplied] (le bouton du header bascule sur
/// Flâner, la barre de filtres de Flâner n'a rien à faire).
class SearchFilterSheet extends ConsumerStatefulWidget {
  final String? currentKeyword;

  /// `header` ou `filter_bar` — reporté tel quel dans `search_opened`.
  final String origin;

  /// Onglet depuis lequel la sheet est ouverte (`flaner` / `essentiel`) —
  /// reporté dans `search_opened`.
  final String tab;

  /// Notifié après l'application d'un filtre (le hôte navigue, remonte en haut
  /// de liste, referme un panneau…).
  final VoidCallback? onApplied;

  const SearchFilterSheet({
    super.key,
    this.currentKeyword,
    this.origin = kSearchOriginFilterBar,
    this.tab = kSearchTabFlaner,
    this.onApplied,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentKeyword,
    String origin = kSearchOriginFilterBar,
    String tab = kSearchTabFlaner,
    VoidCallback? onApplied,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SearchFilterSheet(
        currentKeyword: currentKeyword,
        origin: origin,
        tab: tab,
        onApplied: onApplied,
      ),
    );
  }

  @override
  ConsumerState<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<SearchFilterSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Requête effectivement utilisée pour construire les résultats (débouncée).
  String _query = '';
  Timer? _debounce;

  /// Source du catalogue en cours d'ajout — verrouille la ligne le temps de
  /// l'aller-retour réseau.
  String? _addingSourceId;

  @override
  void initState() {
    super.initState();
    if (widget.currentKeyword != null) {
      _searchController.text = widget.currentKeyword!;
      _query = widget.currentKeyword!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    unawaited(
      ref.read(analyticsServiceProvider).trackSearchOpened(
            origin: widget.origin,
            tab: widget.tab,
          ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // Le bouton « effacer » et le passage vide → non-vide doivent être
    // instantanés ; seul le typage continu est débouncé.
    if (value.trim().isEmpty || _query.isEmpty) {
      setState(() => _query = value);
      return;
    }
    _debounce = Timer(_kDebounce, () {
      if (mounted) setState(() => _query = value);
    });
  }

  // ── Application des filtres ────────────────────────────────────────────

  /// Ferme la sheet, applique [apply], puis rend la main au hôte via
  /// `onApplied` (c'est lui qui sait s'il faut changer d'onglet).
  Future<void> _applyAndClose(
    Future<void> Function() apply, {
    required SearchResult result,
    required int rank,
  }) async {
    unawaited(
      ref.read(analyticsServiceProvider).trackSearchResultSelected(
            resultType: result.analyticsType,
            rank: rank,
            queryLength: _searchController.text.trim().length,
          ),
    );
    Navigator.of(context).pop();
    await apply();
    widget.onApplied?.call();
  }

  Future<void> _selectKeyword(
    String query, {
    bool fromTrending = false,
    int rank = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    unawaited(ref.read(searchHistoryProvider.notifier).addSearch(trimmed));
    final notifier = ref.read(feedProvider.notifier);
    await _applyAndClose(
      () => notifier.setKeyword(trimmed, includeUnfollowed: fromTrending),
      result: KeywordResult(trimmed),
      rank: rank,
    );
  }

  Future<void> _selectSource(Source source, int rank) {
    final notifier = ref.read(feedProvider.notifier);
    return _applyAndClose(
      () => notifier.setSource(source.id),
      result: FollowedSourceResult(source),
      rank: rank,
    );
  }

  Future<void> _selectTopic(TopicResult result, int rank) {
    final notifier = ref.read(feedProvider.notifier);
    return _applyAndClose(
      () => result.isEntity
          ? notifier.setEntity(result.filterValue)
          : notifier.setTopic(result.filterValue),
      result: result,
      rank: rank,
    );
  }

  Future<void> _selectTheme(ThemeResult result, int rank) {
    final notifier = ref.read(feedProvider.notifier);
    return _applyAndClose(
      () => notifier.setTheme(result.slug),
      result: result,
      rank: rank,
    );
  }

  /// Ajout en 1 tap d'une source du catalogue pas encore suivie, puis filtre
  /// dessus : l'utilisateur voit son flux dans la foulée, sans écran
  /// intermédiaire.
  Future<void> _addCatalogSource(Source source, int rank) async {
    if (_addingSourceId != null) return;
    setState(() => _addingSourceId = source.id);
    unawaited(HapticFeedback.mediumImpact());
    final analytics = ref.read(analyticsServiceProvider);
    try {
      await ref.read(sourcesRepositoryProvider).trustSource(source.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingSourceId = null);
      NotificationService.showError(
        'Impossible d\'ajouter cette source pour le moment.',
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(userSourcesProvider);
    unawaited(analytics.trackSearchAddSourceBridged(bridgeCase: 'catalog_follow'));
    NotificationService.showSuccess(
      '« ${source.name} » ajoutée à tes sources.',
    );
    final notifier = ref.read(feedProvider.notifier);
    await _applyAndClose(
      () => notifier.setSource(source.id),
      result: CatalogSourceResult(source),
      rank: rank,
    );
  }

  /// Bascule vers l'écran d'ajout de source avec la recherche intelligente
  /// **déjà lancée** sur la requête saisie.
  void _openAddSource(AddSourceResult result, int rank) {
    final trimmed = result.query.trim();
    if (trimmed.isEmpty) return;
    unawaited(
      ref.read(analyticsServiceProvider).trackSearchResultSelected(
            resultType: result.analyticsType,
            rank: rank,
            queryLength: trimmed.length,
          ),
    );
    // Le push doit partir du navigator **parent** : le context de la sheet est
    // démonté par le pop.
    final host = Navigator.of(context).context;
    Navigator.of(context).pop();
    openAddSourceFor(host, ref, trimmed);
  }

  /// Efface la recherche active depuis la sheet. C'est la seule sortie
  /// disponible depuis L'Essentiel, qui ne monte jamais la barre de filtres
  /// (donc jamais la pill « ✕ ») alors que la loupe du header, elle, y signale
  /// bien une recherche en cours.
  Future<void> _clearSearch() async {
    final notifier = ref.read(feedProvider.notifier);
    Navigator.of(context).pop();
    await notifier.setKeyword(null);
    widget.onApplied?.call();
  }

  // ── Rendu ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasQuery = _query.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rechercher',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                      ),
                    ),
                    if (widget.currentKeyword != null)
                      TextButton(
                        onPressed: _clearSearch,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Effacer la recherche'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSearchField(colors),
              const SizedBox(height: 8),
              Flexible(
                child: hasQuery
                    ? _buildResults(colors)
                    : _buildColdStart(colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: _onQueryChanged,
        onSubmitted: (value) => _selectKeyword(value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Source, sujet, thème ou article…',
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
          prefixIcon: Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
            color: colors.textTertiary,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.regular),
                    color: colors.textTertiary,
                    size: 18,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: colors.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
      ),
    );
  }

  /// Query vide : recherches récentes · sources favorites · sujets du moment.
  Widget _buildColdStart(FacteurColors colors) {
    final history = ref.watch(searchHistoryProvider);
    final trendingAsync = ref.watch(trendingTopicsProvider);
    final favorites = _favoriteSources(
      ref.watch(userSourcesProvider).valueOrNull ?? const <Source>[],
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shrinkWrap: true,
      children: [
        if (history.isNotEmpty) ...[
          _SectionHeader(
            label: 'RECHERCHES RÉCENTES',
            colors: colors,
            trailing: GestureDetector(
              onTap: () =>
                  ref.read(searchHistoryProvider.notifier).clearHistory(),
              child: Text(
                'Effacer',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final query = history[index];
                return _HistoryChip(
                  label: query,
                  colors: colors,
                  onTap: () => _selectKeyword(query, rank: index),
                  onDelete: () => ref
                      .read(searchHistoryProvider.notifier)
                      .removeSearch(query),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Accès direct au filtre source — le geste le plus coûteux aujourd'hui
        // (panneau filtres → chip source → sheet) devient un tap.
        if (favorites.isNotEmpty) ...[
          _SectionHeader(label: 'TES SOURCES FAVORITES', colors: colors),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < favorites.length; i++)
                _SourcePill(
                  source: favorites[i],
                  colors: colors,
                  onTap: () => _selectSource(favorites[i], i),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        trendingAsync.when(
          data: (topics) {
            if (topics.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(label: 'SUJETS DU MOMENT', colors: colors),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < topics.length; i++)
                      _TrendingChip(
                        topic: topics[i],
                        colors: colors,
                        onTap: () => _selectKeyword(
                          topics[i].keyword,
                          fromTrending: true,
                          rank: i,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  List<Source> _favoriteSources(List<Source> all) {
    final favoriteIds = ref
            .watch(userSourcesStateProvider)
            .valueOrNull
            ?.favorites
            .map((f) => f.sourceId)
            .toSet() ??
        const <String>{};
    if (favoriteIds.isEmpty) return const [];
    final out = <Source>[];
    for (final source in all) {
      if (!favoriteIds.contains(source.id)) continue;
      if (!isFollowedSource(source)) continue;
      out.add(source);
      if (out.length == 6) break;
    }
    return out;
  }

  /// Sections mémoïsées : `build()` dépend de `MediaQuery` (insets clavier),
  /// donc il rejoue **à chaque frame** de l'animation d'ouverture du clavier —
  /// et aussi à chaque `setState` du spinner d'ajout. Sans ce cache, chaque
  /// frame relançait un balayage complet du catalogue.
  String? _sectionsQuery;
  List<Source>? _sectionsSources;
  List<UserTopicProfile>? _sectionsTopics;
  List<SearchSection> _sectionsCache = const [];

  List<SearchSection> _sectionsFor(
    List<Source> allSources,
    List<UserTopicProfile> topics,
  ) {
    if (_sectionsQuery == _query &&
        identical(_sectionsSources, allSources) &&
        identical(_sectionsTopics, topics)) {
      return _sectionsCache;
    }
    _sectionsQuery = _query;
    _sectionsSources = allSources;
    _sectionsTopics = topics;
    _sectionsCache = buildSearchSections(
      query: _query,
      allSources: allSources,
      topics: topics,
    );
    return _sectionsCache;
  }

  /// Query non vide : sections calculées en local.
  Widget _buildResults(FacteurColors colors) {
    final allSources =
        ref.watch(userSourcesProvider).valueOrNull ?? const <Source>[];
    final topics = ref.watch(customTopicsProvider).valueOrNull ??
        const <UserTopicProfile>[];
    final sections = _sectionsFor(allSources, topics);

    final children = <Widget>[];
    for (final section in sections) {
      children.add(_SectionHeader(
        label: section.title.toUpperCase(),
        colors: colors,
        trailing: section.hasMore
            ? Text(
                '${section.totalMatches}',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              )
            : null,
      ));
      for (var i = 0; i < section.results.length; i++) {
        children.add(_buildResultTile(section.results[i], i, colors));
      }
      children.add(const SizedBox(height: 12));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shrinkWrap: true,
      children: children,
    );
  }

  Widget _buildResultTile(SearchResult result, int rank, FacteurColors colors) {
    switch (result) {
      case KeywordResult(:final query):
        return _ResultTile(
          colors: colors,
          leading: Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
            size: 18,
            color: colors.primary,
          ),
          title: 'Rechercher « $query »',
          subtitle: 'Dans les titres d\'articles',
          onTap: () => _selectKeyword(query, rank: rank),
        );

      case FollowedSourceResult(:final source):
        return _ResultTile(
          colors: colors,
          leading: SourceLogoAvatar(source: source, size: 28, radius: 8),
          title: source.name,
          subtitle: 'Filtrer sur cette source',
          onTap: () => _selectSource(source, rank),
        );

      case CatalogSourceResult(:final source):
        final busy = _addingSourceId == source.id;
        return _ResultTile(
          colors: colors,
          leading: SourceLogoAvatar(source: source, size: 28, radius: 8),
          title: source.name,
          subtitle: 'Pas encore dans tes sources',
          trailing: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _AddPill(colors: colors),
          onTap: busy ? null : () => _addCatalogSource(source, rank),
        );

      case TopicResult():
        return _ResultTile(
          colors: colors,
          leading: Icon(
            PhosphorIcons.tag(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textSecondary,
          ),
          title: result.topic.name,
          subtitle: result.isEntity ? 'Entité suivie' : 'Sujet suivi',
          onTap: () => _selectTopic(result, rank),
        );

      case ThemeResult():
        return _ResultTile(
          colors: colors,
          leading: Text(result.emoji, style: const TextStyle(fontSize: 18)),
          title: result.label,
          subtitle: 'Filtrer sur ce thème',
          onTap: () => _selectTheme(result, rank),
        );

      case AddSourceResult():
        return _ResultTile(
          colors: colors,
          leading: Icon(
            PhosphorIcons.plusCircle(PhosphorIconsStyle.bold),
            size: 18,
            color: colors.primary,
          ),
          title: 'Chercher « ${result.query} » sur le web',
          subtitle: 'Ajouter une source qui n\'est pas encore au catalogue',
          onTap: () => _openAddSource(result, rank),
        );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final FacteurColors colors;
  final Widget? trailing;

  const _SectionHeader({
    required this.label,
    required this.colors,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: trailing == null
          ? Align(alignment: Alignment.centerLeft, child: text)
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [text, trailing!],
            ),
    );
  }
}

/// Ligne de résultat générique — icône/logo · titre · sous-titre · action.
class _ResultTile extends StatelessWidget {
  final FacteurColors colors;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ResultTile({
    required this.colors,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(width: 28, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  final FacteurColors colors;

  const _AddPill({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(FacteurRadius.full),
      ),
      child: Text(
        'Ajouter',
        style: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  final Source source;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _SourcePill({
    required this.source,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SourceLogoAvatar(source: source, size: 20, radius: 6),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;
  final FacteurColors colors;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryChip({
    required this.label,
    required this.colors,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.regular),
              size: 14,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDelete,
              child: Icon(
                PhosphorIcons.x(PhosphorIconsStyle.regular),
                size: 12,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendingChip extends StatelessWidget {
  final TrendingTopic topic;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _TrendingChip({
    required this.topic,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.trendUp(PhosphorIconsStyle.regular),
              size: 14,
              color: colors.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _truncateLabel(topic.label),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${topic.sourceCount} sources',
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _truncateLabel(String label) {
    if (label.length <= 50) return label;
    final truncated = label.substring(0, 50);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > 25) return '${truncated.substring(0, lastSpace)}…';
    return '$truncated…';
  }
}
