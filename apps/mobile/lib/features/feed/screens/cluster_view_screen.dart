import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/article_preview_modal.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import '../widgets/animated_feed_card.dart';
import '../widgets/feed_card.dart';
import '../widgets/swipe_to_open_card.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../gamification/providers/streak_provider.dart';
import '../../saved/providers/collections_provider.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../sources/providers/sources_providers.dart';

/// Immersive view showing all articles in a topic cluster or theme filter.
///
/// Two modes:
/// - **Cluster mode**: pass [representativeArticle] + [hiddenIds] to fetch
///   hidden articles by ID.
/// - **Theme filter mode**: pass [filteredArticles] directly for instant
///   local display (no API call).
class ClusterViewScreen extends ConsumerStatefulWidget {
  final String topicSlug;
  final Content? representativeArticle;
  final List<String> hiddenIds;
  final List<Content>? filteredArticles;

  const ClusterViewScreen({
    super.key,
    required this.topicSlug,
    this.representativeArticle,
    this.hiddenIds = const [],
    this.filteredArticles,
  });

  @override
  ConsumerState<ClusterViewScreen> createState() => _ClusterViewScreenState();
}

class _ClusterViewScreenState extends ConsumerState<ClusterViewScreen> {
  List<Content> _hiddenArticles = [];
  bool _isLoading = true;

  bool get _isFilterMode => widget.filteredArticles != null;

  @override
  void initState() {
    super.initState();
    if (_isFilterMode) {
      _isLoading = false;
    } else {
      _fetchHiddenArticles();
    }
  }

  Future<void> _fetchHiddenArticles() async {
    if (widget.hiddenIds.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(feedRepositoryProvider);
    final futures = widget.hiddenIds.map((id) => repo.getContent(id));
    final results = await Future.wait(futures);

    if (mounted) {
      setState(() {
        _hiddenArticles = results.whereType<Content>().toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _showArticleModal(Content content) async {
    if (mounted) {
      ref.read(feedProvider.notifier).markContentAsConsumed(content);

      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          ref.read(streakProvider.notifier).refreshSilent();
        }
      });
    }

    final sources = ref.read(userSourcesProvider).valueOrNull ?? [];
    final isPremium =
        sources.any((s) => s.id == content.source.id && s.hasSubscription);
    if (isPremium && content.url.isNotEmpty) {
      final uri = Uri.tryParse(content.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      launchUrl(Uri.parse(content.url));
      return;
    }

    final updated = await context.push<Content?>(
      '/feed/content/${content.id}',
      extra: content,
    );
    if (updated != null) {
      ref.read(feedProvider.notifier).updateContent(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final topicLabel = getTopicLabel(widget.topicSlug);
    final macroTheme = getTopicMacroTheme(widget.topicSlug);
    final emoji = macroTheme != null ? getMacroThemeEmoji(macroTheme) : '';
    final allArticles = _isFilterMode
        ? widget.filteredArticles!
        : [
            widget.representativeArticle!,
            ..._hiddenArticles,
          ];
    final followedTopics =
        ref.watch(customTopicsProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${emoji.isNotEmpty ? '$emoji ' : ''}$topicLabel',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : allArticles.isEmpty
              ? Center(
                  child: Text(
                    'Aucun article sur ce thème',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space4,
                  ),
                  itemCount: allArticles.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FacteurSpacing.space3),
                  itemBuilder: (context, index) {
                    final article = allArticles[index];
                    final isConsumed = ref
                        .read(feedProvider.notifier)
                        .isContentConsumed(article.id);

                    return SwipeToOpenCard(
                      onSwipeOpen: () => _showArticleModal(article),
                      onSwipeDismiss: () =>
                          TopicChip.showArticleSheet(context, article),
                      child: AnimatedFeedCard(
                        isConsumed: isConsumed,
                        child: FeedCard(
                          content: article,
                          onTap: () => _showArticleModal(article),
                          onSourceTap: () {
                            ref.read(feedProvider.notifier).setSource(article.source.id);
                            Navigator.of(context).pop();
                          },
                          onLongPressStart: (_) =>
                              ArticlePreviewOverlay.show(context, article),
                          onLongPressMoveUpdate: (details) =>
                              ArticlePreviewOverlay.updateScroll(
                            details.localOffsetFromOrigin.dy,
                          ),
                          onLongPressEnd: (_) =>
                              ArticlePreviewOverlay.dismiss(),
                          onLike: () {
                            final wasLiked = article.isLiked;
                            ref
                                .read(feedProvider.notifier)
                                .toggleLike(article);
                            NotificationService.showInfo(
                              wasLiked
                                  ? 'Retiré de vos contenus favoris'
                                  : 'Ajouté à vos contenus favoris',
                            );
                            ref.invalidate(collectionsProvider);
                          },
                          isLiked: article.isLiked,
                          onSave: () async {
                            final wasSaved = article.isSaved;
                            ref
                                .read(feedProvider.notifier)
                                .toggleSave(article);
                            if (!wasSaved) {
                              final defaultCol =
                                  ref.read(defaultCollectionProvider);
                              if (defaultCol != null) {
                                final colRepo =
                                    ref.read(collectionsRepositoryProvider);
                                await colRepo.addToCollection(
                                    defaultCol.id, article.id);
                                ref.invalidate(collectionsProvider);
                              }
                              if (context.mounted) {
                                CollectionPickerSheet.show(
                                    context, article.id);
                              }
                            }
                          },
                          isSaved: article.isSaved,
                          onSaveLongPress: () =>
                              CollectionPickerSheet.show(context, article.id),
                          topicChipWidget: TopicChip(
                            content: article,
                            isFollowed: article.topics.isNotEmpty &&
                                followedTopics.any((t) =>
                                    t.slugParent ==
                                        article.topics.first ||
                                    t.name.toLowerCase() ==
                                        getTopicLabel(article.topics.first)
                                            .toLowerCase()),
                            onTap: article.topics.isNotEmpty
                                ? () {
                                    ref
                                        .read(feedProvider.notifier)
                                        .setTopic(article.topics.first);
                                    Navigator.of(context).pop();
                                  }
                                : null,
                          ),
                          clusterChipWidget: const SizedBox.shrink(),
                          isSerene:
                              ref.watch(sereinToggleProvider).enabled,
                          onReportNotSerene: () async {
                            try {
                              final feedRepo =
                                  ref.read(feedRepositoryProvider);
                              await feedRepo.reportNotSerene(article.id);
                              HapticFeedback.lightImpact();
                              NotificationService.showSuccess(
                                  'Merci, nous en prenons note');
                            } catch (e) {
                              NotificationService.showError(
                                  'Erreur lors du signalement');
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
