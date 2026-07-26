import 'package:flutter/material.dart';

import '../../../shared/widgets/completion_stamp.dart' show kStampGreen;

/// Marque discrètement, **au retour de l'article**, la carte d'une lecture
/// menée jusqu'au bout : un filet vertical vert se dessine sur le bord gauche.
///
/// Volontairement pas une célébration. La version d'origine de ce widget —
/// restée du code mort, jamais montée — posait un scrim noir à 60 % sur la
/// carte, une pastille grise (à rebours de la convention verte du produit) et
/// une courbe `elasticOut` sur 1000 ms : un vocabulaire de jeu pour un
/// non-événement. Ici : `easeOutCubic`, 320 ms, aucun scrim, et **aucune
/// haptique** — elle a déjà eu lieu dans l'article. Un événement, une vibration.
///
/// Une carte seulement ouverte ne déclenche rien du tout : il ne s'est rien
/// passé, l'annoncer serait la définition du bruit.
class AnimatedFeedCard extends StatefulWidget {
  const AnimatedFeedCard({
    super.key,
    required this.child,
    required this.isCompleted,
    this.animate = true,
  });

  final Widget child;

  /// L'article a été lu jusqu'au bout (`completedAt != null`).
  final bool isCompleted;

  /// `false` quand l'état était déjà connu à la construction : le filet est
  /// alors peint d'emblée, sans animation. C'est un état, pas un événement.
  final bool animate;

  @override
  State<AnimatedFeedCard> createState() => _AnimatedFeedCardState();
}

class _AnimatedFeedCardState extends State<AnimatedFeedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isCompleted && !widget.animate) _controller.value = 1.0;
    if (widget.isCompleted && widget.animate) _startDelayed();
  }

  @override
  void didUpdateWidget(AnimatedFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted && !oldWidget.isCompleted) _startDelayed();
  }

  /// Léger retard : ne pas concurrencer l'animation de retour de route.
  void _startDelayed() {
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCompleted) return widget.child;

    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Semantics(
      label: 'Lu jusqu\'au bout',
      child: Stack(
        children: [
          widget.child,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = reduceMotion
                    ? 1.0
                    : Curves.easeOutCubic.transform(_controller.value);
                if (t == 0) return const SizedBox.shrink();
                return Transform.scale(
                  scaleY: t,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: const _CompletionRule(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filet vertical 3 px — idiome du filet de journal. Pas de teinte de fond :
/// sur le crème `#F2E8D5`, un vert à 4 % passe sous le seuil de perception et
/// à 8 % il vire kaki, ce qui détruit la sensation papier.
class _CompletionRule extends StatelessWidget {
  const _CompletionRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      decoration: const BoxDecoration(
        color: kStampGreen,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
      ),
    );
  }
}
