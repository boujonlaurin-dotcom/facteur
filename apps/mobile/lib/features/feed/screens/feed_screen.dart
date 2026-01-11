import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../providers/feed_provider.dart';
import '../widgets/welcome_banner.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../../widgets/design/facteur_button.dart';
import '../../../config/constants.dart';
import '../models/content_model.dart';
import '../widgets/feed_card.dart';
import '../widgets/filter_bar.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../gamification/providers/streak_provider.dart';

/// Écran principal du feed
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _showWelcome = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Lire le paramètre welcome de l'URL
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['welcome'] == 'true' && !_showWelcome) {
      setState(() {
        _showWelcome = true;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more when reading bottom
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });

    // Nettoyer l'URL (enlever le paramètre welcome)
    context.go(RoutePaths.feed);
  }

  Future<void> _refresh() async {
    // Explicit refresh call
    return ref.read(feedProvider.notifier).refresh();
  }

  void _showMoreOptions(BuildContext context, Content content) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.facteurColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final colors = context.facteurColors;
        // ignore: unused_local_variable
        final textTheme = Theme.of(context).textTheme;

        final sourceName = content.source.name;
        final topicName = content.source.theme;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                  color: colors.textPrimary,
                ),
                title: RichText(
                  text: TextSpan(
                    text: 'Voir moins de ',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
                    children: [
                      TextSpan(
                        text: sourceName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _hideContent(content, HiddenReason.source);
                },
              ),
              if (topicName != null && topicName.isNotEmpty) ...[
                const Divider(),
                ListTile(
                  leading: Icon(
                    PhosphorIcons.hash(PhosphorIconsStyle.regular),
                    color: colors.textPrimary,
                  ),
                  title: RichText(
                    text: TextSpan(
                      text: 'Voir moins sur le sujet ',
                      style: textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                      children: [
                        TextSpan(
                          text: topicName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _hideContent(content, HiddenReason.topic);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _hideContent(Content content, HiddenReason reason) {
    ref.read(feedProvider.notifier).hideContent(content, reason);

    // Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Contenu masqué"),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final feedAsync = ref.watch(feedProvider);
    final colors = context.facteurColors;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: colors.primary,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space6,
                          vertical: FacteurSpacing.space4,
                        ),
                        child: Center(
                          child: const FacteurLogo(size: 32),
                        ),
                      ),
                    ),

                    // Salutation
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Bonjour ${authState.user?.email?.split('@')[0] ?? 'Vous'},',
                                style:
                                    Theme.of(context).textTheme.displayMedium,
                              ),
                            ),
                            const StreakIndicator(),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Voici votre tournée du jour.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: FilterBar(
                        selectedFilter:
                            ref.read(feedProvider.notifier).selectedFilter,
                        onFilterChanged: (String? filter) {
                          ref.read(feedProvider.notifier).setFilter(filter);
                        },
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // Feed Content
                    feedAsync.when(
                      data: (contents) {
                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                // Add loading indicator at the bottom
                                if (index == contents.length) {
                                  // Check if we are loading more
                                  // Since we don't watch isLoadingMore directly to avoid full rebuilds,
                                  // we can check if notifier has next page.
                                  // If hasNext is true, we might show a spinner or nothing (it will trigger load).
                                  // Let's verify with the provider logic.
                                  // For better UX, we can show a small spinner if we are at the end.
                                  // Note: ref.read is typically okay here, but a watch would be better if we exposed 'isLoadingMore' via state.
                                  // Given the current implementation, we'll just check if we have more pages.
                                  final notifier =
                                      ref.read(feedProvider.notifier);
                                  if (notifier.hasNext) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: CircularProgressIndicator
                                            .adaptive(),
                                      ),
                                    );
                                  } else {
                                    return const SizedBox(height: 64); // Spacer
                                  }
                                }

                                final content = contents[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: FeedCard(
                                    content: content,
                                    onTap: () async {
                                      final uri = Uri.parse(content.url);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.inAppWebView,
                                        );

                                        // Au retour, marquer comme consommé
                                        if (context.mounted) {
                                          ref
                                              .read(feedProvider.notifier)
                                              .markContentAsConsumed(content);

                                          // Update Streak
                                          ref
                                              .read(streakProvider.notifier)
                                              .refreshSilent();
                                        }
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Impossible d\'ouvrir le lien : ${content.url}'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    onBookmark: () {
                                      ref
                                          .read(feedProvider.notifier)
                                          .toggleSave(content);

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            UIConstants.savedConfirmMessage(
                                                UIConstants.savedSectionName),
                                          ),
                                          action: SnackBarAction(
                                            label: 'Annuler',
                                            textColor: colors.primary,
                                            onPressed: () {
                                              ref
                                                  .read(feedProvider.notifier)
                                                  .toggleSave(content);
                                            },
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    },
                                    isBookmarked: content.isSaved,
                                    onMoreOptions: () {
                                      _showMoreOptions(context, content);
                                    },
                                  ),
                                );
                              },
                              // Add +1 for the loader/spacer
                              childCount: contents.length + 1,
                            ),
                          ),
                        );
                      },
                      loading: () => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: CircularProgressIndicator(
                                color: colors.primary),
                          ),
                        ),
                      ),
                      error: (err, stack) => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(
                                  PhosphorIcons.warning(
                                      PhosphorIconsStyle.duotone),
                                  size: 48,
                                  color: colors.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Erreur de chargement',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  err.toString(), // A améliorer pour prod
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.error),
                                ),
                                const SizedBox(height: 16),
                                FacteurButton(
                                  label: "Réessayer",
                                  icon: PhosphorIcons.arrowClockwise(
                                      PhosphorIconsStyle.bold),
                                  onPressed: () => ref.refresh(feedProvider),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showWelcome)
              Positioned.fill(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: WelcomeBanner(
                      onDismiss: _dismissWelcome,
                      secondaryMessage: null,
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
