import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';

/// Overlay de confettis de victoire (« Le mot du jour »).
///
/// À empiler **au-dessus** de l'écran Résultat quand le joueur vient de gagner
/// ([active] = `justFinished && isSolved`). Tire un burst unique depuis le haut,
/// vers le bas. Respecte le reduce-motion (`MediaQuery.disableAnimations`) :
/// dans ce cas, aucun confetti n'est joué.
class GrilleVictory extends StatefulWidget {
  const GrilleVictory({super.key, required this.active});

  /// Déclenche le burst une fois quand il passe à vrai.
  final bool active;

  @override
  State<GrilleVictory> createState() => _GrilleVictoryState();
}

class _GrilleVictoryState extends State<GrilleVictory> {
  late final ConfettiController _controller;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(duration: const Duration(seconds: 1));
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlay());
    }
  }

  @override
  void didUpdateWidget(GrilleVictory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _maybePlay();
    }
  }

  void _maybePlay() {
    if (!mounted || _played) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    _played = true;
    _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _controller,
          blastDirection: math.pi / 2, // vers le bas
          emissionFrequency: 0.0,
          numberOfParticles: 26,
          maxBlastForce: 22,
          minBlastForce: 8,
          gravity: 0.25,
          shouldLoop: false,
          colors: [
            c.primary,
            c.success,
            GrilleConstants.presentTile,
            c.textStamp,
          ],
        ),
      ),
    );
  }
}
