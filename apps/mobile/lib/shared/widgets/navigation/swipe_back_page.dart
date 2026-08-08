import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';

const double wideBackGestureWidthFraction = 0.35;

/// Bande de bord (≈ 6 % de largeur, soit ~24 px sur un écran de 390) réservée
/// au retour quand la page possède elle-même un geste horizontal — c'est le cas
/// du deck d'articles (Story 34.1), où glisser à gauche/droite change d'article.
/// Sans ce rétrécissement, la zone large de 35 % mangerait le swipe de la page.
const double edgeBackGestureWidthFraction = 0.06;

/// Gesture set for platform views nested inside [FullSwipeCupertinoPage].
///
/// Only vertical drags are claimed by the platform view.
///
/// This mirrors a Flutter [Scrollable]: vertical movement scrolls immediately,
/// while horizontal movement remains available to the enclosing route's
/// swipe-back recognizer. Taps and other unclaimed gestures still fall through
/// to the platform view.
Set<Factory<OneSequenceGestureRecognizer>>
    swipeBackCompatiblePlatformViewGestureRecognizers() {
  return {
    const Factory<VerticalDragGestureRecognizer>(
      VerticalDragGestureRecognizer.new,
    ),
  };
}

enum FullSwipePageTransition { horizontal, verticalFromBottom }

/// A [Page] that uses the standard Cupertino slide-from-right transition
/// but with a wider swipe-back gesture zone (left ~35% of screen) instead
/// of the default edge-only (20px) gesture area.
///
/// Drop-in replacement for [CupertinoPage] on pushed screens.
class FullSwipeCupertinoPage<T> extends Page<T> {
  final Widget child;
  final Duration? transitionDurationOverride;
  final FullSwipePageTransition transition;

  /// Largeur (en fraction de l'écran) de la zone où un glissement vers la
  /// droite déclenche le retour. Défaut : [wideBackGestureWidthFraction].
  /// Une page qui possède son propre geste horizontal passe
  /// [edgeBackGestureWidthFraction] pour ne garder que la bande de bord.
  final double backGestureWidthFraction;

  const FullSwipeCupertinoPage({
    required this.child,
    this.transitionDurationOverride,
    this.transition = FullSwipePageTransition.horizontal,
    this.backGestureWidthFraction = wideBackGestureWidthFraction,
    super.key,
    super.name,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _FullSwipePageRoute<T>(page: this);
  }
}

/// Route that uses [CupertinoRouteTransitionMixin] for the visual transition
/// but overrides [buildTransitions] to use a full-screen gesture detector.
class _FullSwipePageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  _FullSwipePageRoute({required FullSwipeCupertinoPage<T> page})
      : super(settings: page);

  FullSwipeCupertinoPage<T> get _page => settings as FullSwipeCupertinoPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      _page.transitionDurationOverride ?? super.transitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_page.transition == FullSwipePageTransition.verticalFromBottom) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      );
    }

    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: popGestureInProgress,
      child: _FullScreenBackGestureDetector(
        widthFraction: _page.backGestureWidthFraction,
        enabledCallback: () => popGestureEnabled,
        onStartPopGesture: () => _BackGestureController(
          navigator: navigator!,
          controller: controller!,
          getIsCurrent: () => isCurrent,
          getIsActive: () => isActive,
        ),
        child: child,
      ),
    );
  }
}

/// Controls the route's animation controller during a back gesture.
///
/// Mirrors Flutter's internal [_CupertinoBackGestureController].
class _BackGestureController {
  _BackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsCurrent,
    required this.getIsActive,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsCurrent;
  final ValueGetter<bool> getIsActive;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const double kMinFlingVelocity = 1.0; // screen widths per second
    const Curve animationCurve = Curves.fastEaseInToSlowEaseOut;
    const Duration dropDuration = Duration(milliseconds: 350);

    final bool isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      // Route already navigated away — follow active state
      animateForward = getIsActive();
    } else if (velocity.abs() >= kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      controller.animateTo(1.0, duration: dropDuration, curve: animationCurve);
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      if (controller.isAnimating) {
        controller.animateBack(0.0,
            duration: dropDuration, curve: animationCurve);
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

/// Wide-area gesture detector for back navigation.
///
/// Unlike Flutter's built-in detector (limited to 20px from the left edge),
/// this one covers the left third of the screen by default, giving a much
/// larger swipe-back target without interfering with vertical scrolling in
/// content. La largeur est réglable ([widthFraction]) pour les pages qui
/// portent elles-mêmes un geste horizontal.
class _FullScreenBackGestureDetector extends StatefulWidget {
  final Widget child;
  final double widthFraction;
  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController> onStartPopGesture;

  const _FullScreenBackGestureDetector({
    required this.child,
    required this.widthFraction,
    required this.enabledCallback,
    required this.onStartPopGesture,
  });

  @override
  State<_FullScreenBackGestureDetector> createState() =>
      _FullScreenBackGestureDetectorState();
}

class _FullScreenBackGestureDetectorState
    extends State<_FullScreenBackGestureDetector> {
  _BackGestureController? _backGestureController;
  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    // La zone est déjà bornée par la bande posée en overlay : il ne reste que
    // la question de savoir si le geste de retour est armé sur cette route.
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _backGestureController?.dragUpdate(
      _convertToLogical(details.primaryDelta! / context.size!.width),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    _backGestureController?.dragEnd(
      _convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width,
      ),
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  double _convertToLogical(double value) {
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        return -value;
      case TextDirection.ltr:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    // La bande de retour est posée **au-dessus** de la page (et non en ancêtre
    // translucide, comme dans une version antérieure). C'est ce qui rend la
    // priorité de geste déterministe : posée au-dessus, elle est hit-testée en
    // premier, donc son recognizer entre dans l'arène avant ceux de la page.
    // En ancêtre, il y entrait en dernier et perdait tout arbitrage contre un
    // recognizer horizontal interne — exactement le cas du deck d'articles.
    // `translucent` laisse passer taps et scrolls verticaux vers la page,
    // comme avant. Même montage que `_CupertinoBackGestureDetector` de Flutter.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.sizeOf(context).width * widget.widthFraction,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
