import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import '../widgets/feed_card.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final topicLabel = getTopicLabel(widget.topicSlug);
    final macroTheme = getTopicMacroTheme(widget.topicSlug);
    final emoji = macroTheme != null ? getMacroThemeEmoji(macroTheme) : '';
    final followedTopics = ref.watch(customTopicsProvider).valueOrNull ?? [];

    final allArticles = _isFilterMode
        ? widget.filteredArticles!
        : [
            widget.representativeArticle!,
            ..._hiddenArticles,
          ];

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
                    return FeedCard(
                      content: article,
                      isSaved: article.isSaved,
                      isLiked: article.isLiked,
                      topicChipWidget: TopicChip(
                        content: article,
                        isFollowed: article.topics.isNotEmpty &&
                            followedTopics.any((t) =>
                                t.slugParent == article.topics.first ||
                                t.name.toLowerCase() ==
                                    getTopicLabel(article.topics.first)
                                        .toLowerCase()),
                      ),
                      onTap: () {
                        context.pushNamed(
                          RouteNames.contentDetail,
                          pathParameters: {'id': article.id},
                          extra: article,
                        );
                      },
                    );
                  },
                ),
    );
  }
}
