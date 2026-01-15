import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../onboarding_strings.dart';

/// Widget qui affiche des messages qui changent avec animation
/// Cycle de messages pendant la conclusion de l'onboarding
class AnimatedMessageText extends StatefulWidget {
  const AnimatedMessageText({super.key});

  @override
  State<AnimatedMessageText> createState() => _AnimatedMessageTextState();
}

class _AnimatedMessageTextState extends State<AnimatedMessageText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentMessageIndex = 0;

  final List<String> _messages = OnboardingStrings.conclusionMessages;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600), // Slower fade
      vsync: this,
    );
    _startSequence();
  }

  Future<void> _startSequence() async {
    for (int i = 0; i < _messages.length; i++) {
      if (!mounted) return;

      setState(() => _currentMessageIndex = i);
      try {
        await _controller.forward(from: 0.0).orCancel;
      } on TickerCanceled {
        return;
      }

      if (!mounted) return;
      // Longer hold time for readability
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;
      if (i < _messages.length - 1) {
        try {
          await _controller.reverse().orCancel;
        } on TickerCanceled {
          return;
        }

        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: Text(
        _messages[_currentMessageIndex],
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.facteurColors.textSecondary,
              fontWeight: FontWeight.w500, // Slightly bolder
              letterSpacing: 0.5,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
