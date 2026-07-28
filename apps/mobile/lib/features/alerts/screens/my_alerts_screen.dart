import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';

/// Écran « Mes alertes » — inventaire des cloches, sources **et** sujets.
///
/// Sa raison d'être : rendre le silence lisible. Une cloche qui ne sonne pas
/// pendant six semaines ressemble à une cloche cassée ; la carte affiche donc
/// la dernière parution réelle de la cible pour prouver que rien n'a été
/// manqué.
class MyAlertsScreen extends ConsumerWidget {
  const MyAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final alertsAsync = ref.watch(alertsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mes alertes'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorView(
          onRetry: () => ref.read(alertsProvider.notifier).refresh(),
        ),
        data: (alerts) => alerts.items.isEmpty
            ? const _EmptyView()
            : _AlertsList(alerts: alerts),
      ),
    );
  }
}

class _AlertsList extends ConsumerWidget {
  final AlertsState alerts;

  const _AlertsList({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => ref.read(alertsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        children: [
          Text(
            '${alerts.activeCount} / ${alerts.cap} alertes actives',
            style: textTheme.labelLarge?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            'Une alerte se pose sur une source ou un sujet suivi. '
            'Elle arrive en silence, dans ta tournée.',
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: FacteurSpacing.space4),
          for (final item in alerts.items) ...[
            _AlertCard(item: item),
            const SizedBox(height: FacteurSpacing.space3),
          ],
        ],
      ),
    );
  }
}

class _AlertCard extends ConsumerStatefulWidget {
  final AlertItem item;

  const _AlertCard({required this.item});

  @override
  ConsumerState<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends ConsumerState<_AlertCard> {
  bool _removing = false;

  Future<void> _disable() async {
    setState(() => _removing = true);
    try {
      final notifier = ref.read(alertsProvider.notifier);
      if (widget.item.isTopic) {
        await notifier.setTopicAlert(widget.item.sourceId, false);
      } else {
        await notifier.setAlert(widget.item.sourceId, false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _removing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de retirer cette alerte.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Un sujet n'a pas de logo : la cloche tient lieu d'identité
              // visuelle, au même gabarit pour que la liste reste alignée.
              if (item.isTopic)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    PhosphorIcons.bell(PhosphorIconsStyle.regular),
                    size: 18,
                    color: colors.primary,
                  ),
                )
              else
                SourceLogoAvatar.fromUrl(
                  logoUrl: item.sourceLogoUrl,
                  name: item.sourceName,
                  size: 32,
                  radius: 8,
                ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Text(
                  item.sourceName,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.newContent > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  ),
                  child: Text(
                    '${item.newContent} nouveau'
                    '${item.newContent > 1 ? 'x' : ''}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            _statusLine(item),
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (item.filtered) ...[
            const SizedBox(height: 6),
            Text(
              'Filtré : seulement les plus marquantes, 1 max par jour.',
              style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: FacteurSpacing.space3),
          _WhenToNotify(),
          const SizedBox(height: FacteurSpacing.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _removing ? null : _disable,
              icon: Icon(
                PhosphorIcons.bellSlash(PhosphorIconsStyle.regular),
                size: 16,
              ),
              label: const Text('Désactiver l\'alerte'),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Le silence comme preuve » : sans cette ligne, une cloche muette depuis
/// six semaines passe pour cassée.
String _statusLine(AlertItem item) {
  final last = item.lastPublishedAt;
  if (last == null) {
    return 'En veille active. Rien de publié pour l\'instant.';
  }
  final days = DateTime.now().difference(last).inDays;
  if (days <= 0) return 'En veille active. Publié aujourd\'hui.';
  if (days == 1) return 'En veille active. Publié hier.';
  if (days < 7) return 'En veille active. Publié il y a $days jours.';
  final weeks = days ~/ 7;
  return 'En veille active. Rien de neuf depuis '
      '$weeks semaine${weeks > 1 ? 's' : ''}, et c\'est vérifié.';
}

/// Réglage « Quand me prévenir ».
///
/// Le récap hebdo est volontairement désactivé en V1 : aucun producteur ne
/// tourne derrière, et proposer un choix qui ne change rien serait mentir.
class _WhenToNotify extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quand me prévenir',
          style: textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _Choice(label: 'Dans ma tournée', selected: true, enabled: true),
            _Choice(label: 'Récap hebdo', selected: false, enabled: false),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;

  const _Choice({
    required this.label,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final color = !enabled
        ? colors.textTertiary
        : (selected ? colors.primary : colors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : null,
              fontSize: 12,
            ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.bell(PhosphorIconsStyle.regular),
              size: 40,
              color: colors.textTertiary,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              'Aucune alerte pour l\'instant',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              'Pose une alerte depuis la fiche d\'une source ou d\'un sujet '
              'suivi : tu seras prévenu à la parution, sans avoir à y penser.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space6),
            FilledButton(
              onPressed: () => context.goNamed(RouteNames.myInterests),
              child: const Text('Voir mes sources'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Impossible de charger tes alertes.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space3),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
