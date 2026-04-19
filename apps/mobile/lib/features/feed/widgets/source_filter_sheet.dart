import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';

class SourceFilterSheet extends ConsumerStatefulWidget {
  final String? currentSourceId;
  final ValueChanged<String> onSourceSelected;

  const SourceFilterSheet({
    super.key,
    this.currentSourceId,
    required this.onSourceSelected,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentSourceId,
    required ValueChanged<String> onSourceSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SourceFilterSheet(
        currentSourceId: currentSourceId,
        onSourceSelected: onSourceSelected,
      ),
    );
  }

  @override
  ConsumerState<SourceFilterSheet> createState() => _SourceFilterSheetState();
}

class _SourceFilterSheetState extends ConsumerState<SourceFilterSheet> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Source> _getFollowedSources(List<Source> allSources) {
    final followed = allSources
        .where((s) => (s.isTrusted || s.isCustom) && !s.isMuted)
        .toList();
    followed.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return followed;
  }

  List<Source> _getFavorites(List<Source> allSources) {
    final followed = allSources
        .where((s) => (s.isTrusted || s.isCustom) && !s.isMuted)
        .toList();
    final favorites = followed
        .where((s) => s.hasSubscription || s.priorityMultiplier >= 2.0)
        .toList();
    favorites.sort((a, b) {
      if (a.hasSubscription != b.hasSubscription) {
        return b.hasSubscription ? 1 : -1;
      }
      return b.priorityMultiplier.compareTo(a.priorityMultiplier);
    });
    return favorites;
  }

  List<Source> _filterByQuery(List<Source> sources) {
    if (_searchQuery.isEmpty) return sources;
    final query = _searchQuery.toLowerCase();
    return sources.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

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
                  'Filtrer parmi vos sources',
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
              child: sourcesAsync.when(
                data: (allSources) {
                  final favorites = _filterByQuery(_getFavorites(allSources));
                  final allFollowed =
                      _filterByQuery(_getFollowedSources(allSources));

                  if (favorites.isEmpty && allFollowed.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Aucune source trouvée'
                            : 'Aucune source suivie',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  final showFavoritesSection =
                      _searchQuery.isEmpty || favorites.isNotEmpty;

                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    shrinkWrap: true,
                    children: [
                      // Favorites section
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
                        if (favorites.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: favorites.map((source) {
                              final isSelected =
                                  source.id == widget.currentSourceId;
                              return _FavoriteChip(
                                source: source,
                                isSelected: isSelected,
                                colors: colors,
                                onTap: () {
                                  widget.onSourceSelected(source.id);
                                  Navigator.of(context).pop();
                                },
                              );
                            }).toList(),
                          ),
                        if (favorites.length < 3) ...[
                          if (favorites.isNotEmpty) const SizedBox(height: 12),
                          _FavoritesPromptCta(
                            label: 'Définir mes sources favorites',
                            subtitle: favorites.isEmpty
                                ? 'Pousse leur priorité à 3/3 dans Mes sources'
                                : '${favorites.length}/3 — ajoute-en encore ${3 - favorites.length}',
                            colors: colors,
                            onTap: () {
                              Navigator.of(context).pop();
                              context.pushNamed(RouteNames.sources);
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],

                      // All sources section
                      if (allFollowed.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'TOUTES VOS SOURCES',
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
                        ...allFollowed.map((source) {
                          final isSelected =
                              source.id == widget.currentSourceId;
                          return _SourceItem(
                            source: source,
                            isSelected: isSelected,
                            colors: colors,
                            onTap: () {
                              widget.onSourceSelected(source.id);
                              Navigator.of(context).pop();
                            },
                          );
                        }),
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

class _FavoriteChip extends StatelessWidget {
  final Source source;
  final bool isSelected;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _FavoriteChip({
    required this.source,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected ? colors.primary : colors.surface;
    final borderColor =
        isSelected ? colors.primary : colors.primary.withOpacity(0.3);
    final textColor = isSelected ? Colors.white : colors.textPrimary;

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
            if (source.logoUrl != null && source.logoUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: FacteurImage(
                  imageUrl: source.logoUrl!,
                  width: 16,
                  height: 16,
                  fit: BoxFit.cover,
                  placeholder: (context) => const SizedBox(width: 16, height: 16),
                  errorWidget: (context) => const SizedBox(width: 16, height: 16),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              source.name,
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

class _SourceItem extends StatelessWidget {
  final Source source;
  final bool isSelected;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _SourceItem({
    required this.source,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            // Logo
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                  ? FacteurImage(
                      imageUrl: source.logoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context) => Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                        color: colors.textTertiary,
                        size: 16,
                      ),
                      errorWidget: (context) => Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                        color: colors.textTertiary,
                        size: 16,
                      ),
                    )
                  : Icon(
                      PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                      color: colors.textTertiary,
                      size: 16,
                    ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                source.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Check mark
            if (isSelected)
              Icon(
                PhosphorIcons.check(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
