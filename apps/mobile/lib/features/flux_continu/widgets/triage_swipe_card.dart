import 'dart:async';
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

  /// `contentId` de l'article **actuellement** au sommet de la pile. La pile
  /// réutilise un unique `TriageSwipeCardState` (via `GlobalKey`) pour tous les
  /// articles ; ce jeton dit à [didUpdateWidget] quand la carte a changé
  /// d'article, pour repartir d'un état de geste propre (`_dragExtent=0`, anims
  /// réinitialisées) au lieu de laisser fuir le drag/anim d'une carte sur la
  /// suivante — la classe de bug « carte grisée figée » de l'itération PO 33.1.
  final String articleId;

  /// Swipe droite — « Je garde ». **Garde** l'article ; ce n'est pas une lecture
  /// (la lecture vient après, depuis la liste des gardés).
  final VoidCallback onKeep;

  /// Swipe gauche — « Pas pour moi ». Écrit une décision de tri, rien d'autre :
  /// aucune source n'est mutée, aucun poids ne bouge.
  final VoidCallback onPass;

  /// Hauteur de la carte du dessus. Deux valeurs discrètes selon que l'article
  /// porte une image (`triageCardHeightFor`), jamais un fit-to-content : la
  /// barre d'actions glisse d'un article à l'autre, elle ne saute pas.
  final double height;

  /// Avancée du geste, normalisée `0..1` (0 = au repos, 1 = la carte a parcouru
  /// une demi-largeur d'écran ou est sortie). Émise à chaque frame de geste pour
  /// que la pile **promeuve la carte du dessous en continu** au lieu de la
  /// faire claquer de 0.96 à 1.0 quand elle devient carte du dessus.
  final ValueChanged<double>? onGestureProgress;

  const TriageSwipeCard({
    super.key,
    required this.child,
    required this.articleId,
    required this.onKeep,
    required this.onPass,
    required this.height,
    this.onGestureProgress,
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

  /// Décision à remonter à la fin de la sortie, consommée **une seule fois** par
  /// [_completeExit]. Non-null ⇒ une sortie est en cours d'aboutissement.
  VoidCallback? _pendingExitDone;

  /// Garde-fou de l'avancée : si l'anim de sortie n'aboutit jamais (ticker mis
  /// en sourdine par `TickerMode`, rebuild, perte d'arène de gestes), ce Timer
  /// force quand même [_completeExit]. Sans lui, l'index pouvait rester piégé,
  /// carte translatée hors écran + fondue (« carte grisée figée »).
  Timer? _exitGuard;

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
  void didUpdateWidget(TriageSwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Carte fraîche par article : le `GlobalKey` conserve ce State d'un article
    // au suivant, donc tout état transitoire du geste précédent doit être remis
    // à zéro, sinon il fuit sur la nouvelle carte (drag resté sale, anim en
    // cours). Belt-and-suspenders : sur le chemin normal, [_completeExit] a déjà
    // tout nettoyé avant que l'index n'avance ; ici on garantit l'état propre
    // même si une anim a été coupée entre-temps.
    if (oldWidget.articleId != widget.articleId) {
      _exitGuard?.cancel();
      _exitGuard = null;
      _pendingExitDone = null;
      _dragUnderway = false;
      _hasTriggered = false;
      _dragExtent = 0;
      _resetController.reset();
      _exitController.reset();
    }
  }

  @override
  void dispose() {
    _exitGuard?.cancel();
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

  /// Perte d'arène de gestes (long-press qui gagne, scroll parent, annulation
  /// système) après un `onStart` : sans ce handler, `_dragUnderway`/`_dragExtent`
  /// resteraient sales et la carte figée décalée. On ramène doucement à zéro.
  void _handleDragCancel() {
    if (!_dragUnderway || _hasTriggered) return;
    _dragUnderway = false;
    if (_dragExtent == 0) return;
    _resetStartExtent = _dragExtent;
    _resetController.forward(from: 0);
  }

  /// Sortie physique : la carte finit sa course hors écran, puis la décision est
  /// remontée. Notifier **après** l'animation évite que la carte suivante
  /// apparaisse déjà décalée (elle démarre à `dx=0`, garanti par le reset).
  void _triggerExit(double direction, VoidCallback onDone) {
    _hasTriggered = true;
    _exitDirection = direction;
    _pendingExitDone = onDone;
    HapticFeedback.mediumImpact();
    // Chemin normal : l'anim de sortie aboutit et remonte la décision.
    _exitController.forward(from: 0).then((_) => _completeExit());
    // Garde-fou : si l'anim est coupée (ticker en sourdine, rebuild), le Timer
    // force l'avancée. Les deux chemins passent par [_completeExit] (idempotent).
    _exitGuard?.cancel();
    _exitGuard = Timer(
      FacteurDurations.medium + const Duration(milliseconds: 80),
      _completeExit,
    );
  }

  /// Fin de sortie : remonte la décision **exactement une fois**, que l'anim ait
  /// abouti ou été coupée. Le notifier est externe à ce State — l'appeler hors
  /// montage reste sûr, et c'est le point : aucune décision perdue, aucun index
  /// figé par une anim interrompue.
  void _completeExit() {
    final onDone = _pendingExitDone;
    if (onDone == null) return; // déjà consommée
    _pendingExitDone = null;
    _exitGuard?.cancel();
    _exitGuard = null;
    // Le reset du contrôleur est gaté sur le montage **et doit le rester** :
    // `State.mounted` ne retombe qu'à `unmount`, donc `!mounted` ⇒ `dispose` est
    // déjà passé et `_exitController` n'a plus de ticker (toute lecture/écriture
    // y lèverait). Il n'y a alors plus rien à assainir : ce State ne se
    // remontera pas, la prochaine carte en aura un neuf. Le nettoyage du geste
    // reste symétrique dans les deux branches, lui.
    if (mounted) {
      _exitController.reset();
      setState(() {
        _dragExtent = 0;
        _hasTriggered = false;
      });
    } else {
      _hasTriggered = false;
      _dragExtent = 0;
    }
    onDone();
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

    // Un tampon ne doit jamais apparaître sur une carte que personne n'a
    // touchée : sans ce gate, un `effectiveDx` résiduel d'une frame (anim de
    // sortie coupée, drag en cours de reset) tamponnait la carte **suivante**,
    // qui se lisait alors comme « déjà décidée ».
    final gestureActive = _dragUnderway || _hasTriggered || exiting;
    final keepStamp = gestureActive
        ? (effectiveDx / _stampFullOpacityAt).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final passStamp = gestureActive
        ? (-effectiveDx / _stampFullOpacityAt).clamp(0.0, 1.0).toDouble()
        : 0.0;

    // Avancée normalisée du geste, remontée à la pile pour qu'elle promeuve la
    // carte du dessous **pendant** la course plutôt qu'à son terme. Émise après
    // la frame : notifier un `ValueNotifier` pendant le build ferait rebuilder
    // un ancêtre en cours de layout.
    final onProgress = widget.onGestureProgress;
    if (onProgress != null) {
      final progress =
          (effectiveDx.abs() / (screenWidth * 0.5)).clamp(0.0, 1.0).toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onProgress(progress);
      });
    }

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
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
                        // `textPrimary` (gris très foncé) et non
                        // `textSecondary` : en aplat, le second ne porte pas du
                        // texte blanc.
                        color: colors.textPrimary,
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
///
/// **Fond plein + texte blanc** (décision PO) : le tampon se pose le plus
/// souvent sur une photo, où un contour de 2px et du texte teinté se perdaient
/// dans l'image.
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
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
