import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../feed/widgets/feed_card.dart';
import '../providers/collections_provider.dart';
import '../widgets/collection_dialogs.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  final String collectionId;

  const CollectionDetailScreen({super.key, required this.collectionId});

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(collectionDetailProvider(widget.collectionId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync =
        ref.watch(collectionDetailProvider(widget.collectionId));
    final collectionsAsync = ref.watch(collectionsProvider);
    final colors = context.facteurColors;

    // Find collection name
    final collectionName = collectionsAsync.whenOrNull(
      data: (cols) =>
          cols
              .where((c) => c.id == widget.collectionId)
              .firstOrNull
              ?.name ??
          'Collection',
    ) ?? 'Collection';

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(collectionName),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              PhosphorIcons.dotsThreeVertical(PhosphorIconsStyle.regular),
              color: colors.textPrimary,
            ),
            color: colors.backgroundSecondary,
            onSelected: (value) async {
              if (value == 'rename') {
                final newName = await showRenameCollectionDialog(
                    context, collectionName);
                if (newName != null && newName.isNotEmpty) {
                  await ref
                      .read(collectionsProvider.notifier)
                      .updateCollection(widget.collectionId, newName);
                }
              } else if (value == 'delete') {
                final confirmed = await showDeleteCollectionConfirmation(
                    context, collectionName);
                if (confirmed) {
                  await ref
                      .read(collectionsProvider.notifier)
                      .deleteCollection(widget.collectionId);
                  if (mounted) Navigator.pop(context);
                  NotificationService.showInfo('Collection supprimée');
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(
                        PhosphorIcons.pencilSimple(
                            PhosphorIconsStyle.regular),
                        size: 20,
                        color: colors.textPrimary),
                    const SizedBox(width: 12),
                    Text('Renommer',
                        style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(PhosphorIcons.trash(PhosphorIconsStyle.regular),
                        size: 20, color: colors.error),
                    const SizedBox(width: 12),
                    Text('Supprimer',
                        style: TextStyle(color: colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.duotone),
                    size: 64,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun article dans cette collection',
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sauvegardez des articles et ajoutez-les ici',
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          final notifier = ref.read(
              collectionDetailProvider(widget.collectionId).notifier);

          return RefreshIndicator(
            onRefresh: notifier.refresh,
            color: colors.primary,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Header: count + sort
                SliverToBoxAdapter(
                  child: _SortHeader(
                    itemCount: items.length,
                    currentSort: notifier.sort,
                    colors: colors,
                    onSortChanged: (sort) => notifier.changeSort(sort),
                  ),
                ),
                // Articles list
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == items.length) {
                          if (notifier.hasNext) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child:
                                    CircularProgressIndicator.adaptive(),
                              ),
                            );
                          }
                          return const SizedBox(height: 64);
                        }

                        final content = items[index];
                        return Dismissible(
                          key: ValueKey(content.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: colors.error.withValues(alpha: 0.1),
                            child: Icon(
                              PhosphorIcons.bookmarkSimple(
                                  PhosphorIconsStyle.regular),
                              color: colors.error,
                            ),
                          ),
                          onDismissed: (_) {
                            notifier.removeItem(content.id);
                            HapticFeedback.mediumImpact();
                            NotificationService.showInfo(
                                'Retiré de la collection');
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: FeedCard(
                              content: content,
                              isSaved: content.isSaved,
                              isLiked: content.isLiked,
                              onTap: () => context.pushNamed(
                                RouteNames.contentDetail,
                                pathParameters: {'id': content.id},
                                extra: content,
                              ),
                              onLongPressStart: (_) =>
                                  ArticlePreviewOverlay.show(
                                      context, content),
                              onLongPressMoveUpdate: (details) =>
                                  ArticlePreviewOverlay.updateScroll(
                                      details
                                          .localOffsetFromOrigin.dy),
                              onLongPressEnd: (_) =>
                                  ArticlePreviewOverlay.dismiss(),
                              onSave: () {
                                notifier.removeItem(content.id);
                                HapticFeedback.mediumImpact();
                                NotificationService.showInfo(
                                    'Retiré de la collection');
                              },
                            ),
                          ),
                        );
                      },
                      childCount: items.length + 1,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () =>
            Center(child: CircularProgressIndicator(color: colors.primary)),
        error: (err, _) => Center(child: Text('Erreur: $err')),
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  final int itemCount;
  final String currentSort;
  final FacteurColors colors;
  final ValueChanged<String> onSortChanged;

  const _SortHeader({
    required this.itemCount,
    required this.currentSort,
    required this.colors,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Text(
            '$itemCount ${itemCount == 1 ? 'article' : 'articles'}',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: currentSort,
            onSelected: onSortChanged,
            color: colors.backgroundSecondary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _sortLabel(currentSort),
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(
                  PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textSecondary,
                ),
              ],
            ),
            itemBuilder: (context) => [
              _sortItem('recent', 'Plus récents'),
              _sortItem('oldest', 'Plus anciens'),
              _sortItem('source', 'Par source'),
              _sortItem('theme', 'Par thème'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: value == currentSort ? FontWeight.w600 : FontWeight.w400,
          )),
    );
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case 'oldest':
        return 'Plus anciens';
      case 'source':
        return 'Par source';
      case 'theme':
        return 'Par thème';
      default:
        return 'Plus récents';
    }
  }
}
