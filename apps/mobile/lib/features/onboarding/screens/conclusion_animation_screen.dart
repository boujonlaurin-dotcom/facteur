import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../providers/conclusion_notifier.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/animated_message_text.dart';
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
          ConclusionError(:final message) => _ErrorView(errorMessage: message),
        },
      ),
    );
  }

  void _completeOnboarding() {
    // Marquer l'onboarding comme terminé dans l'auth state
    ref.read(authStateProvider.notifier).setOnboardingCompleted();

    // Effacer les données locales temporaires
    ref.read(onboardingProvider.notifier).clearSavedData();

    // Naviguer vers le feed avec paramètre welcome
    // context.go() remplace toute la stack (pas de back vers onboarding)
    context.go('${RoutePaths.feed}?welcome=true');
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

/// Vue d'erreur avec options de retry
class _ErrorView extends ConsumerWidget {
  final String errorMessage;

  const _ErrorView({required this.errorMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Emoji d'erreur
          const Text('⚠️', style: TextStyle(fontSize: 64)),

          const SizedBox(height: FacteurSpacing.space6),

          // Titre
          Text(
            'Oups, un problème est survenu',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Message d'erreur
          Text(
            'Impossible de sauvegarder ton profil',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          if (errorMessage.isNotEmpty) ...[
            const SizedBox(height: FacteurSpacing.space3),
            Container(
              padding: const EdgeInsets.all(FacteurSpacing.space3),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.small),
              ),
              child: Text(
                errorMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const Spacer(flex: 3),

          // Bouton réessayer
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(conclusionNotifierProvider.notifier).retry();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: colors.primary,
              ),
              child: const Text(
                'Réessayer',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Bouton continuer quand même
          TextButton(
            onPressed: () {
              ref.read(conclusionNotifierProvider.notifier).continueAnyway();
            },
            child: Text(
              'Continuer quand même',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
