import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Vert des cachets de tournée. Repris **en dur** de `ClosingCardV18`
/// (« FIN DE TOURNÉE ») et `FeedbackClosingCard` (« TON AVIS COMPTE ») pour que
/// les trois cachets du produit soient rigoureusement identiques — c'est
/// `sectionBonnes`, pas `colors.success`.
const Color kStampGreen = Color(0xFF2E7D32);

/// Cachet « LU JUSQU'AU BOUT ».
///
/// Troisième occurrence de l'idiome postal du produit : `Transform.rotate(-2°)`
/// + bordure 1.5 px + Courier Prime 10 / w700 / letterSpacing 2.0, fond
/// transparent. Volontairement **pas** une `checkCircle` : celle-ci est déjà le
/// vocabulaire du « Lu » déclenché au bout d'1 seconde, la réutiliser
/// importerait sa dévaluation.
///
/// [animate] joue l'apparition (opacité + translation verticale). À laisser à
/// `false` quand l'article est rouvert alors qu'il est déjà terminé : c'est un
/// *état*, pas un événement.
class CompletionStamp extends StatefulWidget {
  const CompletionStamp({
    super.key,
    this.animate = false,
    this.label = 'LU JUSQU\'AU BOUT',
  });

  final bool animate;
  final String label;

  @override
  State<CompletionStamp> createState() => _CompletionStampState();
}

class _CompletionStampState extends State<CompletionStamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant CompletionStamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion : le cachet s'affiche plein, sans translation. L'haptique
    // (déclenchée par l'appelant) reste, elle : c'est le canal accessible.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _stamp(context);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
        );
      },
      child: _stamp(context),
    );
  }

  Widget _stamp(BuildContext context) {
    return Semantics(
      label: 'Lu jusqu\'au bout',
      child: Transform.rotate(
        angle: -2 * math.pi / 180,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: kStampGreen, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.checks(PhosphorIconsStyle.bold),
                size: 11,
                color: kStampGreen,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.courierPrime(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kStampGreen,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
