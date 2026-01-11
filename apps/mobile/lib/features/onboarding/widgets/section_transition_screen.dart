import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';

/// Écran de transition entre les sections de l'onboarding
/// Affiche un emoji thématique et le numéro de section avec auto-transition
class SectionTransitionScreen extends StatefulWidget {
  final String emoji;
  final String title;
  final OnboardingSection section;
  final VoidCallback onContinue;
  final Duration autoContinueDuration;

  const SectionTransitionScreen({
    super.key,
    required this.emoji,
    required this.title,
    required this.section,
    required this.onContinue,
    this.autoContinueDuration = const Duration(seconds: 2),
  });

  @override
  State<SectionTransitionScreen> createState() =>
      _SectionTransitionScreenState();
}

class _SectionTransitionScreenState extends State<SectionTransitionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    // Démarrer l'animation
    _controller.forward();

    // Auto-transition après le délai
    Future.delayed(widget.autoContinueDuration, () {
      if (mounted) {
        widget.onContinue();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onContinue,
      child: Container(
        color: context.facteurColors.backgroundPrimary,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji animé
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 80),
                  ),
                );
              },
            ),

            const SizedBox(height: FacteurSpacing.space8),

            // Titre de la section
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: FacteurSpacing.space4),

            // Indicateur de section
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FacteurSpacing.space3,
                  vertical: FacteurSpacing.space2,
                ),
                decoration: BoxDecoration(
                  color: context.facteurColors.surface,
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                ),
                child: Text(
                  'Section ${widget.section.number}/3',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.facteurColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
