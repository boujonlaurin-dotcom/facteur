import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../shared/strings/loader_error_strings.dart';
import '../../../shared/widgets/states/laurin_fallback_view.dart';
import '../providers/conclusion_live_feed_provider.dart';
import '../providers/conclusion_notifier.dart';
import '../providers/onboarding_proof_cache_provider.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/animated_message_text.dart';
import '../widgets/conclusion_live_feed.dart';
import '../widgets/minimal_loader.dart';

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
    // Capture la liste des customs échoués AVANT clearSavedData pour pouvoir
    // afficher le résumé utilisateur ("tu pourras les réajouter").
    final failedCustomTopics = List<String>.from(
      ref.read(onboardingProvider).failedCustomTopics,
    );

    // Effacer les données locales temporaires
    ref.read(onboardingProvider.notifier).clearSavedData();
    ref.read(onboardingProvider.notifier).clearFailedCustomTopics();
    ref.read(onboardingProofCacheProvider.notifier).state = {};

    // Armer le flow post-onboarding (dialog customs échoués + modales thème &
    // notifications) AVANT de basculer l'auth state : on le veut posé avant la
    // redirection router vers Essentiel. Les modales seront jouées par
    // FluxContinuScreen une fois ses données chargées, derrière elles — plus
    // aucun écran gris, plus aucun contexte démonté.
    ref.read(postOnboardingFlowPendingProvider.notifier).state =
        failedCustomTopics;

    // Marquer l'onboarding comme terminé : la règle 5 du redirect route alors
    // l'écran sous-jacent vers Essentiel (qui se monte et charge ses données).
    await ref.read(authStateProvider.notifier).setOnboardingCompleted();

    // context.go() remplace toute la stack pour bloquer le back vers
    // l'onboarding (idempotent avec la redirection router déjà déclenchée).
    if (mounted) {
      context.go(RoutePaths.fluxContinu);
    }
  }
}

/// Vue de chargement : feed vivant (vrais titres des sources choisies) quand
/// des données sont disponibles, sinon loader minimaliste classique.
class _LoadingView extends ConsumerWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch = garde aussi le FutureProvider autoDispose en vie pendant
    // toute l'animation (le fetch démarre au premier build).
    final entries = ref.watch(conclusionLiveFeedEntriesProvider);

    if (entries.isEmpty) {
      // Aucune source / endpoint pas encore répondu / erreur réseau :
      // fallback sur l'animation historique.
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
        child: ConclusionLiveFeed(entries: entries),
      ),
    );
  }
}
