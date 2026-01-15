import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../onboarding_strings.dart';

/// Écran de réaction personnalisée après une réponse clé
/// Affiche un message engageant avec animation de fade-in
class ReactionScreen extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onContinue;
  final bool autoContinue;
  final Duration autoContinueDelay;

  const ReactionScreen({
    super.key,
    required this.title,
    required this.message,
    required this.onContinue,
    this.autoContinue = false,
    this.autoContinueDelay =
        const Duration(seconds: 4), // Augmenté un peu pour lire
  });

  @override
  State<ReactionScreen> createState() => _ReactionScreenState();
}

class _ReactionScreenState extends State<ReactionScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _buttonController;
  late Animation<double> _buttonAnimation;

  @override
  void initState() {
    super.initState();

    // Animation du texte
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Animation du bouton (apparaît après le texte)
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _buttonAnimation = CurvedAnimation(
      parent: _buttonController,
      curve: Curves.easeOut,
    );

    // Démarrer les animations
    _fadeController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _buttonController.forward();
        }
      });
    });

    // Auto-continue si activé
    if (widget.autoContinue) {
      Future.delayed(widget.autoContinueDelay, () {
        if (mounted) {
          widget.onContinue();
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Logo Facteur animé (fade in)
          FadeTransition(
            opacity: _fadeAnimation,
            child: const FacteurLogo(size: 80),
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Titre de la réaction
          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Message personnalisé
          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              widget.message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: context.facteurColors.textSecondary,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
          ),

          const Spacer(flex: 3),

          // Bouton continuer
          FadeTransition(
            opacity: _buttonAnimation,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(OnboardingStrings.continueButton),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}

/// Messages de réaction pour chaque réponse à Q1 (Diagnostic)
class ObjectiveReactionMessages {
  static const Map<String, ReactionContent> messages = {
    'noise': ReactionContent(
      title: OnboardingStrings.r1NoiseTitle,
      message: OnboardingStrings.r1NoiseMessage,
    ),
    'bias': ReactionContent(
      title: OnboardingStrings.r1BiasTitle,
      message: OnboardingStrings.r1BiasMessage,
    ),
    'anxiety': ReactionContent(
      title: OnboardingStrings.r1AnxietyTitle,
      message: OnboardingStrings.r1AnxietyMessage,
    ),
  };
}

/// Messages de réaction pour la Section 2 (préférences d'app)
/// Basés uniquement sur la dernière réponse (contentRecency) pour éviter les répétitions
class PreferencesReactionMessages {
  static ReactionContent getReaction({required String? contentRecency}) {
    // Simple logic: based only on contentRecency (last answered question)
    if (contentRecency == 'recent') {
      return const ReactionContent(
        title: OnboardingStrings.r2RecentTitle,
        message: OnboardingStrings.r2RecentMessage,
      );
    } else if (contentRecency == 'timeless') {
      return const ReactionContent(
        title: OnboardingStrings.r2TimelessTitle,
        message: OnboardingStrings.r2TimelessMessage,
      );
    }

    // Message par défaut
    return const ReactionContent(
      title: OnboardingStrings.r2DefaultTitle,
      message: OnboardingStrings.r2DefaultMessage,
    );
  }
}

class ReactionContent {
  final String title;
  final String message;

  const ReactionContent({required this.title, required this.message});
}
