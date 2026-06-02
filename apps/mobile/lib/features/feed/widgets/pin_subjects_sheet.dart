import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../custom_topics/widgets/entity_add_sheet.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../../veille/providers/veille_themes_provider.dart';
import '../providers/tab_order_prefs_provider.dart';

/// Nombre d'éléments épinglés (sujets + sources) en-dessous duquel on incite
/// l'utilisateur à en épingler davantage (carte CTA). Aligné sur la promesse
/// « 3-4 suffisent ».
const int kPinSubjectsTarget = 3;

int _pinnedTopicCount(UserInterestsState? interests) {
  final favorites = interests?.favorites ?? const <FavoriteRef>[];
  return favorites.whereType<CustomTopicFavoriteRef>().length;
}

int _pinnedSourceCount(UserSourcesState? sources) {
  return sources?.favorites.length ?? 0;
}

/// Ouvre la modale d'épinglage unifiée (sources + sujets précis). Épingler un
/// élément le transforme en onglet dédié dans Flâner.
Future<void> showPinSubjectsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _PinSubjectsContent(),
      ),
    ),
  );
}

/// Carte proéminente (sliver) affichée en haut du feed Flâner tant que
/// l'utilisateur a épinglé moins de [kPinSubjectsTarget] éléments. Sinon masquée.
class PinSubjectsBanner extends ConsumerWidget {
  const PinSubjectsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ne rebuild la bannière que lorsque le nombre d'éléments épinglés change.
    final pinnedTopics = ref.watch(
      userInterestsProvider.select((value) {
        final interests = value.valueOrNull;
        return interests == null ? null : _pinnedTopicCount(interests);
      }),
    );
    final pinnedSources = ref.watch(
      userSourcesStateProvider.select(
        (value) => _pinnedSourceCount(value.valueOrNull),
      ),
    );
    if (pinnedTopics == null) {
      return const SizedBox.shrink();
    }
    final pinnedCount = pinnedTopics + pinnedSources;
    if (pinnedCount >= kPinSubjectsTarget) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          onTap: () {
            HapticFeedback.mediumImpact();
            showPinSubjectsSheet(context);
          },
          child: Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border:
                  Border.all(color: colors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
                  size: 22,
                  color: colors.primary,
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Text(
                    'Épinglez des sources ou sujets précis',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                Icon(
                  PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Emoji du thème parent d'un sujet (sert d'icône de thématique). Fallback
/// 📰 pour un slug hors des 9 thèmes Facteur (cf. [kVeilleFacteurThemes]).
String _themeEmoji(String slugParent) {
  for (final t in kVeilleFacteurThemes) {
    if (t.slug == slugParent) return t.emoji;
  }
  return '📰';
}

/// Normalise une chaîne pour la recherche : minuscules + accents retirés.
String _normalize(String input) {
  final lower = input.toLowerCase();
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final idx = from.indexOf(char);
    buffer.write(idx == -1 ? char : to[idx]);
  }
  return buffer.toString();
}

/// Un élément épinglé dans la section unifiée « ÉPINGLÉS » : un sujet (custom
/// topic) ou une source.
class _PinnedItem {
  final String key; // "topic:<id>" | "source:<id>"
  final bool isSource;
  final String id; // topicId | sourceId
  final String label;
  final String emoji; // pour un sujet
  final Source? source; // pour une source

  const _PinnedItem({
    required this.key,
    required this.isSource,
    required this.id,
    required this.label,
    required this.emoji,
    this.source,
  });
}

class _PinSubjectsContent extends ConsumerStatefulWidget {
  const _PinSubjectsContent();

  @override
  ConsumerState<_PinSubjectsContent> createState() =>
      _PinSubjectsContentState();
}

class _PinSubjectsContentState extends ConsumerState<_PinSubjectsContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setTopicState(String topicId, InterestState state) async {
    try {
      await ref.read(userInterestsProvider.notifier).setInterestState(
            CustomTopicFavoriteRef(id: topicId),
            state,
          );
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  Future<void> _setSourceState(String sourceId, InterestState state) async {
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(sourceId, state);
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  /// Persiste le nouvel ordre unifié (prefs) puis synchronise — best-effort et
  /// en parallèle — les positions serveur de chaque type (sujets / sources)
  /// pour garder les listes « Mes intérêts » / « Mes sources » cohérentes.
  Future<void> _persistReorder(List<_PinnedItem> ordered) async {
    final keys = ordered.map((e) => e.key).toList();
    await ref.read(tabOrderPrefsProvider.notifier).setOrder(keys);

    final topicIds = [
      for (final e in ordered)
        if (!e.isSource) e.id,
    ];
    final sourceIds = [
      for (final e in ordered)
        if (e.isSource) e.id,
    ];

    // Les deux syncs serveur sont indépendantes → on les lance en parallèle.
    // L'ordre prefs reste appliqué pour les onglets même si une sync échoue.
    await Future.wait([
      _syncTopicPositions(topicIds),
      _syncSourcePositions(sourceIds),
    ]);
  }

  /// Réordonne les `CustomTopicFavoriteRef` serveur selon [topicIds] en
  /// préservant la position des thèmes/veille (qui ne sont pas des onglets).
  Future<void> _syncTopicPositions(List<String> topicIds) async {
    final interests = ref.read(userInterestsProvider).valueOrNull;
    if (interests == null) return;
    final newTopicQueue = [
      for (final id in topicIds) CustomTopicFavoriteRef(id: id),
    ];
    final topicSlots =
        interests.favorites.whereType<CustomTopicFavoriteRef>().length;
    if (newTopicQueue.length != topicSlots) return;
    var i = 0;
    final merged = [
      for (final f in interests.favorites)
        f is CustomTopicFavoriteRef ? newTopicQueue[i++] : f,
    ];
    try {
      await ref.read(userInterestsProvider.notifier).reorderFavorites(merged);
    } catch (_) {
      // L'ordre prefs reste appliqué pour les onglets ; on ignore.
    }
  }

  /// Réassigne les positions canoniques des sources favorites selon [sourceIds].
  Future<void> _syncSourcePositions(List<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    final orderedRefs = [
      for (var i = 0; i < sourceIds.length; i++)
        SourceFavoriteRef(sourceId: sourceIds[i], position: i),
    ];
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .reorderFavorites(orderedRefs);
    } catch (_) {
      // idem : best-effort.
    }
  }

  bool _matchesText(String text, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return _normalize(text).contains(normalizedQuery);
  }

  /// Groupe les sujets par thème parent, dans l'ordre canonique des thèmes
  /// Facteur (les thèmes inconnus en dernier), sujets triés alpha dans chaque
  /// groupe.
  List<MapEntry<String, List<CustomTopicInterest>>> _groupByTheme(
    List<CustomTopicInterest> subjects,
  ) {
    final groups = <String, List<CustomTopicInterest>>{};
    for (final t in subjects) {
      groups.putIfAbsent(t.slugParent, () => []).add(t);
    }
    for (final list in groups.values) {
      list.sort((a, b) =>
          a.topicName.toLowerCase().compareTo(b.topicName.toLowerCase()));
    }
    final order = {
      for (var i = 0; i < kVeilleFacteurThemes.length; i++)
        kVeilleFacteurThemes[i].slug: i,
    };
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final ia = order[a.key] ?? kVeilleFacteurThemes.length;
        final ib = order[b.key] ?? kVeilleFacteurThemes.length;
        if (ia != ib) return ia.compareTo(ib);
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final topics = interests?.customTopics ?? const <CustomTopicInterest>[];

    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    final sourceInterests =
        sourcesState?.sources ?? const <SourceInterest>[];
    final sourceFavorites =
        sourcesState?.favorites ?? const <SourceFavoriteRef>[];
    final catalog = ref.watch(userSourcesProvider).valueOrNull ??
        const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};

    final order = ref.watch(tabOrderPrefsProvider);

    final normalizedQuery = _normalize(_query.trim());
    final hasQuery = normalizedQuery.isNotEmpty;

    // ── Section ÉPINGLÉS (interleaved, drag) ──────────────────────────
    final pinnedItems = <_PinnedItem>[];
    for (final t in topics.where((t) => t.state == InterestState.favorite)) {
      pinnedItems.add(_PinnedItem(
        key: tabOrderTopicKey(t.id),
        isSource: false,
        id: t.id,
        label: t.topicName,
        emoji: _themeEmoji(t.slugParent),
      ));
    }
    for (final f in sourceFavorites) {
      final source = sourceById[f.sourceId];
      if (source == null) continue;
      pinnedItems.add(_PinnedItem(
        key: tabOrderSourceKey(f.sourceId),
        isSource: true,
        id: f.sourceId,
        label: source.name,
        emoji: '',
        source: source,
      ));
    }
    final orderedPinned = applyOrder(pinnedItems, order, (e) => e.key);

    // ── Section SOURCES SUIVIES (followed, non épinglées) ─────────────
    final followedSourceIds = sourceInterests
        .where((s) => s.state == InterestState.followed)
        .map((s) => s.sourceId)
        .toSet();
    final followedSources = [
      for (final s in catalog)
        if (followedSourceIds.contains(s.id) &&
            _matchesText(s.name, normalizedQuery))
          s,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // ── Section SUJETS À ÉPINGLER (suivis non favoris, groupés) ───────
    final pinnableTopics = topics
        .where((t) =>
            t.state != InterestState.favorite &&
            _matchesText(t.topicName, normalizedQuery))
        .toList();
    final pinnableGroups = _groupByTheme(pinnableTopics);

    final hasAnything = topics.isNotEmpty || catalog.isNotEmpty;
    final noMatch = orderedPinned.isEmpty &&
        followedSources.isEmpty &&
        pinnableTopics.isEmpty;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),
                Text(
                  'Épingler des sources et sujets',
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sources et sujets épinglés deviennent vos onglets dans '
                  'Flâner. Glissez pour les réordonner.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                if (hasAnything)
                  _SearchField(
                    controller: _searchController,
                    colors: colors,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () => setState(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
                if (hasAnything)
                  const SizedBox(height: FacteurSpacing.space4),

                // Éléments déjà épinglés → drag pour réordonner, tap icône
                // pour dé-épingler.
                if (orderedPinned.isNotEmpty) ...[
                  _SectionLabel(label: 'ÉPINGLÉS', colors: colors),
                  const SizedBox(height: 8),
                  _PinnedItemsList(
                    items: orderedPinned,
                    colors: colors,
                    onReorder: (oldIndex, newIndex) {
                      final reordered = [...orderedPinned];
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      _persistReorder(reordered);
                    },
                    onUnpin: (item) {
                      if (item.isSource) {
                        _setSourceState(item.id, InterestState.followed);
                      } else {
                        _setTopicState(item.id, InterestState.unfollowed);
                      }
                    },
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Sources suivies non épinglées → 1 tap pour épingler.
                if (followedSources.isNotEmpty) ...[
                  _SectionLabel(label: 'SOURCES SUIVIES', colors: colors),
                  const SizedBox(height: 8),
                  for (final s in followedSources)
                    _InterestRow(
                      key: ValueKey('followed_${s.id}'),
                      leading:
                          SourceLogoAvatar(source: s, size: 28, radius: 6),
                      label: s.name,
                      colors: colors,
                      onTap: () =>
                          _setSourceState(s.id, InterestState.favorite),
                    ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Sujets suivis non épinglés → groupés par thématique.
                if (pinnableTopics.isNotEmpty) ...[
                  _SectionLabel(
                    label: 'SUJETS À ÉPINGLER',
                    colors: colors,
                  ),
                  const SizedBox(height: 8),
                  for (final group in pinnableGroups) ...[
                    _ThemeGroupHeader(
                      emoji: _themeEmoji(group.key),
                      label: veilleThemeLabelForSlug(group.key),
                      colors: colors,
                    ),
                    const SizedBox(height: 6),
                    for (final t in group.value)
                      _InterestRow(
                        key: ValueKey('pinnable_${t.id}'),
                        leading: Text(
                          _themeEmoji(t.slugParent),
                          style: const TextStyle(fontSize: 14),
                        ),
                        label: t.topicName,
                        colors: colors,
                        onTap: () =>
                            _setTopicState(t.id, InterestState.favorite),
                      ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: FacteurSpacing.space2),
                ],

                // Aucun élément ne matche la recherche → proposer de créer.
                if (hasQuery && noMatch) ...[
                  _CreateSubjectTile(
                    query: _query.trim(),
                    colors: colors,
                    onTap: () => EntityAddSheet.show(
                      context,
                      pinOnFollow: true,
                      initialQuery: _query.trim(),
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Rien du tout (et pas de recherche en cours).
                if (!hasQuery && !hasAnything) ...[
                  Text(
                    'Aucun sujet pour le moment. Crée ton premier sujet '
                    'à suivre ci-dessous.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => EntityAddSheet.show(
                      context,
                      pinOnFollow: true,
                    ),
                    icon: Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      size: 16,
                      color: colors.primary,
                    ),
                    label: Text(
                      'Créer un sujet',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.primary.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Liste réordonnable des éléments épinglés (sujets + sources interleaved).
class _PinnedItemsList extends StatelessWidget {
  final List<_PinnedItem> items;
  final FacteurColors colors;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(_PinnedItem item) onUnpin;

  const _PinnedItemsList({
    required this.items,
    required this.colors,
    required this.onReorder,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          key: ValueKey(item.key),
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                if (item.isSource && item.source != null)
                  SourceLogoAvatar(source: item.source!, size: 28, radius: 6)
                else
                  Text(item.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onUnpin(item);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
                      size: 16,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIcons.dotsSixVertical(PhosphorIconsStyle.bold),
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FacteurColors colors;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Rechercher une source ou un sujet…',
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
        prefixIcon: Icon(
          PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
          size: 18,
          color: colors.textTertiary,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  PhosphorIcons.x(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.textTertiary,
                ),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
    );
  }
}

class _ThemeGroupHeader extends StatelessWidget {
  final String emoji;
  final String label;
  final FacteurColors colors;

  const _ThemeGroupHeader({
    required this.emoji,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _CreateSubjectTile extends StatelessWidget {
  final String query;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _CreateSubjectTile({
    required this.query,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Créer le sujet ',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: '« $query »',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final FacteurColors colors;

  const _SectionLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
    );
  }
}

/// Ligne tappable d'un élément suivi à épingler — un sujet (emoji en tête) ou
/// une source ([SourceLogoAvatar] en tête). Le contenu de tête varie via
/// [leading] ; le reste (libellé + icône « + ») est commun.
class _InterestRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _InterestRow({
    super.key,
    required this.leading,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  PhosphorIcons.plus(PhosphorIconsStyle.bold),
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
