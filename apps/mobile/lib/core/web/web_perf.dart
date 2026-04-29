import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Web-specific perf helpers. CanvasKit (forced since Flutter 3.29) is slow
/// on Safari iOS for blur, large shadows, and continuous repaints.
/// All helpers are no-ops on mobile so the app's visual identity stays intact
/// on Android/iOS native builds.

const bool kWebPerf = kIsWeb;

/// Replaces a `BackdropFilter` by an opaque fill on web.
/// On mobile, returns the blurred widget unchanged.
Widget webBlurFallback({
  required ImageFilter filter,
  required Color fallbackColor,
  required Widget child,
}) {
  if (kWebPerf) {
    return ColoredBox(color: fallbackColor, child: child);
  }
  return BackdropFilter(filter: filter, child: child);
}

/// Returns a list of `BoxShadow` with reduced `blurRadius` on web
/// (CanvasKit blur is ~quadratic; large blurs tank scroll fps on Safari).
List<BoxShadow> webShadows(List<BoxShadow> shadows) {
  if (!kWebPerf) return shadows;
  return shadows
      .map((s) => BoxShadow(
            color: s.color,
            offset: s.offset,
            blurRadius: s.blurRadius / 3,
            spreadRadius: s.spreadRadius,
            blurStyle: s.blurStyle,
          ))
      .toList(growable: false);
}

/// Wraps `child` in a `RepaintBoundary` on web only.
/// Use on items inside scrollable lists to avoid full-sliver repaints.
Widget webRepaintBoundary({required Widget child}) {
  if (!kWebPerf) return child;
  return RepaintBoundary(child: child);
}
