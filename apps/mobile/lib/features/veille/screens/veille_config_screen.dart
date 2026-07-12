import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../flux_continu/providers/tournee_order_prefs_provider.dart';
import '../providers/veille_active_config_provider.dart';
import '../providers/veille_config_provider.dart';
import '../repositories/veille_repository.dart';
import '../../lettres/widgets/progress_toast.dart';
import '../widgets/veille_widgets.dart';
import 'steps/step1_5_preset_preview_screen.dart';
import 'steps/step1_theme_screen.dart';
import 'steps/step2_suggestions_screen.dart';
import 'steps/step3_sources_screen.dart';
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
        !activeConfig.isLoading &&
        activeCfgValue != null &&
        state.selectedTheme == null) {
      // Mode édition : hydrate l'état une fois depuis la config active, mais
      // seulement quand le chargement est terminé (Story 23.4 — sinon flash
      // d'un Step 1 vide). Idempotent côté notifier (no-op si selectedTheme set).
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
        final cfg = await notifier.submit();
        if (!context.mounted) return;
        // Sources niche dont le flux RSS est introuvable : on garde l'utilisateur
        // sur l'étape Sources (recherche/ajout) au lieu de filer vers la Tournée,
        // pour qu'il puisse en chercher d'autres (plan V0, Problème 1).
        if (cfg != null && cfg.unconnectedSources.isNotEmpty) {
          final n = cfg.unconnectedSources.length;
          final s = n > 1 ? 's' : '';
          final verb = n > 1 ? "n'ont" : "n'a";
          notifier.goToStep(3);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(
                '$n source$s $verb pas pu être connectée$s '
                '(flux RSS introuvable). Tu peux en chercher d\'autres '
                'ci-dessous.',
              ),
            ),
          );
          return;
        }
        // À la **création** (pas en édition), on propose d'épingler la veille en
        // tête de la Tournée. Si oui → insertion en position #1 (réutilise le
        // pattern `_onAddVeille` de manage_favorites_sheet).
        if (!editMode) {
          await _maybePromptPinTournee(context, ref);
          if (!context.mounted) return;
        }
        showProgressToast(
          context,
          level: ProgressToastLevel.step,
          stepNum: '01',
          stepTitle: editMode ? 'Veille mise à jour' : 'Veille créée',
          accentColor: FacteurColors.veille,
        );
        context.go(RoutePaths.fluxContinu);
      } on VeilleApiException catch (e) {
        if (!context.mounted) return;
        final message = e.statusCode == 422
            ? 'Sélectionne au moins un sujet, une source ou un angle pour ta veille.'
            : 'Impossible d\'enregistrer ta veille (${e.statusCode ?? '?'}). Réessaie.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur réseau. Vérifie ta connexion et réessaie.'),
          ),
        );
      }
    }

    Widget body;
    String key;
    if (editMode && state.selectedTheme == null && activeConfig.isLoading) {
      // Mode édition : on charge la config active — scaffold de chargement au
      // lieu d'un flash de Step 1 vide (Story 23.4).
      body = Column(
        children: [
          VeilleStepHeader(step: 1, canGoBack: false, onClose: close),
          const Expanded(child: VeilleStepSkeleton()),
        ],
      );
      key = 'edit-loading';
    } else if (editMode &&
        state.selectedTheme == null &&
        activeConfig.hasError) {
      // GET /config a échoué en édition → écran erreur + retry.
      body = _EditLoadError(
        onClose: close,
        onRetry: () => ref.invalidate(veilleActiveConfigProvider),
      );
      key = 'edit-error';
    } else if (!editMode &&
        !state.introCompleted &&
        activeCfgValue == null &&
        !activeConfig.isLoading) {
      // Premier accès sans config : on cadre via l'intro avant Step1.
      body = VeilleIntroScreen(onClose: close, onStart: notifier.completeIntro);
      key = 'intro';
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
          child: KeyedSubtree(key: ValueKey(key), child: body),
        ),
      ),
    );
  }
}

/// Propose d'épingler la veille en **tête** de la Tournée du jour, juste après
/// sa création. Sur « Oui » : `markCustomized()` + `setHidden(false)` +
/// `setOrder([veille, ...reste])` → la veille passe en position #1. Sur « Non »
/// ou dismiss : no-op (la veille reste accessible via « Mes intérêts »).
Future<void> _maybePromptPinTournee(BuildContext context, WidgetRef ref) async {
  final pin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFF2E8D5),
      title: Text(
        'Épingler à ta Tournée ?',
        style: GoogleFonts.fraunces(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2C2A29),
        ),
      ),
      content: Text(
        'Ta veille apparaîtra en tête de ta Tournée du jour, avant les autres '
        'sections.',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          height: 1.4,
          color: const Color(0xFF5D5B5A),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Plus tard',
            style: GoogleFonts.dmSans(color: const Color(0xFF5D5B5A)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Épingler',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              color: FacteurColors.veille,
            ),
          ),
        ),
      ],
    ),
  );

  if (pin != true) return;

  final notifier = ref.read(tourneeOrderPrefsProvider.notifier);
  await notifier.markCustomized();
  await notifier.setHidden(kTourneeVeilleKey, false);
  final rest = ref
      .read(tourneeOrderPrefsProvider)
      .order
      .where((k) => k != kTourneeVeilleKey)
      .toList();
  await notifier.setOrder([kTourneeVeilleKey, ...rest]);
}

/// Story 23.4 — écran d'erreur (mode édition) quand `GET /config` échoue.
class _EditLoadError extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onRetry;
  const _EditLoadError({required this.onClose, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VeilleStepHeader(step: 1, canGoBack: false, onClose: onClose),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 40,
                    color: Color(0xFF8B7E63),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Impossible de charger ta veille',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2C2A29),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vérifie ta connexion et réessaie.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: const Color(0xFF5D5B5A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  VeilleCtaButton(label: 'Réessayer', onPressed: onRetry),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
