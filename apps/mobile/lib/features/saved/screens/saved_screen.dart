import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../feed/models/content_model.dart';
import '../models/collection_model.dart';
import '../providers/collections_provider.dart';
import '../providers/saved_feed_provider.dart';
import '../providers/weekly_notes_provider.dart';
import '../widgets/collection_dialogs.dart';

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
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        automaticallyImplyLeading: false,
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

    if (totalSaved == 0 && collections.isEmpty) {
      return SliverFillRemaining(child: _EmptyState(colors: colors));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          child: Column(
            children: [
              _CollectionListTile(
                icon: PhosphorIcons.bookmarksSimple(PhosphorIconsStyle.fill),
                iconColor: colors.primary,
                title: 'Tous les articles',
                totalCount: totalSaved,
                unreadCount: totalSaved - readCount,
                colors: colors,
                onTap: () => context.pushNamed('saved-all'),
              ),
              for (final c in collections) ...[
                _Divider(colors: colors),
                _CollectionListTile(
                  icon: c.isLikedCollection
                      ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                      : PhosphorIcons.folderSimple(PhosphorIconsStyle.fill),
                  iconColor: c.isLikedCollection
                      ? colors.error
                      : colors.textSecondary,
                  title: c.name,
                  totalCount: c.itemCount,
                  unreadCount: c.itemCount - c.readCount,
                  colors: colors,
                  onTap: () => context.pushNamed(
                    'collection-detail',
                    pathParameters: {'id': c.id},
                  ),
                  onLongPress: () => _showCollectionMenu(c),
                ),
              ],
              _Divider(colors: colors),
              _NewCollectionTile(
                colors: colors,
                onTap: _createCollection,
              ),
            ],
          ),
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
    // System collections (default + liked) cannot be renamed or deleted
    if (collection.isDefault || collection.isLikedCollection) {
      return;
    }

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
                color: colors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                  PhosphorIcons.pencilSimple(PhosphorIconsStyle.regular),
                  color: colors.textPrimary),
              title:
                  Text('Renommer', style: TextStyle(color: colors.textPrimary)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final newName =
                    await showRenameCollectionDialog(context, collection.name);
                if (newName != null && newName.isNotEmpty) {
                  await ref
                      .read(collectionsProvider.notifier)
                      .updateCollection(collection.id, newName);
                }
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.trash(PhosphorIconsStyle.regular),
                  color: colors.error),
              title: Text('Supprimer', style: TextStyle(color: colors.error)),
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
    return _SavedListBlock(
      titleIcon: PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
      title: 'Tes pensées de la semaine',
      articles: articles,
      colors: colors,
      onToggleSave: onToggleSave,
    );
  }
}

/// Section "Récemment sauvegardés" — liste compacte sans images.
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
    return _SavedListBlock(
      title: 'Récents',
      articles: articles,
      colors: colors,
      onToggleSave: onToggleSave,
    );
  }
}

/// Card-wrapped list of saved articles (no thumbnails), aligned with the
/// Réglages design system.
class _SavedListBlock extends StatelessWidget {
  final String title;
  final IconData? titleIcon;
  final List<Content> articles;
  final FacteurColors colors;
  final ValueChanged<Content> onToggleSave;

  const _SavedListBlock({
    required this.title,
    this.titleIcon,
    required this.articles,
    required this.colors,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: 16, color: colors.primary),
                const SizedBox(width: 6),
              ],
              Text(
                title,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.surfaceElevated),
            ),
            child: Column(
              children: [
                for (var i = 0; i < articles.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.surfaceElevated,
                      indent: 16,
                      endIndent: 16,
                    ),
                  _SavedListTile(
                    article: articles[i],
                    colors: colors,
                    onToggleSave: () {
                      onToggleSave(articles[i]);
                      HapticFeedback.mediumImpact();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedListTile extends StatelessWidget {
  final Content article;
  final FacteurColors colors;
  final VoidCallback onToggleSave;

  const _SavedListTile({
    required this.article,
    required this.colors,
    required this.onToggleSave,
  });

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}sem';
    if (diff.inDays >= 1) return '${diff.inDays}j';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'À l\'instant';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.contentDetail,
        pathParameters: {'id': article.id},
        extra: article,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${article.source.name} · ${_relativeDate(article.publishedAt)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onToggleSave,
              icon: Icon(
                article.isSaved
                    ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                    : PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.regular),
                size: 20,
                color: article.isSaved ? colors.primary : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
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

/// Ligne de liste pour une collection : icône, titre, compteurs.
class _CollectionListTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final int totalCount;
  final int unreadCount;
  final FacteurColors colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CollectionListTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.totalCount,
    required this.unreadCount,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final showUnread = unreadCount > 0 && totalCount > 0;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalCount == 0
                        ? 'Vide'
                        : '$totalCount ${totalCount == 1 ? 'article' : 'articles'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (showUnread)
              Padding(
                padding: const EdgeInsets.only(right: FacteurSpacing.space2),
                child: Text(
                  '$unreadCount non lu${unreadCount > 1 ? 's' : ''}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
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

class _NewCollectionTile extends StatelessWidget {
  final FacteurColors colors;
  final VoidCallback onTap;

  const _NewCollectionTile({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withOpacity(0.10),
              ),
              alignment: Alignment.center,
              child: Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 16,
              ),
            ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Text(
                'Nouvelle collection',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final FacteurColors colors;
  const _Divider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: colors.surfaceElevated,
      indent: 16,
      endIndent: 16,
    );
  }
}
