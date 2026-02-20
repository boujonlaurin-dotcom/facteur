import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../models/collection_model.dart';
import '../providers/collections_provider.dart';
import '../providers/saved_feed_provider.dart';
import '../providers/weekly_notes_provider.dart';
import '../widgets/collection_dialogs.dart';
import '../widgets/collection_grid_cell.dart';
import '../widgets/collection_picker_sheet.dart';

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  Future<void> _refresh() async {
    await Future.wait([
      ref.read(savedFeedProvider.notifier).refresh(),
      ref.read(collectionsProvider.notifier).refresh(),
    ]);
    ref.invalidate(weeklyNotesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final savedAsync = ref.watch(savedFeedProvider);
    final collectionsAsync = ref.watch(collectionsProvider);
    final weeklyNotesAsync = ref.watch(weeklyNotesProvider);
    final colors = context.facteurColors;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mes sauvegardes'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: colors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Section 1: Collections header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'Collections',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Section 1: Collections grid
            collectionsAsync.when(
              data: (collections) => _buildCollectionsGrid(
                collections,
                savedAsync.value ?? [],
                colors,
              ),
              loading: () => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: colors.primary),
                  ),
                ),
              ),
              error: (_, __) => _buildCollectionsGrid(
                [],
                savedAsync.value ?? [],
                colors,
              ),
            ),

            // Section 2: Tes pensées de la semaine
            weeklyNotesAsync.when(
              data: (weeklyNotes) {
                if (weeklyNotes.isEmpty) return const SliverToBoxAdapter();
                return SliverToBoxAdapter(
                  child: _WeeklyNotesSection(
                    articles: weeklyNotes,
                    colors: colors,
                    onToggleSave: (content) {
                      ref.read(savedFeedProvider.notifier).toggleSave(content);
                    },
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(),
              error: (_, __) => const SliverToBoxAdapter(),
            ),

            // Section 3: Récemment sauvegardés (FeedCards)
            savedAsync.when(
              data: (saved) {
                if (saved.isEmpty) return const SliverToBoxAdapter();
                final recents = saved.take(5).toList();
                return SliverToBoxAdapter(
                  child: _RecentSavedSection(
                    articles: recents,
                    colors: colors,
                    onToggleSave: (content) {
                      ref.read(savedFeedProvider.notifier).toggleSave(content);
                    },
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(),
              error: (_, __) => const SliverToBoxAdapter(),
            ),

            // Bottom spacing
            const SliverToBoxAdapter(child: SizedBox(height: 64)),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionsGrid(
    List<Collection> collections,
    List<Content> allSaved,
    FacteurColors colors,
  ) {
    final totalSaved = allSaved.length;
    final readCount =
        allSaved.where((c) => c.status == ContentStatus.consumed).length;
    final thumbnails = allSaved.take(4).map((c) => c.thumbnailUrl).toList();

    if (totalSaved == 0 && collections.isEmpty) {
      return SliverFillRemaining(child: _EmptyState(colors: colors));
    }

    // "Tous les articles" + user collections + "Nouvelle collection"
    final itemCount = 1 + collections.length + 1;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, index) {
            // Index 0: "Tous les articles"
            if (index == 0) {
              return AllArticlesGridCell(
                totalCount: totalSaved,
                readCount: readCount,
                thumbnails: thumbnails,
                onTap: () => context.pushNamed('saved-all'),
              );
            }

            // Last item: "Nouvelle collection"
            if (index == itemCount - 1) {
              return NewCollectionCell(
                onTap: () => _createCollection(),
              );
            }

            // User collections
            final collection = collections[index - 1];
            return CollectionGridCell(
              collection: collection,
              onTap: () => context.pushNamed(
                'collection-detail',
                pathParameters: {'id': collection.id},
              ),
              onLongPress: () => _showCollectionMenu(collection),
            );
          },
          childCount: itemCount,
        ),
      ),
    );
  }

  // Use the widget's own context (not builder context) for dialogs
  Future<void> _createCollection() async {
    final name = await showCreateCollectionDialog(context);
    if (name != null && name.isNotEmpty) {
      try {
        await ref.read(collectionsProvider.notifier).createCollection(name);
        HapticFeedback.mediumImpact();
        NotificationService.showInfo('Collection "$name" créée');
      } catch (e) {
        NotificationService.showError(
            'Erreur: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  void _showCollectionMenu(Collection collection) {
    final colors = context.facteurColors;
    HapticFeedback.mediumImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                  PhosphorIcons.pencilSimple(PhosphorIconsStyle.regular),
                  color: colors.textPrimary),
              title: Text('Renommer',
                  style: TextStyle(color: colors.textPrimary)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final newName = await showRenameCollectionDialog(
                    context, collection.name);
                if (newName != null && newName.isNotEmpty) {
                  await ref
                      .read(collectionsProvider.notifier)
                      .updateCollection(collection.id, newName);
                }
              },
            ),
            ListTile(
              leading: Icon(
                  PhosphorIcons.trash(PhosphorIconsStyle.regular),
                  color: colors.error),
              title:
                  Text('Supprimer', style: TextStyle(color: colors.error)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDeleteCollectionConfirmation(
                    context, collection.name);
                if (confirmed) {
                  await ref
                      .read(collectionsProvider.notifier)
                      .deleteCollection(collection.id);
                  NotificationService.showInfo('Collection supprimée');
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Section "Tes pensées de la semaine" — articles with notes from last 7 days.
class _WeeklyNotesSection extends ConsumerWidget {
  final List<Content> articles;
  final FacteurColors colors;
  final ValueChanged<Content> onToggleSave;

  const _WeeklyNotesSection({
    required this.articles,
    required this.colors,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Divider(
          color: colors.border.withValues(alpha: 0.3),
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Tes pensées de la semaine',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        ...articles.map((article) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: FeedCard(
                content: article,
                isSaved: article.isSaved,
                isLiked: article.isLiked,
                onTap: () => context.pushNamed(
                  RouteNames.contentDetail,
                  pathParameters: {'id': article.id},
                  extra: article,
                ),
                onLongPressStart: (_) =>
                    ArticlePreviewOverlay.show(context, article),
                onLongPressMoveUpdate: (details) =>
                    ArticlePreviewOverlay.updateScroll(
                        details.localOffsetFromOrigin.dy),
                onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
                onSave: () {
                  onToggleSave(article);
                  HapticFeedback.mediumImpact();
                },
                onSaveLongPress: () =>
                    CollectionPickerSheet.show(context, article.id),
              ),
            )),
      ],
    );
  }
}

/// Section "Récemment sauvegardés" avec des FeedCards complètes.
class _RecentSavedSection extends ConsumerWidget {
  final List<Content> articles;
  final FacteurColors colors;
  final ValueChanged<Content> onToggleSave;

  const _RecentSavedSection({
    required this.articles,
    required this.colors,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Divider(
          color: colors.border.withValues(alpha: 0.3),
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Récents',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...articles.map((article) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: FeedCard(
                content: article,
                isSaved: article.isSaved,
                isLiked: article.isLiked,
                onTap: () => context.pushNamed(
                  RouteNames.contentDetail,
                  pathParameters: {'id': article.id},
                  extra: article,
                ),
                onLongPressStart: (_) =>
                    ArticlePreviewOverlay.show(context, article),
                onLongPressMoveUpdate: (details) =>
                    ArticlePreviewOverlay.updateScroll(
                        details.localOffsetFromOrigin.dy),
                onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
                onSave: () {
                  onToggleSave(article);
                  HapticFeedback.mediumImpact();
                },
                onSaveLongPress: () =>
                    CollectionPickerSheet.show(context, article.id),
              ),
            )),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final FacteurColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
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
            'Aucune sauvegarde',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Sauvegardez des articles depuis le feed ou le digest',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
