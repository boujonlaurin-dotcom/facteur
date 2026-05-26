import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/streak_activity_model.dart';
import '../providers/streak_activity_provider.dart';

class StreakExplainerModal extends ConsumerWidget {
  const StreakExplainerModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StreakExplainerModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final streakActivityAsync = ref.watch(streakActivityProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePaper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: streakActivityAsync.when(
            data: (activity) => _ExplainerBody(activity: activity),
            loading: () => SizedBox(
              height: 320,
              child: Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
            ),
            error: (_, __) => SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Impossible de charger la série pour le moment.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplainerBody extends StatelessWidget {
  const _ExplainerBody({required this.activity});

  final StreakActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final totalArticlesRead = activity.days.fold<int>(
      0,
      (sum, day) => sum + (day.articlesRead ?? 0),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: _AnimatedFlameBadge()),
          const SizedBox(height: 16),
          Text(
            'Ta série d\'ouverture',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Elle avance chaque jour où tu ouvres Facteur. Si tu sautes une journée, elle repart à 1.',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _StreakStatsLine(
            currentStreak: activity.currentStreak,
            longestStreak: activity.longestStreak,
            totalArticlesRead: totalArticlesRead,
          ),
          const SizedBox(height: 20),
          _RecentActivityCalendar(days: activity.days),
        ],
      ),
    );
  }
}

class _StreakStatsLine extends StatelessWidget {
  const _StreakStatsLine({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalArticlesRead,
  });

  final int currentStreak;
  final int longestStreak;
  final int totalArticlesRead;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'En ce moment',
          style: textTheme.labelLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InlineMetric(
                icon: PhosphorIcons.fire(PhosphorIconsStyle.fill),
                label: 'Actuelle',
                value: '$currentStreak j',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InlineMetric(
                icon: PhosphorIcons.trophy(PhosphorIconsStyle.fill),
                label: 'Record',
                value: '$longestStreak j',
              ),
            ),
            if (totalArticlesRead > 0) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _InlineMetric(
                  icon: PhosphorIcons.bookOpen(PhosphorIconsStyle.regular),
                  label: 'Lus',
                  value: '$totalArticlesRead',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: colors.primary.withValues(alpha: 0.82),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RecentActivityCalendar extends StatelessWidget {
  const _RecentActivityCalendar({required this.days});

  final List<StreakActivityDay> days;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              PhosphorIcons.calendarBlank(PhosphorIconsStyle.regular),
              size: 16,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '14 derniers jours',
              style: textTheme.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Une flamme marque les jours où Facteur a été ouvert.',
          style: textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        const _WeekdayHeader(),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            return _DayTile(day: days[index]);
          },
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    const labels = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});

  final StreakActivityDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final opened = day.opened;
    final articleCount = day.articlesRead ?? 0;

    return Semantics(
      label:
          '${day.date.day}/${day.date.month}, ${opened ? 'ouvert' : 'non ouvert'}'
          '${articleCount > 0 ? ', $articleCount lu${articleCount > 1 ? 's' : ''}' : ''}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: opened
              ? colors.primary.withValues(alpha: 0.10)
              : colors.backgroundSecondary.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: opened
                ? colors.primary.withValues(alpha: 0.24)
                : colors.border.withValues(alpha: 0.55),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                opened
                    ? PhosphorIcons.fire(PhosphorIconsStyle.fill)
                    : PhosphorIcons.minus(PhosphorIconsStyle.bold),
                size: 14,
                color: opened
                    ? colors.primary.withValues(alpha: 0.86)
                    : colors.textTertiary,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${day.date.day}',
                  maxLines: 1,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
            if (articleCount > 0)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.only(top: 3, right: 3),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedFlameBadge extends StatefulWidget {
  const _AnimatedFlameBadge();

  @override
  State<_AnimatedFlameBadge> createState() => _AnimatedFlameBadgeState();
}

class _AnimatedFlameBadgeState extends State<_AnimatedFlameBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.96,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _glow = Tween<double>(
      begin: 0.18,
      end: 0.36,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.08),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: _glow.value),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Transform.scale(
            scale: _scale.value,
            child: Icon(
              PhosphorIcons.fire(PhosphorIconsStyle.fill),
              color: colors.primary,
              size: 34,
            ),
          ),
        );
      },
    );
  }
}
