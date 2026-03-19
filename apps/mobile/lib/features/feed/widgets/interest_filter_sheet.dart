import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';

class InterestFilterSheet extends ConsumerStatefulWidget {
  final String? currentTopicSlug;
  final void Function(String slug, String name) onInterestSelected;

  const InterestFilterSheet({
    super.key,
    this.currentTopicSlug,
    required this.onInterestSelected,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentTopicSlug,
    required void Function(String slug, String name) onInterestSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => InterestFilterSheet(
        currentTopicSlug: currentTopicSlug,
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

  /// Filter and group topics by macro-theme.
  Map<String, List<UserTopicProfile>> _getGroupedTopics(
      List<UserTopicProfile> allTopics) {
    // Filter by search query
    final filtered = _searchQuery.isEmpty
        ? allTopics
        : allTopics
            .where(
                (t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    // Group by macro-theme
    final groups = <String, List<UserTopicProfile>>{};
    for (final topic in filtered) {
      final macroTheme =
          getTopicMacroTheme(topic.slugParent ?? '') ?? 'Autre';
      groups.putIfAbsent(macroTheme, () => []);
      groups[macroTheme]!.add(topic);
    }

    // Sort items within each group alphabetically
    for (final list in groups.values) {
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return groups;
  }

  /// Display label for an entity type.
  String _entityTypeLabel(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PERSON':
        return 'personne';
      case 'ORG':
        return 'organisation';
      case 'LOCATION':
        return 'lieu';
      case 'EVENT':
        return 'événement';
      case 'PRODUCT':
        return 'produit';
      default:
        return entityType.toLowerCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final topicsAsync = ref.watch(customTopicsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                  color: colors.textTertiary.withValues(alpha: 0.3),
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
                  'Filtrer par sujet',
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
                    vertical: 10,
                  ),
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

            // Topics list
            Flexible(
              child: topicsAsync.when(
                data: (allTopics) {
                  final grouped = _getGroupedTopics(allTopics);

                  if (grouped.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Aucun sujet trouvé'
                            : 'Aucun sujet suivi',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  final sortedThemes = grouped.keys.toList()..sort();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shrinkWrap: true,
                    itemCount: sortedThemes.length,
                    itemBuilder: (context, index) {
                      final theme = sortedThemes[index];
                      final topics = grouped[theme]!;
                      final emoji = getMacroThemeEmoji(theme);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              '$emoji $theme',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colors.textTertiary,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ),
                          // Topic items
                          ...topics.map((topic) => _InterestItem(
                                topic: topic,
                                isSelected:
                                    topic.slugParent == widget.currentTopicSlug,
                                entityTypeLabel: topic.entityType != null
                                    ? _entityTypeLabel(topic.entityType!)
                                    : null,
                                colors: colors,
                                onTap: () {
                                  widget.onInterestSelected(
                                    topic.slugParent ?? topic.id,
                                    topic.name,
                                  );
                                  Navigator.of(context).pop();
                                },
                              )),
                        ],
                      );
                    },
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

class _InterestItem extends StatelessWidget {
  final UserTopicProfile topic;
  final bool isSelected;
  final String? entityTypeLabel;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _InterestItem({
    required this.topic,
    required this.isSelected,
    this.entityTypeLabel,
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
            // Icon based on entity type
            Icon(
              entityTypeLabel != null
                  ? _iconForEntityType(topic.entityType)
                  : PhosphorIcons.hash(PhosphorIconsStyle.regular),
              color: isSelected ? colors.primary : colors.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 12),

            // Name + optional entity type label
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: topic.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                    ),
                    if (entityTypeLabel != null)
                      TextSpan(
                        text: ' ($entityTypeLabel)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                  ],
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

  IconData _iconForEntityType(String? entityType) {
    switch (entityType?.toUpperCase()) {
      case 'PERSON':
        return PhosphorIcons.user(PhosphorIconsStyle.regular);
      case 'ORG':
        return PhosphorIcons.buildings(PhosphorIconsStyle.regular);
      case 'LOCATION':
        return PhosphorIcons.mapPin(PhosphorIconsStyle.regular);
      case 'EVENT':
        return PhosphorIcons.calendarBlank(PhosphorIconsStyle.regular);
      case 'PRODUCT':
        return PhosphorIcons.package_(PhosphorIconsStyle.regular);
      default:
        return PhosphorIcons.hash(PhosphorIconsStyle.regular);
    }
  }
}
