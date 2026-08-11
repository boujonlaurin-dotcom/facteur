import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/web/web_perf.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/utils/publication_frequency.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';

/// Garde-fou partagé par tous les chemins de pose de cloche.
///
/// Poser une cloche sans droit de notifier produirait une alerte qui ne sonne
/// jamais : on demande la permission OS **avant** l'appel serveur, et on
/// renonce si l'utilisateur refuse.
///
/// Retourne `true` si la pose peut continuer. Sur le web il n'y a pas de push
/// local (`flutter_local_notifications` n'a pas de plugin Web) : la cloche est
/// un réglage de compte, pas d'appareil, donc on laisse passer plutôt que de
/// bloquer sur une modale qui ne s'affiche pas.
Future<bool> ensureAlertPushPermission(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!kSupportsPushNotifications) return true;
  if (ref.read(notificationsSettingsProvider).pushEnabled) return true;

  await showNotificationActivationModal(
    context,
    ref,
    trigger: ActivationTrigger.alert,
  );
  if (!context.mounted) return false;
  return ref.read(notificationsSettingsProvider).pushEnabled;
}

/// Propose la cloche juste après un suivi réussi, source **ou** sujet.
///
/// C'est le moment chaud : l'utilisateur vient de choisir cette cible, il sait
/// pourquoi elle l'intéresse. Proposer la même chose trois jours plus tard dans
/// un écran de réglages ne convertit pas.
///
/// **Règle des alertes v2** : la proposition spontanée ne se déclenche que si
/// la cible n'est pas bruyante (≤ 3 parutions/semaine). Poser une cloche sur Le
/// Monde reste possible, mais ça doit rester un geste délibéré depuis la fiche
/// — pas une offre qu'on n'a pas demandée.
///
/// Point d'entrée unique appelé depuis tous les chemins de suivi, pour que la
/// logique ne se disperse pas. Silencieux (aucun effet visible) si le plafond
/// est atteint, si la cadence n'est pas chargeable, ou si la cible est bavarde
/// — jamais d'erreur remontée pour une proposition non sollicitée.
Future<void> maybeOfferAlert(
  BuildContext context,
  WidgetRef ref, {
  String? sourceId,
  String? topicId,
}) async {
  final targetId = sourceId ?? topicId;
  if (targetId == null || targetId.isEmpty) return;
  final kind = topicId != null ? AlertKind.topic : AlertKind.source;

  try {
    final alerts = await ref.read(alertsProvider.future);
    if (alerts.isFull) return;
    if (alerts.items.any((i) => i.sourceId == targetId)) return;

    final String name;
    final String phrase;
    final bool noisy;
    if (kind == AlertKind.topic) {
      final frequency = await ref.read(topicFrequencyProvider(targetId).future);
      // Un sujet dont on ne sait rien (aucune parution correspondante) ne
      // mérite pas de proposition : la cloche ne sonnerait jamais.
      if (frequency.articles30d < 1) return;
      name = 'Ce sujet';
      phrase = frequency.cadencePhrase;
      noisy = frequency.noisy;
    } else {
      final profile = await ref.read(sourceProfileProvider(targetId).future);
      if (profile.articles30d < 1) return;
      name = profile.source?.name ?? 'Cette source';
      phrase = cadencePhrase(profile.articles30d, profile.oldestContentAt);
      noisy = isNoisy(profile.articles30d, profile.oldestContentAt);
    }
    if (noisy) return;

    if (!context.mounted) return;
    await showAlertActivationSheet(
      context,
      ref,
      targetId: targetId,
      kind: kind,
      targetName: name,
      cadencePhrase: phrase,
    );
  } catch (_) {
    // Proposition best-effort : une cadence indisponible ne doit pas
    // transformer un suivi réussi en message d'erreur.
  }
}

Future<void> showAlertActivationSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetId,
  required AlertKind kind,
  required String targetName,
  required String cadencePhrase,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AlertActivationSheet(
      targetId: targetId,
      kind: kind,
      targetName: targetName,
      cadencePhrase: cadencePhrase,
    ),
  );
}

class _AlertActivationSheet extends ConsumerStatefulWidget {
  final String targetId;
  final AlertKind kind;
  final String targetName;
  final String cadencePhrase;

  const _AlertActivationSheet({
    required this.targetId,
    required this.kind,
    required this.targetName,
    required this.cadencePhrase,
  });

  @override
  ConsumerState<_AlertActivationSheet> createState() =>
      _AlertActivationSheetState();
}

class _AlertActivationSheetState extends ConsumerState<_AlertActivationSheet> {
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);

    if (!await ensureAlertPushPermission(context, ref)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    try {
      final notifier = ref.read(alertsProvider.notifier);
      if (widget.kind == AlertKind.topic) {
        await notifier.setTopicAlert(widget.targetId, true);
      } else {
        await notifier.setAlert(widget.targetId, true);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerte activée sur ${widget.targetName}.')),
      );
    } on AlertCapReachedException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tu as déjà ${e.cap} alertes. Désactives-en une dans Mes alertes.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'activer l\'alerte.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final isTopic = widget.kind == AlertKind.topic;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(FacteurSpacing.space4),
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTopic
                  ? 'Ne rate pas la prochaine actu'
                  : 'Ne rate pas sa prochaine parution',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              '${widget.cadencePhrase}. Être alerté à chaque parution ?',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _activate,
                child: const Text('Activer l\'alerte'),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                child: const Text('Plus tard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
