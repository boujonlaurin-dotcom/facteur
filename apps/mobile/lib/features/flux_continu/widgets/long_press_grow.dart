import 'package:flutter/material.dart';

/// « Nudge grow » au long-press, remplaçant l'ancien aperçu flottant plein
/// écran (`ArticlePreviewOverlay`) sur les cartes Essentiel / Flux : la carte
/// grossit brièvement puis revient (1.0 → 1.06 → 1.0), sans overlay.
///
/// **Pas d'haptique** (choix de cohérence : le seul buzz de l'écran Essentiel
/// reste le snap de section). Transposé du pulse `_WeatherBadge`
/// (`essentiel_hi_fi_card.dart`) — même grain de courbe, départ à 1.0.
class LongPressGrowNudge extends StatefulWidget {
  const LongPressGrowNudge({
    super.key,
    required this.child,
    this.onLongPress,
  });

  final Widget child;

  /// Hook analytics-only (ex. `onLongPressConversion`). Aucune action visuelle :
  /// le grow est piloté en interne.
  final VoidCallback? onLongPress;

  @override
  State<LongPressGrowNudge> createState() => _LongPressGrowNudgeState();
}

class _LongPressGrowNudgeState extends State<LongPressGrowNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    widget.onLongPress?.call();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _play(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
