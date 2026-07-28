import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/services/widget_pin_prompt.dart';
import '../../../core/services/widget_service.dart';

/// `true` quand le bandeau « Ajouter le widget » doit être affiché.
///
/// Trois conditions : plateforme Android, aucun widget Facteur déjà épinglé,
/// et pas de rejet récent. En cas de doute sur l'épinglage (appel plateforme
/// en échec, [WidgetService.isWidgetPinned] renvoie `null`), on **n'affiche
/// pas** : mieux vaut rater une proposition que la répéter à un utilisateur
/// qui a déjà le widget.
///
/// Le throttle passe par le registre unifié des nudges
/// ([NudgeIds.widgetCtaFeedBanner], cooldown 7 j) plutôt que par une clé
/// SharedPreferences maison : même horloge testable, même purge au logout,
/// même namespace que les autres bandeaux du feed.
final widgetCtaVisibleProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || !Platform.isAndroid) return false;

  final pinned = await WidgetService.isWidgetPinned();
  if (pinned != false) return false;

  return ref.watch(nudgeServiceProvider).canShow(NudgeIds.widgetCtaFeedBanner);
});

/// Bandeau en tête de Flâner proposant d'épingler le widget d'accueil.
///
/// L'entrée historique était enterrée dans Compte > Widget et, surtout, ne
/// faisait rien : le plugin ne résolvait jamais le receiver et l'échec était
/// silencieux (cf. docs/bugs/bug-widget-fiabilite.md, C1). Ici le CTA est
/// visible, dismissible, et rend toujours compte du résultat via
/// [WidgetPinPrompt].
class WidgetCtaBanner extends ConsumerWidget {
  const WidgetCtaBanner({super.key});

  Future<void> _dismiss(WidgetRef ref) async {
    // Best-effort : même si la persistance échoue, le bandeau disparaît pour
    // la session courante via l'invalidation.
    try {
      await ref
          .read(nudgeServiceProvider)
          .markShown(NudgeIds.widgetCtaFeedBanner);
    } catch (_) {}
    ref.invalidate(widgetCtaVisibleProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(widgetCtaVisibleProvider);
    if (visible.valueOrNull != true) return const SizedBox.shrink();

    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          onTap: () async {
            HapticFeedback.mediumImpact();
            final result = await WidgetPinPrompt.requestAndReport();
            if (result == WidgetPinResult.requested) {
              // Le launcher a pris la main : on ne re-proposera qu'après la
              // fenêtre de throttle, que l'utilisateur confirme ou non.
              await _dismiss(ref);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
                  size: 22,
                  color: colors.primary,
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ton flux sur l\'écran d\'accueil',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ajoute le widget Facteur et lis tes articles sans ouvrir l\'app.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                IconButton(
                  icon: Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.regular),
                    size: 18,
                    color: colors.textTertiary,
                  ),
                  onPressed: () => _dismiss(ref),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Masquer',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
