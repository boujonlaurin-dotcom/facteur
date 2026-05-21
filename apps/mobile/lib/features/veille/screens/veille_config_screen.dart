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
import 'transitions/flow_loading_screen.dart';
import 'veille_intro_screen.dart';

/// Host du flow de configuration de la veille (Story 23.2 PR-4).
///
/// - Si l'utilisateur a déjà une config active (`GET /api/veille/config` =
///   200) en mode création (`editMode == false`), on retourne immédiatement
///   au flux continu : la veille y apparaît comme slot de la Tournée du jour.
/// - Si 404 (pas de veille), on affiche l'intro puis le flow 3-steps.
/// - En mode édition, l'état est hydraté depuis la config active et l'intro
///   est skipée.
class VeilleConfigScreen extends ConsumerWidget {
  const VeilleConfigScreen({super.key, this.editMode = false});

  /// Mode édition : `true` quand la route reçoit `?mode=edit` depuis
  /// l'entrée "Modifier la veille" (Mes intérêts → menu favori veille).
  final bool editMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final activeConfig = ref.watch(veilleActiveConfigProvider);

    final activeCfgValue = activeConfig.valueOrNull;
    if (!editMode && activeCfgValue != null) {
      // Une config existe déjà → le user n'a rien à reconfigurer ici, on
      // retourne au flux continu (où la veille vit comme slot Tournée).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RoutePaths.fluxContinu);
      });
    } else if (editMode &&
        activeCfgValue != null &&
        state.selectedTheme == null) {
      // Mode édition : hydrate l'état une fois depuis la config active.
      // Idempotent côté notifier (no-op si selectedTheme déjà set).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.hydrateFromActiveConfig(activeCfgValue);
      });
    }

    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RoutePaths.fluxContinu);
      }
    }

    Future<void> handleSubmit() async {
      try {
        await notifier.submit();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(editMode ? 'Veille mise à jour' : 'Veille créée'),
          ),
        );
        context.go(RoutePaths.fluxContinu);
      } on VeilleApiException catch (e) {
        if (!context.mounted) return;
        final message = e.statusCode == 422
            ? 'Sélectionne au moins un sujet, une source ou un angle pour ta veille.'
            : 'Impossible d\'enregistrer ta veille (${e.statusCode ?? '?'}). Réessaie.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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
    if (!editMode &&
        !state.introCompleted &&
        activeCfgValue == null &&
        !activeConfig.isLoading) {
      // Premier accès sans config : on cadre via l'intro avant Step1.
      body = VeilleIntroScreen(
        onClose: close,
        onStart: notifier.completeIntro,
      );
      key = 'intro';
    } else if (state.previewPresetId != null) {
      body = Step15PresetPreviewScreen(
        presetSlug: state.previewPresetId!,
        onClose: close,
      );
      key = 'preset-${state.previewPresetId}';
    } else if (state.transitionFrom != null) {
      // Story 23.3 : transition LLM (HaloLoader + bifurcation pour from=1).
      body = FlowLoadingScreen(
        from: state.transitionFrom!,
        onChoosePrecisier: () => notifier.exitTransition(toStep: 2),
        onChooseSkipToSources: () {
          notifier.exitTransition(toStep: 3, skipStep2: true);
          notifier.startTransition(2);
        },
        onSourcesReady: () => notifier.exitTransition(toStep: 3),
      );
      key = 'transition-${state.transitionFrom}';
    } else {
      switch (state.step) {
        case 1:
          body = Step1ThemeScreen(onClose: close);
          break;
        case 2:
          body = Step2SuggestionsScreen(onClose: close);
          break;
        case 3:
        default:
          body = Step3SourcesScreen(onClose: close, onSubmit: handleSubmit);
          break;
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
