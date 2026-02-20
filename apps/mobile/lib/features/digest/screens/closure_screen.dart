import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../models/digest_models.dart';
import '../providers/digest_provider.dart';
import '../widgets/streak_celebration.dart';
import '../widgets/digest_summary.dart';
import '../../saved/providers/saved_summary_provider.dart';

/// Closure screen displayed after completing the digest (5/7 threshold)
/// Shows celebration animation, streak count, and digest summary
class ClosureScreen extends ConsumerStatefulWidget {
  final String digestId;

  const ClosureScreen({
    super.key,
    required this.digestId,
  });

  @override
  ConsumerState<ClosureScreen> createState() => _ClosureScreenState();
}

class _ClosureScreenState extends ConsumerState<ClosureScreen>
    with TickerProviderStateMixin {
  late AnimationController _headlineController;
  late AnimationController _summaryController;
  late AnimationController _buttonsController;
  late Animation<double> _headlineOpacityAnimation;
  late Animation<Offset> _headlineSlideAnimation;
  late Animation<double> _summaryOpacityAnimation;
  late Animation<Offset> _summarySlideAnimation;
  late Animation<double> _buttonsOpacityAnimation;
  late Animation<Offset> _buttonsSlideAnimation;

  DigestCompletionResponse? _completionData;
  bool _isLoadingCompletion = true;
  bool _hasTrackedSession = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimationSequence();
    _loadCompletionData();
  }

  void _setupAnimations() {
    // Headline animation: 0ms start, 400ms duration
    _headlineController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Summary animation: 1000ms start, 400ms duration
    _summaryController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Buttons animation: 1400ms start, 400ms duration
    _buttonsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Headline fade + slide up
    _headlineOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _headlineController, curve: Curves.easeOut),
    );
    _headlineSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _headlineController, curve: Curves.easeOut),
    );

    // Summary fade + slide up
    _summaryOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _summaryController, curve: Curves.easeOut),
    );
    _summarySlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _summaryController, curve: Curves.easeOut),
    );

    // Buttons fade + slide up
    _buttonsOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _buttonsController, curve: Curves.easeOut),
    );
    _buttonsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _buttonsController, curve: Curves.easeOut),
    );
  }

  Future<void> _startAnimationSequence() async {
    // Headline starts immediately
    await _headlineController.forward();

    // Summary starts at 1000ms
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    await _summaryController.forward();

    // Buttons start at 1400ms
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _buttonsController.forward();
  }

  Future<void> _loadCompletionData() async {
    // Get completion data from provider or API
    // For now, we'll calculate it from the digest state
    final digest = ref.read(digestProvider).value;
    if (digest != null) {
      // Complete the digest to get the response
      try {
        await ref.read(digestProvider.notifier).completeDigest();
      } catch (e) {
        // Ignore errors - completion may have already happened
      }

      // Calculate stats from items
      final items = digest.items;
      final readCount = items.where((item) => item.isRead).length;
      final savedCount = items.where((item) => item.isSaved).length;
      final dismissedCount = items.where((item) => item.isDismissed).length;

      // Get streak info from provider or use defaults
      // In a real implementation, this would come from the API response
      final completionData = DigestCompletionResponse(
        success: true,
        digestId: widget.digestId,
        completedAt: DateTime.now(),
        articlesRead: readCount,
        articlesSaved: savedCount,
        articlesDismissed: dismissedCount,
        closureTimeSeconds: null, // Would come from API
        closureStreak: 1, // Would come from streak provider
        streakMessage: null, // Would come from API
      );

      setState(() {
        _completionData = completionData;
        _isLoadingCompletion = false;
      });

      // Fire digest_session analytics event (once only)
      _trackDigestSession(completionData, digest);
    } else {
      setState(() {
        _isLoadingCompletion = false;
      });
    }
  }

  /// Fire a digest_session analytics event once per closure.
  void _trackDigestSession(
    DigestCompletionResponse completionData,
    DigestResponse digest,
  ) {
    if (_hasTrackedSession) return;
    _hasTrackedSession = true;

    try {
      // Calculate articles passed: total minus read/saved/dismissed
      final totalItems = digest.items.length;
      final passedCount = totalItems -
          completionData.articlesRead -
          completionData.articlesSaved -
          completionData.articlesDismissed;

      ref.read(analyticsServiceProvider).trackDigestSession(
            digestDate: digest.targetDate.toIso8601String().split('T').first,
            articlesRead: completionData.articlesRead,
            articlesSaved: completionData.articlesSaved,
            articlesDismissed: completionData.articlesDismissed,
            articlesPassed: passedCount > 0 ? passedCount : 0,
            totalTimeSeconds: completionData.closureTimeSeconds ?? 0,
            closureAchieved: true,
            streak: completionData.closureStreak,
          );
    } catch (e) {
      // Fail silently — analytics should never block closure UX
      debugPrint('ClosureScreen: analytics tracking failed: $e');
    }
  }

  void _navigateToFeed() {
    // Replace current route (don't allow back to closure)
    context.go(RoutePaths.feed);
  }

  void _onExplorerPlusPressed() {
    _navigateToFeed();
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _summaryController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Headline with fade and slide
            SlideTransition(
              position: _headlineSlideAnimation,
              child: FadeTransition(
                opacity: _headlineOpacityAnimation,
                child: Text(
                  'Tu es à jour !',
                  style: textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space6),

            // Streak celebration (animated widget handles its own timing)
            if (_isLoadingCompletion)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              StreakCelebration(
                streakCount: _completionData?.closureStreak ?? 1,
                streakMessage: _completionData?.streakMessage,
              ),

            const SizedBox(height: FacteurSpacing.space4),

            // Digest summary with fade and slide
            SlideTransition(
              position: _summarySlideAnimation,
              child: FadeTransition(
                opacity: _summaryOpacityAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                  ),
                  child: _isLoadingCompletion
                      ? const SizedBox.shrink()
                      : DigestSummary(
                          articlesRead: _completionData?.articlesRead ?? 0,
                          articlesSaved: _completionData?.articlesSaved ?? 0,
                          articlesDismissed:
                              _completionData?.articlesDismissed ?? 0,
                          closureTimeSeconds:
                              _completionData?.closureTimeSeconds,
                        ),
                ),
              ),
            ),

            // Saved articles nudge (subtle, after summary)
            Builder(builder: (context) {
              final savedSummary =
                  ref.watch(savedSummaryProvider).valueOrNull;
              if (savedSummary == null ||
                  savedSummary.recentCount7d < 3) {
                return const SizedBox.shrink();
              }
              final count = savedSummary.recentCount7d;
              return Padding(
                padding: const EdgeInsets.only(top: FacteurSpacing.space3),
                child: GestureDetector(
                  onTap: () => context.push(RoutePaths.saved),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIcons.bookmarkSimple(
                            PhosphorIconsStyle.regular),
                        size: 14,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$count article${count > 1 ? 's' : ''} sauvegardé${count > 1 ? 's' : ''} cette semaine',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Voir',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const Spacer(flex: 3),

            // Buttons with fade and slide
            SlideTransition(
              position: _buttonsSlideAnimation,
              child: FadeTransition(
                opacity: _buttonsOpacityAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary button: Explorer plus
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _onExplorerPlusPressed,
                          icon: Icon(
                            PhosphorIcons.compass(PhosphorIconsStyle.regular),
                            size: 20,
                          ),
                          label: const Text('Explorer plus'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(FacteurRadius.medium),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: FacteurSpacing.space3),

                      // Message emphasizing user is up to date
                      Text(
                        'ps : Tu peux maintenant aussi fermer l\'app ;-)',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: FacteurSpacing.space2),

                      // Feedback CTA
                      GestureDetector(
                        onTap: () async {
                          final uri =
                              Uri.parse(ExternalLinks.feedbackFormUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.chatCircleDots(
                                  PhosphorIconsStyle.regular),
                              size: 16,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: FacteurSpacing.space1),
                            Text(
                              'Un avis ? Dites-nous tout',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.textSecondary
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space4),
          ],
        ),
      ),
    );
  }
}
