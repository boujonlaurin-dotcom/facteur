import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../onboarding_strings.dart';

/// Écran de réaction personnalisée après une réponse clé
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
    this.autoContinueDelay = const Duration(seconds: 4),
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

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _buttonAnimation = CurvedAnimation(
      parent: _buttonController,
      curve: Curves.easeOut,
    );

    _fadeController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _buttonController.forward();
        }
      });
    });

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

          FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space8),

          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

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
/// Supports multi-select: if multiple objectives, shows combined message
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

  /// Get reaction for multi-select objectives
  static ReactionContent getReaction(List<String> objectives) {
    if (objectives.length > 1) {
      return const ReactionContent(
        title: OnboardingStrings.r1MultiTitle,
        message: OnboardingStrings.r1MultiMessage,
      );
    }
    final key = objectives.isNotEmpty ? objectives.first : 'noise';
    return messages[key] ?? messages['noise']!;
  }
}

class ReactionContent {
  final String title;
  final String message;

  const ReactionContent({required this.title, required this.message});
}
