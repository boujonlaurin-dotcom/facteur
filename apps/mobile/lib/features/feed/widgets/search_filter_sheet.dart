import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/search_history_provider.dart';
import '../providers/trending_topics_provider.dart';

class SearchFilterSheet extends ConsumerStatefulWidget {
  final String? currentKeyword;
  final ValueChanged<String> onSearchSubmitted;

  const SearchFilterSheet({
    super.key,
    this.currentKeyword,
    required this.onSearchSubmitted,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentKeyword,
    required ValueChanged<String> onSearchSubmitted,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SearchFilterSheet(
        currentKeyword: currentKeyword,
        onSearchSubmitted: onSearchSubmitted,
      ),
    );
  }

  @override
  ConsumerState<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<SearchFilterSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.currentKeyword != null) {
      _searchController.text = widget.currentKeyword!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    ref.read(searchHistoryProvider.notifier).addSearch(trimmed);
    Navigator.of(context).pop();
    widget.onSearchSubmitted(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final history = ref.watch(searchHistoryProvider);
    final trendingAsync = ref.watch(trendingTopicsProvider);
    final hasQuery = _searchController.text.trim().isNotEmpty;

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
                  'Rechercher',
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
                onChanged: (_) => setState(() {}),
                onSubmitted: _submitSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Rechercher un sujet...',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 14,
                  ),
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
                            setState(() {});
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

            // Cold start content (when no query typed)
            if (!hasQuery)
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  shrinkWrap: true,
                  children: [
                    // Recent searches
                    if (history.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'RECHERCHES RÉCENTES',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colors.textTertiary,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            GestureDetector(
                              onTap: () => ref
                                  .read(searchHistoryProvider.notifier)
                                  .clearHistory(),
                              child: Text(
                                'Effacer',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: history.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final query = history[index];
                            return _HistoryChip(
                              label: query,
                              colors: colors,
                              onTap: () => _submitSearch(query),
                              onDelete: () => ref
                                  .read(searchHistoryProvider.notifier)
                                  .removeSearch(query),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Trending topics
                    trendingAsync.when(
                      data: (topics) {
                        if (topics.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 8, bottom: 10),
                              child: Text(
                                'SUJETS DU MOMENT',
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: topics.map((topic) {
                                return _TrendingChip(
                                  topic: topic,
                                  colors: colors,
                                  onTap: () {
                                    final keyword =
                                        _extractKeyword(topic.label);
                                    _submitSearch(keyword);
                                  },
                                );
                              }).toList(),
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _extractKeyword(String title) {
    if (title.length <= 40) return title;
    final truncated = title.substring(0, 40);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > 20) return truncated.substring(0, lastSpace);
    return truncated;
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
              PhosphorIcons.clockCounterClockwise(
                  PhosphorIconsStyle.regular),
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
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
              ),
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
