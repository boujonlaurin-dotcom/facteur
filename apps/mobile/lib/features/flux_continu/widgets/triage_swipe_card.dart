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

  /// Avancée du geste, normalisée `0..1` (0 = au repos, 1 = la carte a parcouru
  /// une demi-largeur d'écran ou est sortie). Émise à chaque frame de geste pour
  /// que la pile **promeuve la carte du dessous en continu** au lieu de la
  /// faire claquer de 0.96 à 1.0 quand elle devient carte du dessus.
  final ValueChanged<double>? onGestureProgress;

  /// Tap sur la carte — ouvre l'article, **sans aucune décision** (Story 33.2).
  /// Branché sur le `GestureDetector` qui porte déjà les handlers de drag :
  /// l'arène départage tap / drag / long-press sans widget supplémentaire.
  final VoidCallback? onTap;

  const TriageSwipeCard({
    super.key,
    required this.child,
    required this.articleId,
    required this.onKeep,
    required this.onPass,
    this.onGestureProgress,
    this.onTap,
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

  /// Largeur d'écran relevée au dernier [build]. Sert de dénominateur à
  /// [_effectiveDx] / [_emitProgress], appelés depuis des callbacks où lire
  /// `MediaQuery` serait hors phase.
  double _screenWidth = 0;

  /// Pointeurs physiquement posés sur la carte, vus par le [Listener] qui
  /// enveloppe le `GestureDetector`. C'est le filet du bug « geste sans fin
  /// détectée » : le `HorizontalDragGestureRecognizer` peut ne jamais délivrer
  /// de `onEnd`/`onCancel` terminal (2ᵉ doigt qui atterrit en cours de swipe et
  /// fait « tenir » le recognizer, perte de route d'arène) — `_dragUnderway`
  /// restait alors `true` et la carte figée translatée, définitivement (aucune
  /// décision ⇒ l'index n'avance pas ⇒ `didUpdateWidget` ne reset jamais).
  /// Les événements bruts de pointeur, eux, arrivent toujours.
  final Set<int> _activePointers = {};

  /// Un microtask de réconciliation [_resolveLostDragEnd] est-il déjà planifié ?
  bool _resolveScheduled = false;

  /// Nombre de gestes résolus par le filet (fin jamais délivrée par le
  /// recognizer). Doit rester à 0 sur tous les drags propres — c'est l'assertion
  /// des tests de non-régression du filet.
  @visibleForTesting
  int lostGestureResolutions = 0;

  /// Aligné sur `SwipeToOpenCard._threshold`.
  static const double _threshold = 0.25;

  /// Aligné sur `SwipeToOpenCard._flingVelocity`.
  static const double _flingVelocity = 700.0;

  /// Distance (px) au bout de laquelle un tampon est pleinement opaque.
  static const double _stampFullOpacityAt = 70;

  /// Diviseur de rotation : `dx / 50` degrés, soit ~1,6° à 80px. Était 26
  /// (~3° à 80px) : à cette amplitude, la rotation **à origine centrée**
  /// faisait balayer ~11px horizontalement aux coins de la carte en plus de la
  /// translation — un « coin » de révélation en biais, asymétrique, que l'œil
  /// lisait comme un décalage de la carte du dessous (bug « drift »). Réduite
  /// et bornée ([_maxRotationDegrees]), avec pivot ancré en haut (cf. [build]).
  static const double _rotationDivisor = 50;

  /// Borne (degrés) de l'inclinaison de sortie : au-delà, l'angle n'apporte
  /// plus rien au signal « la carte part » mais amplifie le balayage des coins.
  static const double _maxRotationDegrees = 2.5;

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
      // **Doit précéder `_resetController.reset()`** (bug « drift » du 15/08) :
      // `AnimationController.reset()` passe par le setter `value`, qui
      // `notifyListeners()`. Le `reset()` deux lignes plus bas rappelait donc
      // [_onResetTick], lequel recalcule `_dragExtent = _resetStartExtent *
      // (1 - 0)` — soit exactement le décalage du dernier retour élastique,
      // **restauré** sur la carte fraîche, juste après l'avoir mis à zéro. La
      // carte suivante s'affichait translatée, au repos et sans geste : le
      // décalage rapporté après « Je garde »/« Pas pour moi ». `_dragExtent` ne
      // suffit pas, c'est sa *source* qu'il faut éteindre.
      _resetStartExtent = 0;
      // Le filet aussi repart à zéro : un pointeur encore posé (ou un microtask
      // en vol) appartient à la carte précédente et fuirait sinon sur celle-ci.
      _activePointers.clear();
      _resolveScheduled = false;
      _resetController.reset();
      _exitController.reset();
      // La carte fraîche est au repos : la pile doit repartir d'une promotion
      // nulle, sinon la nouvelle carte du dessous hérite de l'avancée de la
      // précédente.
      _emitProgress();
    }
  }

  @override
  void dispose() {
    _exitGuard?.cancel();
    // Un microtask [_resolveLostDragEnd] éventuellement en vol se no-op sur
    // `!mounted` ; on éteint quand même l'état du filet par symétrie avec
    // `didUpdateWidget`.
    _activePointers.clear();
    _resolveScheduled = false;
    _resetController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  /// Décalage horizontal rendu, geste et sortie confondus. Getter plutôt que
  /// calcul local à [build] : [_emitProgress] a besoin de la même valeur hors
  /// phase de build.
  double get _effectiveDx => _exiting
      ? _dragExtent +
          _exitDirection * _screenWidth * 1.2 * _exitController.value
      : _dragExtent;

  bool get _exiting => _exitController.isAnimating || _exitController.value > 0;

  /// Remonte l'avancée normalisée du geste (`0..1`, 1 = une demi-largeur d'écran
  /// parcourue) pour que la pile promeuve la carte du dessous **pendant** la
  /// course plutôt qu'à son terme.
  ///
  /// Appelé depuis les points qui *mutent* l'état du geste, jamais depuis
  /// [build] : émettre au build allouait une closure et un `addPostFrameCallback`
  /// à chaque frame (y compris sur une carte au repos), et faisait atterrir la
  /// promotion **après** le layout — soit une frame de retard permanent sur la
  /// carte qu'elle est censée suivre.
  void _emitProgress() {
    final onProgress = widget.onGestureProgress;
    if (onProgress == null || _screenWidth <= 0) return;
    onProgress((_effectiveDx.abs() / (_screenWidth * 0.5))
        .clamp(0.0, 1.0)
        .toDouble());
  }

  void _onResetTick() {
    setState(() {
      _dragExtent = _resetStartExtent * (1 - _resetController.value);
    });
    _emitProgress();
  }

  void _onExitTick() {
    setState(() {});
    _emitProgress();
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
    _emitProgress();
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragUnderway || _exitController.isAnimating) return;
    _resolveDragEnd(velocity: details.primaryVelocity ?? 0);
  }

  /// Corps décisionnel de la fin de geste, partagé entre le `onEnd` réel du
  /// recognizer ([_handleDragEnd]) et la réconciliation du filet
  /// ([_resolveLostDragEnd]). `_dragUnderway = false` **d'abord** : c'est ce qui
  /// rend les deux entrées mutuellement exclusives — la première qui passe
  /// désarme l'autre.
  void _resolveDragEnd({required double velocity}) {
    _dragUnderway = false;

    final ratio = _screenWidth > 0 ? _dragExtent / _screenWidth : 0.0;

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

    _springBack();
  }

  void _trackPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
  }

  /// `onPointerUp` **et** `onPointerCancel` du filet. Quand plus aucun doigt
  /// n'est posé alors que `_dragUnderway` est encore vrai, la fin de geste du
  /// recognizer est peut-être perdue — on planifie une réconciliation
  /// **différée** : le [Listener] s'exécute *avant* le `onEnd` du recognizer
  /// dans la chaîne de dispatch, donc trancher ici doublerait le chemin normal.
  void _trackPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isNotEmpty || !_dragUnderway || _resolveScheduled) {
      return;
    }
    _resolveScheduled = true;
    scheduleMicrotask(_resolveLostDragEnd);
  }

  /// Réconciliation du filet : ne tranche que si la fin de geste est **encore**
  /// perdue au moment où le microtask s'exécute. Vélocité nulle — seule la
  /// distance peut alors décider ; sous le seuil, la carte revient simplement
  /// à sa place.
  void _resolveLostDragEnd() {
    _resolveScheduled = false;
    if (!mounted) return;
    // Le chemin normal (onEnd/onCancel) a résolu entre-temps, un nouveau geste
    // a démarré, ou une sortie est déjà en cours : rien à réconcilier.
    if (!_dragUnderway || _activePointers.isNotEmpty) return;
    if (_hasTriggered || _exitController.isAnimating) return;
    lostGestureResolutions++;
    _resolveDragEnd(velocity: 0);
  }

  /// Perte d'arène de gestes (long-press qui gagne, scroll parent, annulation
  /// système) après un `onStart` : sans ce handler, `_dragUnderway`/`_dragExtent`
  /// resteraient sales et la carte figée décalée. On ramène doucement à zéro.
  void _handleDragCancel() {
    if (!_dragUnderway || _hasTriggered) return;
    _dragUnderway = false;
    _springBack();
  }

  /// Retour élastique à `dx = 0` — le geste n'a pas franchi le seuil, ou l'arène
  /// a été perdue. Les ticks de `_resetController` remontent l'avancée au fur et
  /// à mesure, donc la carte du dessous redescend en même temps que celle du
  /// dessus revient.
  void _springBack() {
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
    // Assainissement gaté sur le montage **et qui doit le rester** :
    // `State.mounted` ne retombe qu'à `unmount`, donc `!mounted` ⇒ `dispose` est
    // déjà passé et `_exitController` n'a plus de ticker (toute lecture y
    // lèverait). Il n'y a alors plus rien à assainir non plus : ce State ne se
    // remontera pas, la prochaine carte en aura un neuf.
    if (mounted) {
      _exitController.reset();
      setState(() {
        _dragExtent = 0;
        // Même raison qu'en [didUpdateWidget] : une sortie aboutie annule tout
        // retour élastique en attente. Laisser `_resetStartExtent` chargé ici
        // réarmerait le drift au prochain `_resetController.reset()`.
        _resetStartExtent = 0;
        _hasTriggered = false;
      });
      // Pas de `_emitProgress()` ici : il pousserait la promotion à 0 — donc la
      // carte entrante à son opacité de repos — **avant** que `onDone()` ne
      // l'avance en carte du dessus (flash d'une frame). C'est
      // `didUpdateWidget`, une fois l'index avancé, qui remet la promotion à
      // zéro pour la nouvelle carte du dessous.
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
    // Mémorisé pour que [_emitProgress] et [_effectiveDx] disposent de la
    // largeur hors phase de build (ticks d'anim, handlers de geste), sans
    // relire `MediaQuery` depuis un callback.
    _screenWidth = MediaQuery.of(context).size.width;
    final colors = context.facteurColors;

    final exiting = _exiting;
    final effectiveDx = _effectiveDx;
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

    // Filet de sécurité **passif** autour du `GestureDetector` (précédent
    // maison : `article_preview_modal.dart`). `deferToChild` : le `Listener`
    // ne rejoint pas l'arène de gestes — tap, long-press et drag restent
    // intacts, il ne fait qu'observer les événements bruts de pointeur pour
    // réconcilier une fin de geste que le recognizer aurait perdue.
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _trackPointerDown,
      onPointerUp: _trackPointerUp,
      onPointerCancel: _trackPointerUp,
      child: GestureDetector(
        onTap: widget.onTap,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onHorizontalDragCancel: _handleDragCancel,
        child: Transform.translate(
          offset: Offset(effectiveDx, 0),
          child: Transform.rotate(
            angle: (effectiveDx / _rotationDivisor)
                    .clamp(-_maxRotationDegrees, _maxRotationDegrees) *
                math.pi /
                180,
            // Pivot ancré en haut : les deux cartes de la pile partagent leur
            // bord haut (`top: 0`), donc un pivot au centre faisait balayer le
            // coin haut latéralement pendant la sortie — le « drift » perçu de
            // la carte du dessous. Ancré, ce déplacement devient sub-pixel.
            alignment: Alignment.topCenter,
            child: Opacity(
              opacity: opacity,
              child: Stack(
                children: [
                  // **La carte est le seul enfant non positionné** : c'est elle
                  // qui dimensionne le `Stack`, donc le slot de pile — la carte
                  // épouse son contenu (reprise PO 08/08) au lieu de remplir une
                  // hauteur imposée. `width: infinity` parce qu'un enfant non
                  // positionné reçoit des contraintes lâches et se réduirait
                  // sinon à la largeur de son texte.
                  //
                  // Frontière de repeinture : le drag appelle `setState` à
                  // chaque frame et la carte est devenue lourde (image décodée,
                  // glyphe de divergence, pile d'avatars). Sans elle, chaque
                  // frame de geste re-enregistre la display list de tout ce qui
                  // est visible jusqu'au viewport du feed.
                  SizedBox(
                    width: double.infinity,
                    child: RepaintBoundary(child: widget.child),
                  ),
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
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: 6,
          ),
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
