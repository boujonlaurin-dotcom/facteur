import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';

const Map<String, String> _apiSlugToMacroLabel = {
  'tech': 'Technologie',
  'science': 'Sciences',
  'society': 'Société',
  'politics': 'Politique',
  'economy': 'Économie',
  'environment': 'Environnement',
  'culture': 'Culture',
  'international': 'Géopolitique',
  'sport': 'Sport',
};

class InterestFilterSheet extends ConsumerStatefulWidget {
  final String? currentTopicSlug;
  final bool currentIsTheme;
  final void Function(String slug, String name, {bool isTheme, bool isEntity})
      onInterestSelected;

  const InterestFilterSheet({
    super.key,
    this.currentTopicSlug,
    this.currentIsTheme = false,
    required this.onInterestSelected,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentTopicSlug,
    bool currentIsTheme = false,
    required void Function(String slug, String name, {bool isTheme, bool isEntity})
        onInterestSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => InterestFilterSheet(
        currentTopicSlug: currentTopicSlug,
        currentIsTheme: currentIsTheme,
        onInterestSelected: onInterestSelected,
      ),
    );
  }

  @override
  ConsumerState<InterestFilterSheet> createState() =>
      _InterestFilterSheetState();
}

class _InterestFilterSheetState extends ConsumerState<InterestFilterSheet> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Story 22.1 — résout les favoris canoniques sous forme de chips ordonnés.
  /// Les Thèmes apparaissent comme chip dédié (emoji macro), les Sujets/entités
  /// comme chip classique. Ordre = `favoriteOrder` du provider (drag user-controlled).
  List<_FavoriteChipData> _resolveFavoriteChips(
    List<FavoriteRef> favorites,
    List<UserTopicProfile> allTopics,
  ) {
    final byId = {for (final t in allTopics) t.id: t};
    final out = <_FavoriteChipData>[];
    for (final fav in favorites) {
      switch (fav) {
        case ThemeFavoriteRef(:final slug):
          final macro = _apiSlugToMacroLabel[slug] ?? slug;
          out.add(_FavoriteChipData.theme(
            slug: slug,
            label: macro,
            emoji: getMacroThemeEmoji(macro),
          ));
        case CustomTopicFavoriteRef(:final id):
          final topic = byId[id];
          if (topic != null) {
            out.add(_FavoriteChipData.topic(topic: topic));
          }
        case VeilleFavoriteRef():
          // La veille n'apparaît pas dans le filter sheet feed (Story 22.1) —
          // c'est un type de favori avec son propre flow d'édition/archive
          // depuis Mes intérêts (Story 23.2 PR-4).
          break;
      }
    }
    return out;
  }

  /// Filter quick picks by search query.
  List<_FavoriteChipData> _filterFavoriteChips(List<_FavoriteChipData> picks) {
    if (_searchQuery.isEmpty) return picks;
    final q = _searchQuery.toLowerCase();
    return picks.where((c) => c.label.toLowerCase().contains(q)).toList();
  }

  /// Filter macro-themes by search query.
  List<String> _filterThemes() {
    if (_searchQuery.isEmpty) return macroThemeOrder;
    final q = _searchQuery.toLowerCase();
    return macroThemeOrder.where((t) => t.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final topicsAsync = ref.watch(customTopicsProvider);
    final favorites =
        ref.watch(userInterestsProvider).value?.favorites ??
            const <FavoriteRef>[];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.81,
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
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtrer parmi vos intérêts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                    color: colors.textTertiary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            PhosphorIcons.x(PhosphorIconsStyle.regular),
                            color: colors.textTertiary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Content
            Flexible(
              child: topicsAsync.when(
                data: (allTopics) {
                  final allFavoriteChips =
                      _resolveFavoriteChips(favorites, allTopics);
                  final quickPicks = _filterFavoriteChips(allFavoriteChips);
                  final filteredThemes = _filterThemes();
                  final topicCounts = countTopicsPerMacroTheme(allTopics);

                  if (quickPicks.isEmpty && filteredThemes.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Aucun sujet trouvé'
                            : 'Aucun sujet disponible',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  final showFavoritesSection =
                      _searchQuery.isEmpty || quickPicks.isNotEmpty;

                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    shrinkWrap: true,
                    children: [
                      // Quick picks section
                      if (showFavoritesSection) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 10),
                          child: Text(
                            'VOS FAVORIS',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textTertiary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        if (quickPicks.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: quickPicks.map((chip) {
                              final isSelected = chip.isTheme
                                  ? (widget.currentIsTheme &&
                                      chip.themeSlug == widget.currentTopicSlug)
                                  : (!widget.currentIsTheme &&
                                      chip.selectedSlug ==
                                          widget.currentTopicSlug);
                              return _FavoriteChip(
                                data: chip,
                                isSelected: isSelected,
                                colors: colors,
                                onTap: () {
                                  if (chip.isTheme) {
                                    widget.onInterestSelected(
                                      chip.themeSlug!,
                                      chip.label,
                                      isTheme: true,
                                    );
                                  } else {
                                    final topic = chip.topic!;
                                    final isEntity = topic.entityType != null;
                                    widget.onInterestSelected(
                                      isEntity
                                          ? topic.canonicalName ?? topic.name
                                          : topic.slugParent ?? topic.id,
                                      topic.name,
                                      isTheme: false,
                                      isEntity: isEntity,
                                    );
                                  }
                                  Navigator.of(context).pop();
                                },
                              );
                            }).toList(),
                          ),
                        if (quickPicks.length < 3) ...[
                          if (quickPicks.isNotEmpty) const SizedBox(height: 12),
                          _FavoritesPromptCta(
                            label: 'Définir mes thèmes favoris',
                            subtitle: quickPicks.isEmpty
                                ? 'Ajoute-les en favori dans Mes intérêts (top 3 = Tournée du jour)'
                                : '${quickPicks.length} favori${quickPicks.length > 1 ? "s" : ""} — top 3 affiché dans la Tournée du jour',
                            colors: colors,
                            onTap: () {
                              Navigator.of(context).pop();
                              context.pushNamed(RouteNames.myInterests);
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],

                      // Themes grid section
                      if (filteredThemes.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'THÈMES',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textTertiary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.05,
                          children: filteredThemes.map((themeLabel) {
                            final slug = macroThemeToApiSlug[themeLabel];
                            final isSelected = widget.currentIsTheme &&
                                slug == widget.currentTopicSlug;
                            final count = topicCounts[themeLabel] ?? 0;
                            return _ThemeCard(
                              label: themeLabel,
                              emoji: getMacroThemeEmoji(themeLabel),
                              topicCount: count,
                              isSelected: isSelected,
                              colors: colors,
                              onTap: () {
                                if (slug == null) return;
                                widget.onInterestSelected(
                                  slug,
                                  themeLabel,
                                  isTheme: true,
                                );
                                Navigator.of(context).pop();
                              },
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 16),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Erreur de chargement',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Story 22.1 — valeur d'affichage d'un favori (Thème ou Sujet) dans la sheet.
class _FavoriteChipData {
  final bool isTheme;
  final String label;
  final String emoji;
  // For themes:
  final String? themeSlug;
  // For custom topics:
  final UserTopicProfile? topic;

  const _FavoriteChipData._({
    required this.isTheme,
    required this.label,
    required this.emoji,
    this.themeSlug,
    this.topic,
  });

  factory _FavoriteChipData.theme({
    required String slug,
    required String label,
    required String emoji,
  }) =>
      _FavoriteChipData._(
        isTheme: true,
        label: label,
        emoji: emoji,
        themeSlug: slug,
      );

  factory _FavoriteChipData.topic({required UserTopicProfile topic}) {
    final isEntity = topic.entityType != null;
    final emoji = isEntity
        ? getEntityTypeEmoji(topic.entityType)
        : getMacroThemeEmoji(
            getTopicMacroTheme(topic.slugParent ?? '') ?? '');
    return _FavoriteChipData._(
      isTheme: false,
      label: topic.name,
      emoji: emoji,
      topic: topic,
    );
  }

  /// Slug renvoyé au caller via `onInterestSelected` quand c'est un topic.
  String? get selectedSlug {
    if (topic == null) return null;
    return topic!.entityType != null
        ? (topic!.canonicalName ?? topic!.name)
        : topic!.slugParent;
  }
}

class _FavoriteChip extends StatelessWidget {
  final _FavoriteChipData data;
  final bool isSelected;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _FavoriteChip({
    required this.data,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = data.isTheme
        ? colors.primary
        : (data.topic?.entityType != null
            ? Colors.orange.shade600
            : Colors.green.shade700);

    final bgColor = isSelected ? accent : accent.withOpacity(0.10);
    final borderColor = isSelected ? accent : accent.withOpacity(0.30);
    final textColor = isSelected ? Colors.white : accent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.emoji.isNotEmpty) ...[
              Text(data.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
            ],
            Text(
              data.label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesPromptCta extends StatelessWidget {
  final String label;
  final String subtitle;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _FavoritesPromptCta({
    required this.label,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.star(PhosphorIconsStyle.regular),
              color: colors.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String label;
  final String emoji;
  final int topicCount;
  final bool isSelected;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.label,
    required this.emoji,
    required this.topicCount,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF8EB) : colors.surface,
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (topicCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                topicCount == 1 ? '1 sujet' : '$topicCount sujets',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
