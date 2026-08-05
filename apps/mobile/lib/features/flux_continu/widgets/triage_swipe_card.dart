import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';

/// Carte du dessus de la pile de tri : le geste (Story 33.1).
///
/// **Widget frère de `SwipeToOpenCard`**, dont il reprend délibérément les
/// mêmes constantes de déclenchement pour que les deux swipes de l'app aient le
/// même toucher :
///
/// - seuil : 0.25 × largeur d'écran (`_SwipeToOpenCardState._threshold`) ;
/// - fling : 700 px/s (`_flingVelocity`) ;
/// - retour haptique : `HapticFeedback.mediumImpact()` au déclenchement.
///
/// Pourquoi un frère plutôt qu'une réutilisation directe : `SwipeToOpenCard`
/// est un binaire ouvrir/masquer, à fonds de couleur fixes, câblé sur **toutes**
/// les cartes du flux. La pile veut une sortie physique (translation + rotation
/// + fondu) et deux tampons. Le généraliser toucherait un widget déjà partout ;
/// le duplicata est assumé, à charge de garder les deux constantes alignées.
class TriageSwipeCard extends StatefulWidget {
  final Widget child;

  /// Swipe droite — « Je garde ». **Garde** l'article ; ce n'est pas une lecture
  /// (la lecture vient après, depuis la liste des gardés).
  final VoidCallback onKeep;

  /// Swipe gauche — « Pas pour moi ». Écrit une décision de tri, rien d'autre :
  /// aucune source n'est mutée, aucun poids ne bouge.
  final VoidCallback onPass;

  /// Hauteur réservée, imposée par le budget de fit pour que la carte ne
  /// change pas de taille en cours de tri.
  final double height;

  const TriageSwipeCard({
    super.key,
    required this.child,
    required this.onKeep,
    required this.onPass,
    required this.height,
  });

  @override
  State<TriageSwipeCard> createState() => TriageSwipeCardState();
}

class TriageSwipeCardState extends State<TriageSwipeCard>
    with TickerProviderStateMixin {
  double _dragExtent = 0;
  bool _dragUnderway = false;
  bool _hasTriggered = false;

  late AnimationController _resetController;
  double _resetStartExtent = 0;

  late AnimationController _exitController;
  double _exitDirection = 1;

  /// Aligné sur `SwipeToOpenCard._threshold`.
  static const double _threshold = 0.25;

  /// Aligné sur `SwipeToOpenCard._flingVelocity`.
  static const double _flingVelocity = 700.0;

  /// Distance (px) au bout de laquelle un tampon est pleinement opaque.
  static const double _stampFullOpacityAt = 70;

  /// Diviseur de rotation : `dx / 26` degrés, soit ~3° à 80px.
  static const double _rotationDivisor = 26;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: FacteurDurations.fast,
    )..addListener(_onResetTick);
    _exitController = AnimationController(
      vsync: this,
      duration: FacteurDurations.medium,
    )..addListener(_onExitTick);
  }

  @override
  void dispose() {
    _resetController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _onResetTick() {
    setState(() {
      _dragExtent = _resetStartExtent * (1 - _resetController.value);
    });
  }

  void _onExitTick() {
    setState(() {});
  }

  void _handleDragStart(DragStartDetails details) {
    if (_exitController.isAnimating) return;
    _dragUnderway = true;
    _hasTriggered = false;
    _resetController.stop();
    setState(() {});
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragUnderway || _exitController.isAnimating) return;
    setState(() => _dragExtent += details.primaryDelta ?? 0);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragUnderway || _exitController.isAnimating) return;
    _dragUnderway = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0;
    final ratio = _dragExtent / screenWidth;

    if (!_hasTriggered &&
        _dragExtent > 0 &&
        (ratio > _threshold || velocity > _flingVelocity)) {
      _triggerExit(1, widget.onKeep);
      return;
    }
    if (!_hasTriggered &&
        _dragExtent < 0 &&
        (ratio < -_threshold || velocity < -_flingVelocity)) {
      _triggerExit(-1, widget.onPass);
      return;
    }

    if (_dragExtent == 0) return;
    _resetStartExtent = _dragExtent;
    _resetController.forward(from: 0);
  }

  /// Sortie physique : la carte finit sa course hors écran, puis la décision est
  /// remontée. Notifier **après** l'animation évite que la carte suivante
  /// apparaisse déjà décalée.
  void _triggerExit(double direction, VoidCallback onDone) {
    _hasTriggered = true;
    _exitDirection = direction;
    HapticFeedback.mediumImpact();
    _exitController.forward(from: 0).then((_) {
      if (!mounted) return;
      _exitController.reset();
      setState(() {
        _dragExtent = 0;
        _hasTriggered = false;
      });
      onDone();
    });
  }

  /// Rejoue la sortie physique du geste depuis la barre d'actions, pour que le
  /// mode boutons rende le même mouvement que le swipe.
  ///
  /// [onDone] est fourni par l'appelant plutôt que réutilisé depuis
  /// [TriageSwipeCard.onKeep] / [onPass] : ces deux-là étiquettent la décision
  /// comme un *swipe*, et confondre les deux modalités viderait de son sens la
  /// lecture « le geste biaise-t-il la décision ? » de la jauge.
  void animateOut({required bool toRight, required VoidCallback onDone}) {
    if (_exitController.isAnimating || _hasTriggered) return;
    _triggerExit(toRight ? 1 : -1, onDone);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final colors = context.facteurColors;

    final exiting = _exitController.isAnimating || _exitController.value > 0;
    final effectiveDx = exiting
        ? _dragExtent +
            _exitDirection * screenWidth * 1.2 * _exitController.value
        : _dragExtent;
    final opacity = exiting ? (1 - _exitController.value).clamp(0.0, 1.0) : 1.0;

    final keepStamp =
        (effectiveDx / _stampFullOpacityAt).clamp(0.0, 1.0).toDouble();
    final passStamp =
        (-effectiveDx / _stampFullOpacityAt).clamp(0.0, 1.0).toDouble();

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: SizedBox(
        height: widget.height,
        child: Transform.translate(
          offset: Offset(effectiveDx, 0),
          child: Transform.rotate(
            angle: (effectiveDx / _rotationDivisor) * math.pi / 180,
            child: Opacity(
              opacity: opacity,
              child: Stack(
                children: [
                  // Frontière de repeinture : le drag appelle `setState` à
                  // chaque frame et la carte est devenue lourde (image décodée,
                  // glyphe de divergence, pile d'avatars). Sans elle, chaque
                  // frame de geste re-enregistre la display list de tout ce qui
                  // est visible jusqu'au viewport du feed.
                  Positioned.fill(child: RepaintBoundary(child: widget.child)),
                  if (keepStamp > 0)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _Stamp(
                        label: 'Je garde',
                        color: colors.primary,
                        opacity: keepStamp,
                        angle: -0.2,
                      ),
                    ),
                  if (passStamp > 0)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _Stamp(
                        label: 'Pas pour moi',
                        color: colors.textSecondary,
                        opacity: passStamp,
                        angle: 0.2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tampon posé sur la carte pendant le geste — dit ce qui va se passer avant
/// que le doigt ne se lève.
class _Stamp extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  final double angle;

  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.angle,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
