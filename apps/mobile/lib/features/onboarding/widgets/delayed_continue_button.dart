import 'package:flutter/material.dart';

import '../onboarding_strings.dart';

/// A "Continuer" button that appears after a delay on first selection,
/// but is shown immediately when revisiting an already-answered question.
///
/// Used on auto-advance screens so that when a user navigates back
/// to an already-answered question, they can tap "Continuer" to
/// move forward without re-selecting the same choice.
class DelayedContinueButton extends StatefulWidget {
  final bool visible;
  final VoidCallback onPressed;
  final Duration delay;

  const DelayedContinueButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.delay = const Duration(seconds: 1),
  });

  @override
  State<DelayedContinueButton> createState() => _DelayedContinueButtonState();
}

class _DelayedContinueButtonState extends State<DelayedContinueButton> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    // Already answered when screen mounts → show immediately
    if (widget.visible) {
      _show = true;
    }
  }

  @override
  void didUpdateWidget(DelayedContinueButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      // Selection just happened → delay before showing
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _show = true);
      });
    } else if (!widget.visible && oldWidget.visible) {
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _show ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !_show,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: widget.onPressed,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
              ),
              child: const Text(OnboardingStrings.continueButton),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
