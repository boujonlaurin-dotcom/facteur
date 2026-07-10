import 'package:flutter/material.dart';

import '../models/tour_step.dart';
import 'guided_tour_coach_card.dart';

/// Voile + découpe spotlight + coach card du tour guidé, rendu dans l'overlay
/// **racine** (au-dessus de la feuille « Mes favoris » qui vit en branche).
///
/// La découpe suit l'élément cerné frame par frame (relecture live du
/// `RenderBox` des [targets] via un ticker), pour rester collée pendant les
/// slides d'onglet et les scrolls. Quand aucune cible n'est encore mesurée /
/// visible (ou [TourStep.flaner] / [TourStep.done]), le voile est plein.
class GuidedTourOverlay extends StatefulWidget {
  final TourStep step;

  /// Cibles à cerner. Vide → voile plein (étape sans ancre / attente d'ancre).
  final List<GlobalKey> targets;

  /// Centre le coach card verticalement (étape Flâner) au lieu de l'ancrer en
  /// bas du téléphone.
  final bool centerCard;

  final VoidCallback onSkip;
  final VoidCallback onNext;

  const GuidedTourOverlay({
    super.key,
    required this.step,
    required this.targets,
    required this.onSkip,
    required this.onNext,
    this.centerCard = false,
  });

  @override
  State<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<GuidedTourOverlay>
    with SingleTickerProviderStateMixin {
  // Ticker uniquement pour repeindre la découpe à chaque frame (suivi de
  // l'élément pendant slide/scroll). Borné par la vie de l'overlay → pas de
  // boucle d'animation orpheline.
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final card = GuidedTourCoachCard(
      step: widget.step,
      onSkip: widget.onSkip,
      onNext: widget.onNext,
    );
    return Stack(
      children: [
        // Voile + découpe. GestureDetector opaque : absorbe les taps (l'app
        // dessous reste inerte) ; un tap hors carte est un no-op.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _SpotlightPainter(
                repaint: _ticker,
                targets: widget.targets,
              ),
            ),
          ),
        ),
        if (widget.centerCard)
          Positioned(
            left: 24,
            right: 24,
            top: 0,
            bottom: 0,
            child: Center(child: card),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 24,
            child: card,
          ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final List<GlobalKey> targets;

  _SpotlightPainter({required Listenable repaint, required this.targets})
      : super(repaint: repaint);

  static const Color _scrim = Color(0xFF2C2A29);
  static const Color _stroke = Color(0xFFE8943F);
  static const double _pad = 8;
  static const double _radius = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final holes = <RRect>[];
    for (final key in targets) {
      final rect = _rectFor(key, size);
      if (rect != null) {
        holes.add(
          RRect.fromRectAndRadius(
            rect.inflate(_pad),
            const Radius.circular(_radius),
          ),
        );
      }
    }

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = _scrim.withValues(alpha: 0.72));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final hole in holes) {
      canvas.drawRRect(hole, clear);
    }
    canvas.restore();

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _stroke;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = _stroke.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final hole in holes) {
      canvas.drawRRect(hole, glowPaint);
      canvas.drawRRect(hole, strokePaint);
    }
  }

  /// Rect global de la cible si elle est montée, mesurée et visible à l'écran.
  Rect? _rectFor(GlobalKey key, Size screen) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    // Hors viewport vertical → pas de trou (sinon voile uniforme sans repère).
    if (rect.bottom <= 0 || rect.top >= screen.height) return null;
    return rect;
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.targets != targets;
}
