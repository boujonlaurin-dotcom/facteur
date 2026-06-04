import 'package:flutter/physics.dart' show SpringDescription;

/// px. A target this close to the current position is already aligned ⇒ no
/// snap (avoids a 0-length spring that would still fire a settle haptic). Also
/// the slack used when testing whether a landing sits *inside* a free zone or
/// *on* a framing offset.
const double kSnapEpsilon = 1.0;

/// px. **Deadband (« marge ») around each section extremity** — the main feel
/// knob, tune it à l'œil. When the reader overshoots an extremity (a section's
/// top or bottom frame) by *less* than this, the snap pulls them **back** to
/// re-frame that section instead of switching to the next one. They must scroll
/// more than this margin past the edge before the section actually switches.
/// Larger ⇒ harder to switch sections (more « collant » à la carte courante);
/// smaller ⇒ switches more readily. 0 reverts to the pure edge-triggered feel.
const double kSectionEdgeMargin = 120.0;

// ── Réglages du ressort de snap (le « grain » du switch vers une section) ──
// Le snap est un [ScrollSpringSimulation] : on tune ces 3 leviers à l'œil pour
// le rendre à la fois smooth ET net. Repères :

/// La **force / vitesse** du tir vers la cible. Plus haut ⇒ snap plus rapide et
/// « net » (claque vers la section) ; plus bas ⇒ plus lent et mou. C'est le
/// premier levier pour la « vitesse de switch ».
const double kSnapStiffness = 550.0;

/// L'**amortissement**. Plus haut ⇒ aucune oscillation, arrivée « posée » et
/// smooth (mais trop haut = traînant) ; plus bas ⇒ vif, voire un léger rebond.
/// À monter avec [kSnapStiffness] pour rester net sans wobble.
const double kSnapDamping = 40.0;

/// L'**inertie** de la masse animée. Plus haut ⇒ démarrage plus pesant / lent ;
/// plus bas ⇒ réaction plus immédiate. À laisser ≈ 0.5 sauf besoin précis.
const double kSnapMass = 0.05;

/// Ressort de pose du snap, assemblé depuis les 3 leviers ci-dessus. Visible
/// « pose » (~250-350ms) sans wobble — le snap fait partie de la décélération
/// du fling, pas d'une seconde animation.
const SpringDescription kSnapSpring = SpringDescription(
  mass: kSnapMass,
  stiffness: kSnapStiffness,
  damping: kSnapDamping,
);

/// The two framing offsets of a sticky section, as absolute scroll pixels:
/// - [top]    : section top flush under the sticky header.
/// - [bottom] : section bottom flush to the footer (its last cards posed at the
///   viewport bottom). Equals [top] for a section shorter than the usable
///   viewport (it can never fill the screen, so it has no free-reading zone);
///   `bottom > top` only for a section taller than the usable viewport.
typedef SectionFrame = ({double top, double bottom});

/// Chooses a section-framed resting position for a fling, or `null` to leave
/// the scroll free.
///
/// The feel: the reader is **free** while a section fully fills the viewport
/// (its top is above the sticky header *and* its bottom is below the footer —
/// no edge shows). Once an edge crosses into the viewport the scroll **snaps**:
/// - a *small* overshoot past an extremity (within [kSectionEdgeMargin]) is
///   pulled **back** to re-frame that section — a margin before the card
///   actually switches;
/// - a *larger* scroll commits to the next frame *in the travel direction*
///   (down ⇒ next section top, up ⇒ previous section bottom), so the reader is
///   never left floating between two sections without feedback.
/// A section shorter than the viewport has no free zone, so beyond the margin it
/// behaves like the simple "pose on the next section top" rule.
///
/// Pure arithmetic — no Flutter binding — so it is unit-testable without the
/// Hive/Supabase bootstrap that the widget suite needs.
///
/// - [currentPixels]   : scroll offset at finger lift.
/// - [naturalLanding]  : where the platform ballistic *would* settle (carries
///   the fling energy → the rule is intrinsically un-gated by speed).
/// - [velocity]        : fling velocity (px/s, signed). Only a fallback for the
///   travel direction.
/// - [scrollDirection] : the reader's *travel* direction, sign only — +1 down
///   (offset increasing), -1 up, 0 unknown. Sourced from the controller, not
///   from [velocity], because a slow drag-to-read ends with a ≈ 0 (or slightly
///   reversed) lift velocity that would misread as "going the other way". Falls
///   back to `velocity.sign` when 0, then to the nearest frame.
/// - [frames]          : the section framing offsets, sorted ascending by top.
///
/// The caller clamps the result to `[min, max]ScrollExtent`.
double? resolveSnapTarget({
  required double currentPixels,
  required double naturalLanding,
  required double velocity,
  required double scrollDirection,
  required List<SectionFrame> frames,
}) {
  if (frames.isEmpty) return null;

  // Free reading: the landing rests inside a section that fully fills the
  // viewport (a tall section's open interior). No edge shows ⇒ leave it free.
  for (final f in frames) {
    if (f.bottom > f.top + kSnapEpsilon &&
        naturalLanding > f.top + kSnapEpsilon &&
        naturalLanding < f.bottom - kSnapEpsilon) {
      return null;
    }
  }

  // Every framing offset is a snap point: each section top, plus the bottom of
  // each tall section (rest on its last cards). Sorted ascending.
  final points = <double>[];
  for (final f in frames) {
    points.add(f.top);
    if (f.bottom > f.top + kSnapEpsilon) points.add(f.bottom);
  }
  points.sort();

  // Bracketing extremities around the landing.
  final lo = _lastAtOrBefore(points, naturalLanding);
  final hi = _firstAtOrAfter(points, naturalLanding);
  if (lo == null) return _commit(hi!, currentPixels); // below the first frame
  if (hi == null) return _commit(lo, currentPixels); // above the last frame
  if (lo == hi) return _commit(lo, currentPixels); // landing ≈ on a frame

  // Edge margin (deadband): a small overshoot past an extremity is pulled BACK
  // to it — the « marge » before the section switches. Applied only when the
  // landing is close to exactly one extremity; if it is close to both (a narrow
  // gap between short sections) we fall through to the directional commit so
  // those still switch immediately.
  final nearLo = (naturalLanding - lo) <= kSectionEdgeMargin;
  final nearHi = (hi - naturalLanding) <= kSectionEdgeMargin;
  if (nearLo && !nearHi) return _commit(lo, currentPixels);
  if (nearHi && !nearLo) return _commit(hi, currentPixels);

  // Committed switch: snap to the frame in the travel direction (controller
  // direction first, then the fling sign, then the nearest frame).
  final dir = scrollDirection != 0 ? scrollDirection : velocity.sign;
  final double target;
  if (dir > 0) {
    target = hi;
  } else if (dir < 0) {
    target = lo;
  } else {
    target = (naturalLanding - lo) <= (hi - naturalLanding) ? lo : hi;
  }
  return _commit(target, currentPixels);
}

/// `null` when [target] is already aligned with [currentPixels] (± epsilon).
double? _commit(double target, double currentPixels) {
  if ((target - currentPixels).abs() <= kSnapEpsilon) return null;
  return target;
}

/// First point `>= value` (± epsilon), or `null` when [value] is beyond the last.
double? _firstAtOrAfter(List<double> sorted, double value) {
  for (final p in sorted) {
    if (p >= value - kSnapEpsilon) return p;
  }
  return null;
}

/// Last point `<= value` (± epsilon), or `null` when [value] is below the first.
double? _lastAtOrBefore(List<double> sorted, double value) {
  for (var i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i] <= value + kSnapEpsilon) return sorted[i];
  }
  return null;
}
