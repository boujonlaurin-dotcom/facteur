import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Animated streak celebration widget for the closure screen
/// Displays a large flame icon with animated scaling and counting number
class StreakCelebration extends StatefulWidget {
  final int streakCount;
  final String? streakMessage;
  final VoidCallback? onAnimationComplete;

  const StreakCelebration({
    super.key,
    required this.streakCount,
    this.streakMessage,
    this.onAnimationComplete,
  });

  @override
  State<StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<StreakCelebration>
    with TickerProviderStateMixin {
  late AnimationController _flameController;
  late AnimationController _numberController;
  late AnimationController _messageController;
  late Animation<double> _flameScaleAnimation;
  late Animation<double> _flameGlowAnimation;
  late Animation<double> _numberOpacityAnimation;
  late Animation<double> _messageOpacityAnimation;
  int _displayedNumber = 0;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimationSequence();
  }

  void _setupAnimations() {
    // Flame scale animation: 0-500ms (bounce effect)
    _flameController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Number fade-in: 500-800ms
    _numberController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Message fade-in: 800-1200ms
    _messageController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Scale from 0.5 to 1.2 with bounce, then settle to 1.0
    _flameScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60, // 0-300ms
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40, // 300-500ms
      ),
    ]).animate(_flameController);

    // Subtle pulsing glow effect
    _flameGlowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _flameController,
        curve: Curves.easeInOut,
      ),
    );

    // Number fades in
    _numberOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _numberController,
        curve: Curves.easeOut,
      ),
    );

    // Message fades in
    _messageOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _messageController,
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _startAnimationSequence() async {
    // Start flame animation (0-500ms)
    await _flameController.forward();

    // Wait for flame to bounce (300ms), then start number animation
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Count up the number
    _countUpNumber();

    // Start number fade-in (500-800ms)
    await _numberController.forward();
    if (!mounted) return;

    // Wait a bit, then start message animation (800-1200ms)
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await _messageController.forward();
    if (!mounted) return;

    // Animation complete callback
    widget.onAnimationComplete?.call();
  }

  void _countUpNumber() {
    const duration = Duration(milliseconds: 500);
    const frames = 20;
    final interval = duration.inMilliseconds ~/ frames;

    for (int i = 0; i <= frames; i++) {
      Future<void>.delayed(Duration(milliseconds: i * interval), () {
        if (!mounted) return;
        setState(() {
          final double progress = i / frames;
          _displayedNumber = (progress * widget.streakCount).round();
        });
      });
    }
  }

  @override
  void dispose() {
    _flameController.dispose();
    _numberController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated flame with glow
        AnimatedBuilder(
          animation: _flameController,
          builder: (context, child) {
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(
                      alpha: 0.3 * _flameGlowAnimation.value,
                    ),
                    blurRadius: 30 * _flameGlowAnimation.value,
                    spreadRadius: 10 * _flameGlowAnimation.value,
                  ),
                ],
              ),
              child: Transform.scale(
                scale: _flameScaleAnimation.value,
                child: Icon(
                  PhosphorIcons.fire(PhosphorIconsStyle.fill),
                  color: Colors.orange,
                  size: 80,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Streak number with fade-in
        FadeTransition(
          opacity: _numberOpacityAnimation,
          child: Text(
            '$_displayedNumber',
            style: textTheme.displayLarge?.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ),

        // Streak message with fade-in
        FadeTransition(
          opacity: _messageOpacityAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              widget.streakMessage ??
                  _getDefaultStreakMessage(widget.streakCount),
              style: textTheme.titleMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  String _getDefaultStreakMessage(int streak) {
    if (streak == 1) return 'Premier jour !';
    if (streak == 7) return 'Une semaine !';
    if (streak == 30) return 'Un mois !';
    if (streak >= 100) return 'Incroyable !';
    return '$streak jours d\'affilée !';
  }
}
