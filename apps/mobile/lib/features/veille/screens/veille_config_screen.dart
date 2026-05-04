import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../models/veille_delivery.dart';
import '../providers/veille_active_config_provider.dart';
import '../providers/veille_config_provider.dart';
import '../providers/veille_repository_provider.dart';
import '../repositories/veille_repository.dart';
import 'steps/step1_5_preset_preview_screen.dart';
import 'steps/step1_theme_screen.dart';
import 'steps/step2_suggestions_screen.dart';
import 'steps/step3_sources_screen.dart';
import 'steps/step4_frequency_screen.dart';
import 'transitions/flow_loading_screen.dart';

/// Host du flow de configuration de la veille.
///
/// - Si l'utilisateur a déjà une config active (`GET /api/veille/config` =
///   200), redirect vers `/veille/dashboard` au lieu de relancer le flow.
/// - Si 404 (pas de veille), affiche le flow 4-steps normal.
/// - Si erreur API, affiche le flow normal et laisse le user tenter de
///   créer une veille (l'erreur sera relevée au submit).
class VeilleConfigScreen extends ConsumerWidget {
  const VeilleConfigScreen({super.key, this.editMode = false});

  /// Mode édition : `true` quand la route reçoit `?mode=edit` depuis le
  /// bouton « Modifier ma veille » du dashboard. En mode edit, la guard
  /// redirect-vers-dashboard est désactivée et le state est hydraté depuis
  /// la config active.
  final bool editMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final activeConfig = ref.watch(veilleActiveConfigProvider);

    final activeCfgValue = activeConfig.valueOrNull;
    if (!editMode && activeCfgValue != null) {
      // Si une config est déjà active, le user n'a rien à reconfigurer →
      // redirect vers le dashboard. context.go est idempotent, donc même si le
      // postFrameCallback se ré-arme à chaque rebuild, GoRouter dédupe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RoutePaths.veilleDashboard);
      });
    } else if (editMode && activeCfgValue != null && state.selectedTheme == null) {
      // Mode édition : hydrate l'état une seule fois depuis la config active.
      // Idempotent côté notifier (no-op si selectedTheme déjà set).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.hydrateFromActiveConfig(activeCfgValue);
      });
    }

    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RoutePaths.feed);
      }
    }

    Future<void> handleSubmit() async {
      try {
        if (editMode) {
          // Mode édition : pas de génération première livraison ni de modal
          // notif (le user n'est plus en onboarding). Juste UPSERT + retour
          // dashboard avec confirmation.
          await notifier.submit();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Veille mise à jour')),
          );
          context.go(RoutePaths.veilleDashboard);
          return;
        }
        final deliveryId = await notifier.submitAndGenerateFirst();
        if (!context.mounted) return;
        notifier.setLoadingFrom(4);

        // Délai 1 s pour laisser le loading screen apparaître avant la modal,
        // sinon la modal flashe par-dessus la transition AnimatedSwitcher.
        unawaited(Future<void>.delayed(const Duration(seconds: 1), () async {
          if (!context.mounted) return;
          await showNotificationActivationModal(
            context,
            ref,
            trigger: ActivationTrigger.veille,
          );
        }));

        if (deliveryId != null) {
          await _pollFirstDelivery(
            context: context,
            ref: ref,
            deliveryId: deliveryId,
            onTimeoutMessage:
                "On t'enverra une notif quand ta veille est prête.",
          );
        }
        if (!context.mounted) return;
        context.go(RoutePaths.veilleDashboard);
      } on VeilleApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible d\'enregistrer ta veille (${e.statusCode ?? '?'}). Réessaie.',
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Erreur réseau. Vérifie ta connexion et réessaie.',
            ),
          ),
        );
      } finally {
        if (context.mounted) notifier.setLoadingFrom(null);
      }
    }

    Widget body;
    String key;
    if (state.isLoading) {
      body = FlowLoadingScreen(from: state.loadingFrom!);
      key = 'load-${state.loadingFrom}';
    } else if (state.previewPresetId != null) {
      body = Step15PresetPreviewScreen(
        presetSlug: state.previewPresetId!,
        onClose: close,
      );
      key = 'preset-${state.previewPresetId}';
    } else {
      switch (state.step) {
        case 1:
          body = Step1ThemeScreen(onClose: close);
          break;
        case 2:
          body = Step2SuggestionsScreen(onClose: close);
          break;
        case 3:
          body = Step3SourcesScreen(onClose: close);
          break;
        case 4:
        default:
          body = Step4FrequencyScreen(
            onClose: close,
            onSubmit: handleSubmit,
          );
      }
      key = 'step-${state.step}';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2E8D5),
      body: SafeArea(
        bottom: true,
        child: AnimatedSwitcher(
          duration: FacteurDurations.medium,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(key),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Poll `/deliveries/{id}` jusqu'à `succeeded` (succès) ou 90 s écoulées.
/// Backoff 2 s pendant les 20 premières secondes (≈ p50 de la génération),
/// puis 5 s ensuite — l'objectif est de limiter la charge serveur quand le
/// volume utilisateur scalera. Renvoie quand le poll s'arrête (état terminal,
/// timeout ou widget unmount). Affiche un snackbar en cas de timeout.
Future<void> _pollFirstDelivery({
  required BuildContext context,
  required WidgetRef ref,
  required String deliveryId,
  required String onTimeoutMessage,
}) async {
  const totalBudget = Duration(seconds: 90);
  const fastInterval = Duration(seconds: 2);
  const slowInterval = Duration(seconds: 5);
  const fastWindow = Duration(seconds: 20);

  final repo = ref.read(veilleRepositoryProvider);
  final start = DateTime.now();

  while (true) {
    if (!context.mounted) return;
    final elapsed = DateTime.now().difference(start);
    if (elapsed >= totalBudget) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(onTimeoutMessage)),
      );
      return;
    }

    try {
      final delivery = await repo.getDelivery(deliveryId);
      if (delivery.generationState == VeilleGenerationState.succeeded) {
        return;
      }
      if (delivery.generationState == VeilleGenerationState.failed) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La génération a échoué. On retentera à la prochaine livraison.',
            ),
          ),
        );
        return;
      }
    } on VeilleApiException {
      // Erreur transitoire — on continue à poll, le timeout protégera.
    }

    final next = elapsed < fastWindow ? fastInterval : slowInterval;
    await Future<void>.delayed(next);
  }
}
