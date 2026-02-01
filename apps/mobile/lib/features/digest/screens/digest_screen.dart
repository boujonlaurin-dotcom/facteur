import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../sources/models/source_model.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../models/digest_models.dart';
import '../providers/digest_provider.dart';
import '../widgets/digest_card.dart';
import '../widgets/not_interested_sheet.dart';
import '../widgets/digest_welcome_modal.dart';

/// Main digest screen showing the daily "Essentiel" with 5 articles
class DigestScreen extends ConsumerStatefulWidget {
  const DigestScreen({super.key});

  @override
  ConsumerState<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends ConsumerState<DigestScreen> {
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    _checkFirstTimeWelcome();
  }

  Future<void> _checkFirstTimeWelcome() async {
    // Check for 'first' query param (from onboarding)
    final uri = GoRouterState.of(context).uri;
    final isFirstTime = uri.queryParameters['first'] == 'true';

    if (isFirstTime) {
      // Also check shared preferences to ensure we only show once
      final shouldShow = await DigestWelcomeModal.shouldShowWelcome();
      if (shouldShow && mounted) {
        setState(() {
          _showWelcome = true;
        });
      }
    }
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });
    // Clear the query param from URL
    context.go(RoutePaths.digest);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final digestAsync = ref.watch(digestProvider);

    // Listen for completion to navigate to closure screen
    ref.listen(digestProvider, (previous, next) {
      final prevDigest = previous?.value;
      final nextDigest = next.value;

      if (prevDigest != null &&
          nextDigest != null &&
          !prevDigest.isCompleted &&
          nextDigest.isCompleted) {
        // Navigate to closure screen when digest completes
        context.go(RoutePaths.digestClosure, extra: nextDigest.digestId);
      }
    });

    return Stack(
      children: [
        Scaffold(
          backgroundColor: colors.backgroundPrimary,
          appBar: AppBar(
            backgroundColor: colors.backgroundPrimary,
            elevation: 0,
            centerTitle: false,
            title: Text(
              'Votre Essentiel',
              style: TextStyle(
                fontFamily: 'Fraunces', // Use Fraunces font family
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            leading: const Padding(
              padding: EdgeInsets.only(left: 16),
              child: StreakIndicator(),
            ),
            leadingWidth: 56,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: _buildProgressBar(digestAsync, colors),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await ref.read(digestProvider.notifier).refreshDigest();
            },
            color: colors.primary,
            child: digestAsync.when(
              data: (digest) {
                if (digest == null) {
                  return _buildEmptyState(colors);
                }

                final items = digest.items;
                if (items.isEmpty) {
                  return _buildEmptyState(colors);
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(FacteurSpacing.space3),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: FacteurSpacing.space3),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return DigestCard(
                      item: item,
                      onTap: () => _openDetail(context, item),
                      onAction: (action) =>
                          _handleAction(context, ref, item, action),
                    );
                  },
                );
              },
              loading: () => _buildLoadingState(colors),
              error: (error, stack) =>
                  _buildErrorState(context, ref, colors, error),
            ),
          ),
        ),
        // Welcome modal overlay for first-time users
        if (_showWelcome)
          Positioned.fill(
            child: DigestWelcomeModal(
              onDismiss: _dismissWelcome,
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar(
      AsyncValue<DigestResponse?> digestAsync, FacteurColors colors) {
    final processedCount = digestAsync.value?.items
            .where((item) => item.isRead || item.isDismissed)
            .length ??
        0;
    final totalCount = digestAsync.value?.items.length ?? 5;
    final progress = totalCount > 0 ? processedCount / totalCount : 0.0;

    return Container(
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: colors.backgroundSecondary,
          valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, DigestItem item) {
    // Navigate to content detail screen
    final content = Content(
      id: item.contentId,
      title: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      description: item.description,
      contentType: _mapContentType(item.contentType),
      durationSeconds: item.durationSeconds,
      publishedAt: item.publishedAt,
      source: Source(
        id: item.contentId, // Use contentId as fallback for source id
        name: item.source.name,
        type: _mapSourceType(item.contentType),
        logoUrl: item.source.logoUrl,
        theme: item.source.theme,
      ),
    );
    context.push('/feed/content/${item.contentId}', extra: content);
  }

  void _handleAction(
      BuildContext context, WidgetRef ref, DigestItem item, String action) {
    if (action == 'not_interested') {
      _showNotInterestedSheet(context, ref, item);
    } else {
      ref.read(digestProvider.notifier).applyAction(item.contentId, action);
    }
  }

  Future<void> _showNotInterestedSheet(
      BuildContext context, WidgetRef ref, DigestItem item) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotInterestedSheet(
        item: item,
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );

    if (confirmed == true) {
      ref
          .read(digestProvider.notifier)
          .applyAction(item.contentId, 'not_interested');
    }
  }

  Widget _buildLoadingState(FacteurColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: colors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Chargement de votre Essentiel...',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FacteurColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.newspaper(),
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun article aujourd\'hui',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Revenez plus tard pour découvrir votre Essentiel',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, WidgetRef ref, FacteurColors colors, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.warningCircle(),
            size: 64,
            color: colors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Erreur de chargement',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.read(digestProvider.notifier).refreshDigest(),
            icon: Icon(PhosphorIcons.arrowClockwise()),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  ContentType _mapContentType(dynamic type) {
    if (type == null) return ContentType.article;
    final str = type.toString().toLowerCase();
    switch (str) {
      case 'video':
        return ContentType.video;
      case 'audio':
        return ContentType.audio;
      case 'youtube':
        return ContentType.youtube;
      default:
        return ContentType.article;
    }
  }

  SourceType _mapSourceType(dynamic type) {
    if (type == null) return SourceType.article;
    final str = type.toString().toLowerCase();
    switch (str) {
      case 'video':
        return SourceType.video;
      case 'audio':
        return SourceType.podcast;
      case 'youtube':
        return SourceType.youtube;
      default:
        return SourceType.article;
    }
  }
}
