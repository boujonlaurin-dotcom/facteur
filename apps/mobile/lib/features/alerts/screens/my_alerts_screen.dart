import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';
import '../widgets/alert_target_picker_sheet.dart';

/// Écran « Mes alertes » — le poste de commande des cloches, sources **et**
/// sujets (story 30.5).
///
/// Deux raisons d'être :
/// 1. **Rendre le silence lisible.** Une cloche qui ne sonne pas pendant six
///    semaines ressemble à une cloche cassée ; la carte affiche donc la
///    dernière parution réelle de la cible pour prouver que rien n'a été
///    manqué.
/// 2. **Poser une cloche sans quitter l'écran.** Jusqu'à la 30.5 l'écran ne
///    savait que lister et désactiver : ajouter imposait d'aller chercher la
///    fiche d'une source ou d'un sujet. Le bouton « Ajouter une alerte » ouvre
///    désormais le sélecteur de cible sur place.
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
        data: (alerts) => _AlertsList(alerts: alerts),
      ),
    );
  }
}

class _AlertsList extends ConsumerWidget {
  final AlertsState alerts;

  const _AlertsList({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(alertsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        children: [
          _Header(alerts: alerts),
          const SizedBox(height: FacteurSpacing.space4),
          // ─────────────────────────────────────────────────────────────────
          // SLOT LOT D — suggestions de cibles.
          // Emplacement réservé, entre l'en-tête et l'inventaire : c'est là que
          // le moteur de suggestions viendra proposer « Tu suis X depuis 3
          // semaines, veux-tu être alerté ? ». Le Lot D remplace le corps de
          // [AlertSuggestionsSlot] ; ni l'en-tête ni la liste n'ont à bouger.
          // ─────────────────────────────────────────────────────────────────
          const AlertSuggestionsSlot(),
          if (alerts.items.isEmpty)
            const _EmptyView()
          else
            for (final item in alerts.items) ...[
              _AlertCard(item: item),
              const SizedBox(height: FacteurSpacing.space3),
            ],
          const SizedBox(height: FacteurSpacing.space4),
          const _NotificationSettingsLink(),
        ],
      ),
    );
  }
}

/// En-tête : le plafond, la vérité sur ce qui se passe, et le geste d'ajout.
///
/// Le plafond était jusqu'ici une ligne perdue au-dessus de la liste et un
/// refus serveur découvert au moment de la 6ᵉ cloche. Il est maintenant lisible
/// avant le geste.
class _Header extends ConsumerWidget {
  final AlertsState alerts;

  const _Header({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final full = alerts.isFull;

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
              Icon(
                PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Text(
                '${alerts.activeCount} alerte'
                '${alerts.activeCount > 1 ? 's' : ''} sur ${alerts.cap}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space2),
          // Ce que l'app fait réellement, et rien d'autre : le push part à la
          // parution, avec son. L'ancien réglage « Quand me prévenir » laissait
          // croire à un choix (« Dans ma tournée » / « Récap hebdo ») qu'aucun
          // producteur ne servait.
          Text(
            'Tu reçois une notification dès la parution, avec son. '
            '${alerts.cap} alertes au maximum, sources et sujets confondus.',
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: FacteurSpacing.space4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: full ? null : () => showAlertTargetPicker(context),
              icon: Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
              ),
              label: const Text('Ajouter une alerte'),
            ),
          ),
          if (full) ...[
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              'Plafond atteint. Désactive une alerte pour en poser une autre.',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Emplacement réservé au moteur de suggestions (Lot D).
///
/// Volontairement vide ici : un écran ne doit pas afficher un bloc dont
/// personne ne produit le contenu. Le Lot D remplace ce corps par sa liste.
class AlertSuggestionsSlot extends StatelessWidget {
  const AlertSuggestionsSlot({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

/// État vide **actionnable** : le geste d'ajout est déjà dans l'en-tête, on ne
/// le duplique pas ; on explique seulement ce que la cloche fait.
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space6),
      child: Column(
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
            'Une alerte se pose sur une source ou un sujet que tu suis. '
            'Tu es prévenu à la parution, sans avoir à y penser.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Lien discret vers les réglages de notifications (horaire du récap, bonnes
/// nouvelles, interrupteur push général).
///
/// Sens de la flèche inversé par rapport à la v1 : « Mes alertes » n'est plus
/// une feuille des réglages de notifications, c'est l'inverse. Masqué sur le
/// web, où l'écran des push n'a pas d'effet.
class _NotificationSettingsLink extends StatelessWidget {
  const _NotificationSettingsLink();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final colors = context.facteurColors;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.pushNamed(RouteNames.notifications),
        icon: Icon(
          PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
          size: 16,
        ),
        label: const Text('Horaires et notifications'),
        style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
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
