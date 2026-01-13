import 'package:flutter/material.dart';

import '../../../config/theme.dart';

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
    this.autoContinueDelay = const Duration(seconds: 3),
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

          // Emoji de célébration
          FadeTransition(
            opacity: _fadeAnimation,
            child: const Text('✨', style: TextStyle(fontSize: 64)),
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
                child: const Text('Continuer'),
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
      title: 'Le signal, pas le bruit.',
      message:
          'Nous allons drastiquement filtrer l\'info pour vous.\n\nVotre feed ne gardera que les signaux faibles pertinents, zéro buzz.',
    ),
    'bias': ReactionContent(
      title: 'La transparence avant tout.',
      message:
          'Facteur affiche systématiquement le positionnement des sources.\n\nVous saurez toujours d\'où vient l\'information.',
    ),
    'anxiety': ReactionContent(
      title: 'Prendre de la hauteur.',
      message:
          'Nous privilégions le temps long et l\'analyse.\n\nLe meilleur remède au chaos immédiat est de comprendre ses racines.',
    ),
  };
}

/// Messages de réaction pour la Section 2 (préférences d'app)
/// Basés sur la combinaison de diagnostic (objective) + thèmes
class PreferencesReactionMessages {
  static ReactionContent getReaction({
    required String? perspective,
    required String? responseStyle,
    required String? contentRecency,
    String? objective, // Diagnostic: noise, bias, anxiety
    List<String>? themes,
  }) {
    // Compound logic: Diagnostic + Themes
    final hasTech = themes?.contains('tech') ?? false;
    final hasGeopolitics =
        themes?.contains('politics') ?? themes?.contains('society') ?? false;

    // Case: Bruit + Tech
    if (objective == 'noise' && hasTech) {
      return const ReactionContent(
        title: 'Zéro buzz, zéro bruit.',
        message:
            'Nous allons drastiquement filtrer le signal.\n\nVotre veille Tech ne gardera que les signaux faibles pertinents.',
      );
    }

    // Case: Anxiété + Géopo
    if (objective == 'anxiety' && hasGeopolitics) {
      return const ReactionContent(
        title: 'Prendre de la hauteur.',
        message:
            'Le meilleur remède au chaos immédiat.\n\nNos sources Slow Media vous donneront le temps de comprendre.',
      );
    }

    // Case: Biais (transparency focus)
    if (objective == 'bias') {
      return const ReactionContent(
        title: 'Transparence totale.',
        message:
            'Facteur affiche systématiquement le positionnement des sources.\n\nVous saurez toujours d\'où vient l\'information.',
      );
    }

    // Fallback: Use perspective/style preferences
    final isBigPicture = perspective == 'big_picture';
    final isDecisive = responseStyle == 'decisive';
    final isRecent = contentRecency == 'recent';

    if (isBigPicture && isDecisive && isRecent) {
      return const ReactionContent(
        title: 'Vous allez droit au but !',
        message:
            'Vous aimez avoir une vision claire et actuelle des choses.\n\nOn va vous préparer un feed concis et percutant.',
      );
    }

    if (isBigPicture && isDecisive && !isRecent) {
      return const ReactionContent(
        title: 'L\'essentiel, sans le bruit.',
        message:
            'Vous cherchez des insights clairs qui traversent le temps.\n\nParfait pour construire une vraie vision.',
      );
    }

    if (isBigPicture && !isDecisive) {
      return const ReactionContent(
        title: 'Vous aimez comprendre le contexte !',
        message:
            'Une vue d\'ensemble avec toutes les perspectives.\n\nOn va enrichir votre compréhension du monde.',
      );
    }

    if (!isBigPicture && isDecisive && isRecent) {
      return const ReactionContent(
        title: 'Efficace et précis !',
        message:
            'Vous voulez les détails qui comptent, avec des avis clairs.\n\nOn va creuser les sujets pour vous.',
      );
    }

    if (!isBigPicture && !isDecisive && !isRecent) {
      return const ReactionContent(
        title: 'Vous préférez la profondeur !',
        message:
            'La nuance et le détail, pour vraiment maîtriser les sujets.\n\nDes contenus riches qui font réfléchir.',
      );
    }

    // Message par défaut
    return const ReactionContent(
      title: 'On vous connaît mieux !',
      message:
          'Vos préférences vont nous aider à personnaliser votre expérience.\n\nEncore quelques questions et on y est.',
    );
  }
}

class ReactionContent {
  final String title;
  final String message;

  const ReactionContent({required this.title, required this.message});
}
