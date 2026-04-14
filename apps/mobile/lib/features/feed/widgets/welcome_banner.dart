import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Banner de bienvenue affiché après l'onboarding
///
/// S'affiche en haut de l'écran avec une animation slide et se ferme
/// automatiquement après [duration] ou sur tap
class WelcomeBanner extends StatefulWidget {
  /// Message secondaire personnalisé selon l'objectif
  final String? secondaryMessage;

  /// Callback appelé lors du dismiss
  final VoidCallback onDismiss;

  /// Durée avant auto-dismiss
  final Duration duration;

  const WelcomeBanner({
    super.key,
    this.secondaryMessage,
    required this.onDismiss,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<WelcomeBanner> createState() => _WelcomeBannerState();
}

class _WelcomeBannerState extends State<WelcomeBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();

    // Animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Slide animation (entrée depuis le haut)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);

    // Démarrer l'animation d'entrée
    _controller.forward();

    // Timer pour auto-dismiss après la durée spécifiée
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  /// Ferme le banner avec animation
  Future<void> _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;

    // Animation de sortie (inverse)
    await _controller.reverse();

    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vérifier si animations réduites activées
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return SlideTransition(
      position: reduceMotion
          ? const AlwaysStoppedAnimation(Offset.zero)
          : _slideAnimation,
      child: FadeTransition(
        opacity:
            reduceMotion ? const AlwaysStoppedAnimation(1.0) : _fadeAnimation,
        child: Semantics(
          label: 'Bienvenue dans Facteur. Ton feed personnalisé est prêt.',
          button: true,
          onTap: _dismiss,
          child: GestureDetector(
            onTap: _dismiss,
            child: Container(
              margin: const EdgeInsets.all(FacteurSpacing.space4),
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE07A5F), // Terracotta
                    Color(0xFFD06A4F), // Terracotta plus foncé
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
                boxShadow: [
                  BoxShadow(
                    color: context.facteurColors.textSecondary
                        .withOpacity(0.7),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Emoji de bienvenue
                  const Text(
                    '👋',
                    style: TextStyle(fontSize: 28),
                  ),
                  const SizedBox(width: FacteurSpacing.space3),

                  // Textes
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Bienvenue dans Facteur !',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: FacteurSpacing.space1),
                        Text(
                          widget.secondaryMessage ??
                              'Ton feed personnalisé est prêt 🎉',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                        ),
                      ],
                    ),
                  ),

                  // Bouton fermer
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _dismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Génère un message secondaire personnalisé selon l'objectif de l'utilisateur
String getWelcomeSecondaryMessage(String? objective) {
  switch (objective) {
    case 'learn':
      return 'Ton feed est prêt pour apprendre 📚';
    case 'culture':
      return 'Enrichis ta culture avec ton feed 🎭';
    case 'work':
      return 'Reste informé pour ton travail 💼';
    default:
      return 'Ton feed personnalisé est prêt 🎉';
  }
}
