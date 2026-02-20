import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../feed/widgets/feed_card.dart';
import '../providers/saved_feed_provider.dart';

/// Écran "Tous les articles" sauvegardés (liste plate chronologique).
class SavedAllScreen extends ConsumerStatefulWidget {
  const SavedAllScreen({super.key});

  @override
  ConsumerState<SavedAllScreen> createState() => _SavedAllScreenState();
}

class _SavedAllScreenState extends ConsumerState<SavedAllScreen> {
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
      ref.read(savedFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(savedFeedProvider);
    final colors = context.facteurColors;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Tous les articles'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(savedFeedProvider.notifier).refresh(),
        color: colors.primary,
        child: feedAsync.when(
          data: (contents) {
            if (contents.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.bookmarkSimple(
                          PhosphorIconsStyle.duotone),
                      size: 64,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune sauvegarde',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              );
            }

            return CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == contents.length) {
                          final notifier =
                              ref.read(savedFeedProvider.notifier);
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

                        final content = contents[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FeedCard(
                            content: content,
                            isSaved: true,
                            isLiked: content.isLiked,
                            onTap: () async {
                              final uri = Uri.parse(content.url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.inAppWebView);
                              } else {
                                NotificationService.showError(
                                    'Impossible d\'ouvrir le lien');
                              }
                            },
                            onLongPressStart: (_) =>
                                ArticlePreviewOverlay.show(
                                    context, content),
                            onLongPressMoveUpdate: (details) =>
                                ArticlePreviewOverlay.updateScroll(
                                    details.localOffsetFromOrigin.dy),
                            onLongPressEnd: (_) =>
                                ArticlePreviewOverlay.dismiss(),
                            onSave: () async {
                              if (!mounted) return;
                              await ref
                                  .read(savedFeedProvider.notifier)
                                  .toggleSave(content);
                            },
                          ),
                        );
                      },
                      childCount: contents.length + 1,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => Center(
              child: CircularProgressIndicator(color: colors.primary)),
          error: (err, stack) => Center(child: Text('Erreur: $err')),
        ),
      ),
    );
  }
}
