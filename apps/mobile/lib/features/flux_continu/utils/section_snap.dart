import 'package:flutter/physics.dart' show SpringDescription;

/// Section-snap tuning. All four knobs live here so the feeling can be
/// iterated in one place after a device pass (cf. plan « snap d'ancrage »).
/// `resolveSnapTarget` consumes the first three; the screen physics consumes
/// [kSnapSpring] (motion) and [kSnapEpsilon] (already-aligned guard).
///
/// ≤ this fraction of the usable viewport between the natural landing and an
/// anchor ⇒ snap; beyond it the landing sits deep inside a tall section
/// (e.g. the hi-fi Essentiel card) and we leave the reader free.
const double kSnapCaptureFraction = 0.5;

/// px/s. Above this the fling is a deliberate flick: we commit firmly across
/// the next boundary in the gesture direction instead of letting friction
/// drop the reader mid-card (no rubber-band back).
const double kBoundaryCrossVelocity = 320.0;

/// px. A target this close to the current position is already aligned ⇒ no
/// snap (avoids a 0-length spring that would still fire a settle haptic).
const double kSnapEpsilon = 1.0;

/// Settle spring for the snap. Visible « pose » (~250-350ms) without wobble —
/// the snap is part of the fling's deceleration, not a second animation.
/// Pass to [ScrollSpringSimulation]. Soften (lower stiffness) if it feels abrupt.
const SpringDescription kSnapSpring = SpringDescription(
  mass: 0.5,
  stiffness: 140,
  damping: 18,
);

/// Chooses a section-anchored resting position for a fling, or `null` to leave
/// the scroll free (deep inside a tall section, already aligned, or no anchors).
///
/// Pure arithmetic — no Flutter binding — so it is unit-testable without the
/// Hive/Supabase bootstrap that the widget suite needs.
///
/// - [currentPixels]   : scroll offset at finger lift.
/// - [naturalLanding]  : where the platform ballistic *would* settle (carries
///   the fling energy → the rule is intrinsically un-gated by speed).
/// - [velocity]        : fling velocity (px/s, signed).
/// - [anchors]         : section-start offsets (absolute scroll pixels), sorted
///   ascending.
/// - [usableViewport]  : viewport height minus the sticky bar.
///
/// The caller clamps the result to `[min, max]ScrollExtent`.
double? resolveSnapTarget({
  required double currentPixels,
  required double naturalLanding,
  required double velocity,
  required List<double> anchors,
  required double usableViewport,
}) {
  if (anchors.isEmpty) return null;
  final viewport = usableViewport <= 0 ? 1.0 : usableViewport;

  // 1. Nearest anchor to the natural landing.
  final nearest = _nearestAnchor(anchors, naturalLanding);

  // 3. Firmness on boundary crossing — a deliberate flick commits across the
  //    next boundary in the gesture direction (within reach), never snapping
  //    back behind it.
  if (velocity.abs() > kBoundaryCrossVelocity) {
    final dir = velocity.sign;
    final boundary = _firstAnchorBeyond(anchors, currentPixels, dir);
    if (boundary != null &&
        (boundary - currentPixels).abs() <= 1.25 * viewport) {
      // Stay aligned to the natural landing when the fling reaches further
      // (hard multi-section fling), but never fall behind the crossed boundary.
      var target = nearest;
      if (dir > 0 && target < boundary) target = boundary;
      if (dir < 0 && target > boundary) target = boundary;
      return _epsilon(target, currentPixels);
    }
  }

  // 2. High-section guard — the landing is deep inside a section taller than
  //    the capture window ⇒ leave the reader free.
  if ((nearest - naturalLanding).abs() > kSnapCaptureFraction * viewport) {
    return null;
  }

  // 4. Otherwise snap to the nearest anchor.
  return _epsilon(nearest, currentPixels);
}

/// `null` when [target] is already aligned with [currentPixels] (± epsilon).
double? _epsilon(double target, double currentPixels) {
  if ((target - currentPixels).abs() <= kSnapEpsilon) return null;
  return target;
}

/// Nearest value in the ascending [sorted] list to [value] (binary search).
double _nearestAnchor(List<double> sorted, double value) {
  if (value <= sorted.first) return sorted.first;
  if (value >= sorted.last) return sorted.last;
  var lo = 0;
  var hi = sorted.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  // lo = first index whose value >= [value]; hi = lo - 1.
  final above = sorted[lo];
  final below = sorted[hi];
  return (value - below) <= (above - value) ? below : above;
}

/// First anchor strictly beyond [from] in direction [dir] (+1 fwd / -1 back),
/// or `null` if none.
double? _firstAnchorBeyond(List<double> sorted, double from, double dir) {
  if (dir > 0) {
    for (final a in sorted) {
      if (a > from + kSnapEpsilon) return a;
    }
  } else {
    for (var i = sorted.length - 1; i >= 0; i--) {
      if (sorted[i] < from - kSnapEpsilon) return sorted[i];
    }
  }
  return null;
}
