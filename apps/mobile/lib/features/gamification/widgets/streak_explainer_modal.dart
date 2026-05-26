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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Actuelle',
                  value: '${activity.currentStreak}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  label: 'Record',
                  value: '${activity.longestStreak}',
                ),
              ),
              if (totalArticlesRead > 0) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricTile(label: 'Lus', value: '$totalArticlesRead'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '14 derniers jours',
            style: textTheme.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activity.days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.86,
            ),
            itemBuilder: (context, index) {
              return _DayTile(day: activity.days[index]);
            },
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
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
    final date = day.date;
    final weekday = _weekdayLabel(date.weekday);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: opened
            ? colors.primary.withValues(alpha: 0.10)
            : colors.backgroundSecondary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: opened
              ? colors.primary.withValues(alpha: 0.25)
              : colors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            style: textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            opened
                ? PhosphorIcons.fire(PhosphorIconsStyle.fill)
                : PhosphorIcons.minus(PhosphorIconsStyle.bold),
            size: 14,
            color: opened
                ? colors.primary.withValues(alpha: 0.85)
                : colors.textTertiary,
          ),
          const SizedBox(height: 4),
          Text(
            '${date.day}',
            style: textTheme.labelMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (day.articlesRead != null) ...[
            const SizedBox(height: 2),
            Text(
              '${day.articlesRead}',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = <int, String>{
      DateTime.monday: 'L',
      DateTime.tuesday: 'M',
      DateTime.wednesday: 'M',
      DateTime.thursday: 'J',
      DateTime.friday: 'V',
      DateTime.saturday: 'S',
      DateTime.sunday: 'D',
    };
    return labels[weekday] ?? '';
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
