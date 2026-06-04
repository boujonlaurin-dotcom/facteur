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
/// no edge shows). Once an edge crosses into the viewport the scroll **snaps**,
/// with a hard **one-step cap**: whatever the fling's strength, the commit
/// target is always the frame **adjacent to the finger-lift position**
/// ([currentPixels]) in the travel direction — never bracketed around where the
/// fling *would* land. So a violent fling can no longer skip several sections at
/// once: it advances exactly one frame, the active section flips once, and the
/// screen fires a single haptic. The reader chains quick flings to descend.
/// - a *small* overshoot (the fling carries less than [kSectionEdgeMargin] past
///   the lift point) re-frames the **current** section — a margin before the
///   card actually switches («&nbsp;collant&nbsp;» à la carte courante);
/// - a *larger* fling commits **one** frame in the travel direction (down ⇒
///   next snap point, up ⇒ previous one).
/// A section shorter than the viewport has no free zone, so it always snaps.
///
/// Pure arithmetic — no Flutter binding — so it is unit-testable without the
/// Hive/Supabase bootstrap that the widget suite needs.
///
/// - [currentPixels]   : scroll offset at finger lift. **The commit anchor** —
///   the target is always one frame away from here.
/// - [naturalLanding]  : where the platform ballistic *would* settle. Used only
///   to (a) detect free-reading inside a tall section and (b) measure the fling
///   overshoot magnitude for the deadband — **not** as the commit bracket, so
///   the target stays un-skippable regardless of fling strength.
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

  // Travel direction: controller first, then the fling sign (lift velocity).
  final dir = scrollDirection != 0 ? scrollDirection : velocity.sign;

  // Deadband (« marge »): how far the fling's inertia carries past the lift
  // point. A small overshoot — or no direction at all — re-frames the section
  // the reader is on (pull-back to the nearest snap point); it must exceed the
  // margin before the card actually switches.
  final overshoot = (naturalLanding - currentPixels).abs();
  if (overshoot < kSectionEdgeMargin || dir == 0) {
    return _commit(_nearest(points, currentPixels), currentPixels);
  }

  // One-step commit: the snap point ADJACENT to the lift position in the travel
  // direction. Because the target is anchored on [currentPixels] (not on
  // [naturalLanding]), a stronger fling can never bracket — and so never skip —
  // a farther section: it always advances exactly one frame. When there is no
  // neighbour in that direction (already at the extremity) fall back to the
  // nearest frame so a hard fling past the last entry still settles on it.
  if (dir > 0) {
    final next = _firstStrictlyAfter(points, currentPixels);
    return _commit(next ?? _nearest(points, currentPixels), currentPixels);
  }
  final prev = _lastStrictlyBefore(points, currentPixels);
  return _commit(prev ?? _nearest(points, currentPixels), currentPixels);
}

/// `null` when [target] is already aligned with [currentPixels] (± epsilon).
double? _commit(double target, double currentPixels) {
  if ((target - currentPixels).abs() <= kSnapEpsilon) return null;
  return target;
}

/// First point strictly `> value` (beyond ± epsilon), or `null` when [value]
/// is at/after the last point.
double? _firstStrictlyAfter(List<double> sorted, double value) {
  for (final p in sorted) {
    if (p > value + kSnapEpsilon) return p;
  }
  return null;
}

/// Last point strictly `< value` (before ± epsilon), or `null` when [value]
/// is at/before the first point.
double? _lastStrictlyBefore(List<double> sorted, double value) {
  for (var i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i] < value - kSnapEpsilon) return sorted[i];
  }
  return null;
}

/// Point closest to [value] (ties resolve to the lower point). [sorted] is
/// non-empty at every call site (the empty-frames guard returns early).
double _nearest(List<double> sorted, double value) {
  var best = sorted.first;
  var bestDist = (best - value).abs();
  for (final p in sorted.skip(1)) {
    final d = (p - value).abs();
    if (d < bestDist) {
      best = p;
      bestDist = d;
    }
  }
  return best;
}
