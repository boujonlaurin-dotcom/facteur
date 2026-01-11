import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Écran de progression (placeholder)
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
          onPressed: () => context.pop(),
        ),
        title: const Text('Progression'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Streak
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
              child: Column(
                children: [
                  Icon(
                    PhosphorIcons.fire(PhosphorIconsStyle.fill),
                    size: 64,
                    color: colors.warning,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '0',
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 48,
                    ),
                  ),
                  Text(
                    'jours de suite',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIcons.trophy(PhosphorIconsStyle.fill),
                        size: 16,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Record : 0 jours',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Objectif hebdo
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.target(PhosphorIconsStyle.fill),
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Objectif hebdomadaire',
                        style: textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: 0,
                      backgroundColor: colors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation(
                        colors.primary,
                      ),
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '0 / 10 contenus cette semaine',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stats
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Statistiques',
                    style: textTheme.labelLarge,
                  ),
                  const SizedBox(height: 16),
                  const _StatRow(label: 'Cette semaine', value: '0'),
                  const Divider(height: 24),
                  const _StatRow(label: 'Ce mois', value: '0'),
                  const Divider(height: 24),
                  const _StatRow(label: 'Total', value: '0'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Répartition
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Répartition par type',
                    style: textTheme.labelLarge,
                  ),
                  const SizedBox(height: 16),
                  _TypeBar(
                    icon: PhosphorIcons.article(PhosphorIconsStyle.fill),
                    label: 'Articles',
                    count: 0,
                    total: 1,
                    color: colors.info,
                  ),
                  const SizedBox(height: 12),
                  _TypeBar(
                    icon: PhosphorIcons.headphones(PhosphorIconsStyle.fill),
                    label: 'Podcasts',
                    count: 0,
                    total: 1,
                    color: colors.success,
                  ),
                  const SizedBox(height: 12),
                  _TypeBar(
                    icon: PhosphorIcons.video(PhosphorIconsStyle.fill),
                    label: 'Vidéos',
                    count: 0,
                    total: 1,
                    color: colors.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        Text(
          '$value contenus',
          style: textTheme.labelLarge,
        ),
      ],
    );
  }
}

class _TypeBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final int total;
  final Color color;

  const _TypeBar({
    required this.icon,
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? count / total : 0.0;
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(label, style: textTheme.bodyMedium),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.surfaceElevated,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$count',
            style: textTheme.labelMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
