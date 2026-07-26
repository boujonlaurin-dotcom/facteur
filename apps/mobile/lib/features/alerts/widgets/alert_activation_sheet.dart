import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/utils/publication_frequency.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';

/// Propose la cloche juste après un suivi réussi, si la source est rare.
///
/// C'est le moment chaud : l'utilisateur vient de choisir cette source, il
/// sait pourquoi elle l'intéresse. Proposer la même chose trois jours plus
/// tard dans un écran de réglages ne convertit pas.
///
/// Point d'entrée unique appelé depuis tous les chemins de suivi, pour que la
/// logique ne se disperse pas. Silencieux (aucun effet visible) si la source
/// n'est pas éligible, si le plafond est atteint, ou si le profil n'est pas
/// chargeable — jamais d'erreur remontée à l'utilisateur pour une proposition
/// qu'il n'a pas demandée.
Future<void> maybeOfferSourceAlert(
  BuildContext context,
  WidgetRef ref,
  String sourceId,
) async {
  if (sourceId.isEmpty) return;
  try {
    final alerts = await ref.read(alertsProvider.future);
    if (alerts.isFull) return;
    if (alerts.items.any((i) => i.sourceId == sourceId)) return;

    final profile = await ref.read(sourceProfileProvider(sourceId).future);
    final phrase = rarityPhrase(profile.articles30d, profile.oldestContentAt);
    if (phrase == null) return;

    if (!context.mounted) return;
    await showAlertActivationSheet(
      context,
      ref,
      sourceId: sourceId,
      sourceName: profile.source?.name ?? 'Cette source',
      rarityPhrase: phrase,
    );
  } catch (_) {
    // Proposition best-effort : un profil indisponible ne doit pas transformer
    // un suivi réussi en message d'erreur.
  }
}

Future<void> showAlertActivationSheet(
  BuildContext context,
  WidgetRef ref, {
  required String sourceId,
  required String sourceName,
  required String rarityPhrase,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AlertActivationSheet(
      sourceId: sourceId,
      sourceName: sourceName,
      rarityPhrase: rarityPhrase,
    ),
  );
}

class _AlertActivationSheet extends ConsumerStatefulWidget {
  final String sourceId;
  final String sourceName;
  final String rarityPhrase;

  const _AlertActivationSheet({
    required this.sourceId,
    required this.sourceName,
    required this.rarityPhrase,
  });

  @override
  ConsumerState<_AlertActivationSheet> createState() =>
      _AlertActivationSheetState();
}

class _AlertActivationSheetState extends ConsumerState<_AlertActivationSheet> {
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);

    // Permission OS d'abord : poser la cloche sans droit de notifier
    // produirait une alerte qui ne sonne jamais.
    final settings = ref.read(notificationsSettingsProvider);
    if (!settings.pushEnabled) {
      await showNotificationActivationModal(
        context,
        ref,
        trigger: ActivationTrigger.alert,
      );
      if (!mounted) return;
      if (!ref.read(notificationsSettingsProvider).pushEnabled) {
        setState(() => _busy = false);
        return;
      }
    }

    try {
      await ref.read(alertsProvider.notifier).setAlert(widget.sourceId, true);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloche activée sur ${widget.sourceName}.'),
        ),
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
        const SnackBar(content: Text('Impossible d\'activer la cloche.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

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
              '📯 Ne rate pas sa prochaine parution',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              '${widget.sourceName} publie ${widget.rarityPhrase}. '
              'Être alerté à chaque parution ?',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _activate,
                child: const Text('Activer la cloche'),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).maybePop(),
                child: const Text('Plus tard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
