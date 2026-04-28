import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../../../shared/strings/loader_error_strings.dart';
import '../../../shared/widgets/states/laurin_fallback_view.dart';
import '../providers/conclusion_notifier.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/animated_message_text.dart';
import '../widgets/minimal_loader.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../widgets/theme_choice_bottom_sheet.dart';

/// Écran d'animation de conclusion de l'onboarding
/// Affiche une animation élégante pendant la sauvegarde des réponses
class ConclusionAnimationScreen extends ConsumerStatefulWidget {
  const ConclusionAnimationScreen({super.key});

  @override
  ConsumerState<ConclusionAnimationScreen> createState() =>
      _ConclusionAnimationScreenState();
}

class _ConclusionAnimationScreenState
    extends ConsumerState<ConclusionAnimationScreen> {
  @override
  void initState() {
    super.initState();
    // Démarrer le processus de conclusion dès l'affichage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(conclusionNotifierProvider.notifier).startConclusion();
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    final conclusionState = ref.watch(conclusionNotifierProvider);
    final colors = context.facteurColors;

    // Écouter les changements d'état pour naviguer
    ref.listen<ConclusionState>(conclusionNotifierProvider, (previous, next) {
      if (next is ConclusionSuccess) {
        _completeOnboarding();
      }
    });

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: switch (conclusionState) {
          ConclusionLoading() => const _LoadingView(),
          ConclusionSuccess() =>
            const _LoadingView(), // Garde l'animation pendant la transition
          ConclusionError() => LaurinFallbackView(
              title: OnboardingFallbackStrings.title,
              subtitle: OnboardingFallbackStrings.subtitle,
              onRetry: () =>
                  ref.read(conclusionNotifierProvider.notifier).retry(),
            ),
        },
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    // Marquer l'onboarding comme terminé dans l'auth state
    await ref.read(authStateProvider.notifier).setOnboardingCompleted();

    // Capture la liste des customs échoués AVANT clearSavedData pour pouvoir
    // afficher le résumé utilisateur ("tu pourras les réajouter").
    final failedCustomTopics =
        List<String>.from(ref.read(onboardingProvider).failedCustomTopics);

    // Effacer les données locales temporaires
    ref.read(onboardingProvider.notifier).clearSavedData();
    ref.read(onboardingProvider.notifier).clearFailedCustomTopics();

    if (mounted && failedCustomTopics.isNotEmpty) {
      // Dialog bloquant au lieu d'une SnackBar : les bottom sheets suivants
      // (thème, notifications) poseraient un barrier qui masquerait la
      // SnackBar. Le dialog garantit que l'utilisateur voit l'info.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            OnboardingFallbackStrings.failedCustomTopicsMessage(
              failedCustomTopics,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    // Proposer le choix du thème avant de naviguer
    if (mounted) {
      await showThemeChoiceBottomSheet(context, ref);
    }

    // Proposer l'activation des notifications (une seule fois, post-onboarding)
    if (mounted) {
      await showNotificationActivationModal(
        context,
        ref,
        trigger: ActivationTrigger.onboarding,
      );
    }

    // Naviguer vers le digest avec paramètre first pour welcome experience
    // context.go() remplace toute la stack (pas de back vers onboarding)
    if (mounted) {
      context.go('${RoutePaths.digest}?first=true');
    }
  }
}

/// Vue de chargement avec animation centrée
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animation minimaliste et élégante
            MinimalLoader(),

            SizedBox(height: FacteurSpacing.space4),

            // Messages animés
            AnimatedMessageText(),
          ],
        ),
      ),
    );
  }
}

