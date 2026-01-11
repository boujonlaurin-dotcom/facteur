import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Widget qui affiche des messages qui changent avec animation
/// Cycle de 3 messages pendant la conclusion de l'onboarding
class AnimatedMessageText extends StatefulWidget {
  const AnimatedMessageText({super.key});

  @override
  State<AnimatedMessageText> createState() => _AnimatedMessageTextState();
}

class _AnimatedMessageTextState extends State<AnimatedMessageText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentMessageIndex = 0;

  final List<String> _messages = const [
    'Chargement de tes sources...',
    'Configuration de tes préférences...',
    'Préparation de ton feed...',
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    for (int i = 0; i < _messages.length; i++) {
      if (!mounted) return;

      // Fade in
      setState(() => _currentMessageIndex = i);
      await _controller.forward(from: 0.0);

      // Hold
      await Future.delayed(const Duration(milliseconds: 900));

      // Fade out (sauf pour le dernier message)
      if (i < _messages.length - 1) {
        await _controller.reverse();
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    // Garder le dernier message visible
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Text(
        _messages[_currentMessageIndex],
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.facteurColors.textSecondary,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
