import 'package:flutter/material.dart';

/// Pulse « grow » **automatique** (aucun geste) : la carte grossit brièvement
/// puis revient (1.0 → 1.06 → 1.0). Wrapper purement déclaratif, piloté de
/// l'extérieur — le vrai long-press (aperçu flottant) est géré séparément par
/// la carte, ce widget ne porte donc **aucun** [GestureDetector].
///
/// L'animation se joue quand [playToken] **change** vers une valeur non-nulle
/// (cf. [didUpdateWidget]). Chaque tuile dérive son `playToken` du signal
/// `autoGrowNudgeSignalProvider` : un nouveau `nonce` pour un `contentId` donné
/// rejoue le pulse sur cette seule carte.
///
/// **Pas d'haptique** (choix de cohérence : le seul buzz de l'écran Essentiel
/// reste le snap de section). Transposé du pulse `_WeatherBadge`
/// (`essentiel_hi_fi_card.dart`) — même grain de courbe, départ à 1.0.
class AutoGrowPulse extends StatefulWidget {
  const AutoGrowPulse({
    super.key,
    required this.child,
    this.playToken,
  });

  final Widget child;

  /// Jeton de déclenchement : quand il passe à une **nouvelle** valeur non-nulle,
  /// le pulse se rejoue une fois. `null` = repos (échelle neutre à 1.0).
  final Object? playToken;

  @override
  State<AutoGrowPulse> createState() => _AutoGrowPulseState();
}

class _AutoGrowPulseState extends State<AutoGrowPulse>
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
    // Un token déjà posé au 1er montage joue le pulse (rare, mais garde le
    // comportement cohérent si la carte se (re)monte pile sur un signal actif).
    if (widget.playToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(AutoGrowPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    final token = widget.playToken;
    if (token != null && token != oldWidget.playToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
