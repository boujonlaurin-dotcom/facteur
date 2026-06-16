import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_snap.dart';

void main() {
  // Canonical layout, top→bottom:
  // - a short section at 0 (bottom == top ⇒ no free zone);
  // - a TALL section framed 300 (top) … 600 (bottom) ⇒ free interior (300, 600);
  // - a short section at 1200.
  // Snap points = {0, 300, 600, 1200}. The 600→1200 gap is wide so the
  // one-step cap (you only ever advance to the ADJACENT point) is testable.
  const List<SectionFrame> frames = [
    (top: 0.0, bottom: 0.0),
    (top: 300.0, bottom: 600.0),
    (top: 1200.0, bottom: 1200.0),
  ];
  // Margin-relative offsets so these tests stay valid if the knob is tuned.
  const within = kSectionEdgeMargin - 10; // inside the deadband
  const beyond = kSectionEdgeMargin + 10; // past it ⇒ commit

  group('snapPointsOf', () {
    test('canonical frames yield each top + each tall bottom, sorted', () {
      // Short@0 (no bottom), tall 300…600 (both), short@1200 (no bottom).
      expect(snapPointsOf(frames), [0.0, 300.0, 600.0, 1200.0]);
    });

    test('a short section contributes a single point (bottom == top)', () {
      expect(snapPointsOf(const [(top: 50.0, bottom: 50.0)]), [50.0]);
    });

    test('empty frames yield no points', () {
      expect(snapPointsOf(const []), isEmpty);
    });

    test('is the source of truth resolveSnapTarget commits to', () {
      // Every committed target must be one of the published snap points — the
      // guarantee that the drag-time cue (which reads snapPointsOf) ramps to
      // exactly where the snap lands.
      final points = snapPointsOf(frames);
      final target = resolveSnapTarget(
        currentPixels: 10,
        naturalLanding: 5000,
        velocity: 9000,
        scrollDirection: 1,
        frames: frames,
      );
      expect(points, contains(target));
    });
  });

  group('resolveSnapTarget', () {
    test('free while inside a tall section (it fills the screen)', () {
      // Landing at 450, inside the (300, 600) interior: no edge shows ⇒ free,
      // regardless of travel direction.
      for (final dir in [1.0, -1.0]) {
        final target = resolveSnapTarget(
          currentPixels: 430,
          naturalLanding: 450,
          velocity: 0,
          scrollDirection: dir,
          frames: frames,
        );
        expect(target, isNull, reason: 'dir=$dir should stay free at 450');
      }
    });

    // --- One-step cap: a fling NEVER skips a section ------------------------

    test('a violent fling down only advances ONE frame (never skips)', () {
      // Lift just past the short top (10) with a huge natural landing way past
      // 1200. The old bracketing would commit near the landing (skipping
      // 300/600). The cap pins the target to the adjacent point: 300.
      final target = resolveSnapTarget(
        currentPixels: 10,
        naturalLanding: 5000,
        velocity: 9000,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 300.0);
    });

    test('a violent fling up only recedes ONE frame (never skips)', () {
      // Lift at the last frame (1200) with a huge upward landing past 0. Cap ⇒
      // previous adjacent point only: 600.
      final target = resolveSnapTarget(
        currentPixels: 1200,
        naturalLanding: -5000,
        velocity: -9000,
        scrollDirection: -1, // up
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('a hard fling from inside a tall section stops at its bottom (one step)',
        () {
      // Lift inside the (300, 600) interior, huge landing past the section.
      // The cap advances to the section's own bottom frame (600), not beyond.
      final target = resolveSnapTarget(
        currentPixels: 320,
        naturalLanding: 5000,
        velocity: 9000,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 600.0);
    });

    // --- Directional one-step commits --------------------------------------

    test('past the margin, scrolling down commits to the next adjacent frame',
        () {
      // Lift on the tall bottom (600), fling carries `beyond` the margin ⇒
      // advance one frame to 1200.
      final target = resolveSnapTarget(
        currentPixels: 600,
        naturalLanding: 600 + beyond,
        velocity: 300,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 1200.0);
    });

    test('past the margin, scrolling up commits to the previous adjacent frame',
        () {
      // Lift on the tall bottom (600), fling up clearing the (300,600) free
      // zone entirely ⇒ recede one frame to the tall top (300).
      final target = resolveSnapTarget(
        currentPixels: 600,
        naturalLanding: 100, // past the tall top, out of the free interior
        velocity: -300,
        scrollDirection: -1, // up
        frames: frames,
      );
      expect(target, 300.0);
    });

    test('a gentle approach to a tall section top poses on it', () {
      // Lift below the tall top (250) and coast to land on 300: within the
      // margin ⇒ re-frame on the nearest snap point, the tall top. (A *harder*
      // fling would land inside the (300,600) free zone and stay free.)
      final target = resolveSnapTarget(
        currentPixels: 250,
        naturalLanding: 300,
        velocity: 40,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 300.0);
    });

    // --- Deadband (pull-back) ----------------------------------------------

    test('a small overshoot past a frame is pulled back to it (margin, down)',
        () {
      // Lift just past 600, fling carries only `within` the margin ⇒ re-frame
      // the current section (pull back to 600) instead of switching.
      final target = resolveSnapTarget(
        currentPixels: 620,
        naturalLanding: 620 + within,
        velocity: 60,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('a small overshoot before a frame is pulled back to it (margin, up)',
        () {
      // Lift just before the finale frame (1180) heading up, fling within the
      // margin ⇒ pull back to the nearest frame (1200) rather than receding.
      final target = resolveSnapTarget(
        currentPixels: 1180,
        naturalLanding: 1180 - within,
        velocity: -60,
        scrollDirection: -1, // up
        frames: frames,
      );
      expect(target, 1200.0);
    });

    // --- Direction sourcing -------------------------------------------------

    test('the controller direction wins over a noisy near-zero lift velocity',
        () {
      // Lift on 600 heading DOWN per the controller, with a strong fling.
      // Whatever the noisy lift velocity reports, commit forward one frame.
      for (final v in [0.0, -5.0, 12.0]) {
        final target = resolveSnapTarget(
          currentPixels: 600,
          naturalLanding: 600 + beyond,
          velocity: v,
          scrollDirection: 1, // down (from the controller, reliable)
          frames: frames,
        );
        expect(target, 1200.0, reason: 'velocity=$v should commit to 1200');
      }
    });

    test('scrolling down beyond the last short entry frames it as the finale',
        () {
      // Regression for "Fin de tournée": lift between 600 and 1200 with a
      // strong downward fling ⇒ the adjacent point 1200 (the finale frame).
      final target = resolveSnapTarget(
        currentPixels: 1050,
        naturalLanding: 1350,
        velocity: 220,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 1200.0);
    });

    test('falls back to velocity sign when the controller direction is unknown',
        () {
      // scrollDirection 0 (idle) ⇒ use velocity.sign. Strong upward fling from
      // 900 ⇒ recede one frame to 600.
      final target = resolveSnapTarget(
        currentPixels: 900,
        naturalLanding: 900 - beyond,
        velocity: -300, // up
        scrollDirection: 0,
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('falls back to the nearest frame when both direction signals are zero',
        () {
      // scrollDirection 0 and velocity 0 ⇒ nearest frame to currentPixels.
      final target = resolveSnapTarget(
        currentPixels: 620,
        naturalLanding: 620,
        velocity: 0,
        scrollDirection: 0,
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('returns null for an empty frame list', () {
      final target = resolveSnapTarget(
        currentPixels: 400,
        naturalLanding: 450,
        velocity: 200,
        scrollDirection: 1,
        frames: const [],
      );
      expect(target, isNull);
    });

    test('returns null when already aligned with a frame', () {
      final target = resolveSnapTarget(
        currentPixels: 300,
        naturalLanding: 300.4, // within kSnapEpsilon of the 300 frame
        velocity: 10,
        scrollDirection: 1,
        frames: frames,
      );
      expect(target, isNull);
    });
  });
}
