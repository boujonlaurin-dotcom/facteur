import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/veille_active_config_provider.dart';
import '../providers/veille_config_provider.dart';
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
  const VeilleConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final activeConfig = ref.watch(veilleActiveConfigProvider);

    // Si une config est déjà active, le user n'a rien à reconfigurer →
    // redirect vers le dashboard. context.go est idempotent, donc même si le
    // postFrameCallback se ré-arme à chaque rebuild, GoRouter dédupe.
    if (activeConfig.valueOrNull != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RoutePaths.veilleDashboard);
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
        await notifier.submit();
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
