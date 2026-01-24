import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../widgets/design/facteur_button.dart';
import '../repositories/progress_repository.dart';
import '../models/progress_models.dart';

class ProgressionsScreen extends ConsumerWidget {
  const ProgressionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final progressAsync = ref.watch(myProgressProvider);

    return Material(
      color: colors.backgroundPrimary,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(myProgressProvider.future),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(FacteurSpacing.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mes Progressions',
                        style: textTheme.displayMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space1),
                      Text(
                        'Fini la lecture passive. Ici, apprenez et progressez sur vos thématiques favorites !',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Content
              progressAsync.when(
                data: (progressList) {
                  if (progressList.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(FacteurSpacing.space6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  PhosphorIcons.chartLineUp(
                                    PhosphorIconsStyle.duotone,
                                  ),
                                  size: 48,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(height: FacteurSpacing.space4),
                              Text(
                                'Aucune progression',
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: FacteurSpacing.space2),
                              Text(
                                'Suivez un thème depuis un article pour commencer votre progression.',
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: FacteurSpacing.space6),
                              FacteurButton(
                                label: 'Explorer le feed',
                                icon: PhosphorIcons.compass(
                                  PhosphorIconsStyle.bold,
                                ),
                                onPressed: () {
                                  context.go(RoutePaths.feed);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final progress = progressList[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ProgressCard(progress: progress),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: (50 * index).ms)
                              .slideX(begin: 0.1, end: 0);
                        },
                        childCount: progressList.length,
                      ),
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, stack) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.warning(PhosphorIconsStyle.duotone),
                            size: 48,
                            color: colors.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Une erreur est survenue',
                            style: textTheme.titleMedium,
                          ),
                          Text(
                            err.toString(),
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FacteurButton(
                            label: 'Réessayer',
                            icon: PhosphorIcons.arrowClockwise(
                              PhosphorIconsStyle.bold,
                            ),
                            onPressed: () =>
                                ref.refresh(myProgressProvider.future),
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
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final UserTopicProgress progress;

  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        context.goNamed(
          RouteNames.quiz,
          extra: progress.topic,
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.surfaceElevated,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    PhosphorIcons.student(PhosphorIconsStyle.fill),
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress.topic,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Niveau ${progress.level} • ${progress.points} pts',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                  color: colors.textTertiary,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress Bar (fake calculation for demo, level * 100 threshold)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (progress.points % 100) /
                    100, // Dummy progress within level
                backgroundColor: colors.surfaceElevated,
                color: colors.primary,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
