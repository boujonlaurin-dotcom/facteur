import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// A [Page] that uses the standard Cupertino slide-from-right transition
/// but with full-screen swipe-back gesture detection instead of the
/// default edge-only (20px) gesture area.
///
/// Drop-in replacement for [CupertinoPage] on pushed screens.
class FullSwipeCupertinoPage<T> extends Page<T> {
  final Widget child;

  const FullSwipeCupertinoPage({
    required this.child,
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

  FullSwipeCupertinoPage<T> get _page =>
      settings as FullSwipeCupertinoPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: popGestureInProgress,
      child: _FullScreenBackGestureDetector(
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
        controller.animateBack(0.0, duration: dropDuration, curve: animationCurve);
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

/// Full-screen gesture detector for back navigation.
///
/// Unlike Flutter's built-in detector (limited to 20px from the left edge),
/// this one covers the entire screen width, allowing users to swipe back
/// from anywhere.
class _FullScreenBackGestureDetector extends StatefulWidget {
  final Widget child;
  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController> onStartPopGesture;

  const _FullScreenBackGestureDetector({
    required this.child,
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
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        // Full-screen transparent overlay to capture pointer events
        Positioned.fill(
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
