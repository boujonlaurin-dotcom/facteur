import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_snap.dart';

void main() {
  // Canonical layout, top→bottom:
  // - a short section at 0 (bottom == top ⇒ no free zone);
  // - a TALL section framed 300 (top) … 600 (bottom) ⇒ free interior (300, 600);
  // - a short section at 1200.
  // Snap points = {0, 300, 600, 1200}; transition zone (600, 1200) is wide so
  // the edge-margin deadband and the directional commit are both exercisable.
  const List<SectionFrame> frames = [
    (top: 0.0, bottom: 0.0),
    (top: 300.0, bottom: 600.0),
    (top: 1200.0, bottom: 1200.0),
  ];
  // Margin-relative offsets so these tests stay valid if the knob is tuned.
  const within = kSectionEdgeMargin - 10; // inside the deadband
  const beyond = kSectionEdgeMargin + 10; // past it ⇒ commit

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

    test('a small overshoot past the section bottom is pulled back (margin)',
        () {
      // Down, only `within` px past the 600 bottom: the deadband re-frames the
      // section's last cards (600) instead of switching to the next one.
      final target = resolveSnapTarget(
        currentPixels: 580,
        naturalLanding: 600 + within,
        velocity: 60,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('past the margin, scrolling down commits to the next section top', () {
      // Down, `beyond` the deadband: now it switches forward to the next frame.
      final target = resolveSnapTarget(
        currentPixels: 650,
        naturalLanding: 600 + beyond,
        velocity: 60,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 1200.0);
    });

    test('a small overshoot above a section top is pulled back (margin)', () {
      // Up, only `within` px above the 1200 top: the deadband keeps it framed on
      // 1200 rather than jumping back to the previous section.
      final target = resolveSnapTarget(
        currentPixels: 1180,
        naturalLanding: 1200 - within,
        velocity: -60,
        scrollDirection: -1, // up
        frames: frames,
      );
      expect(target, 1200.0);
    });

    test('past the margin, scrolling up commits to the previous section bottom',
        () {
      // Up, `beyond` the deadband below the 1200 top: switch back to frame the
      // previous section's last cards (600).
      final target = resolveSnapTarget(
        currentPixels: 1150,
        naturalLanding: 1200 - beyond,
        velocity: -60,
        scrollDirection: -1, // up
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('poses on the tall section bottom (its last cards) when reaching it',
        () {
      // Landing flush on the bottom frame ⇒ rest there.
      final target = resolveSnapTarget(
        currentPixels: 520,
        naturalLanding: 600,
        velocity: 40,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('entering a tall section from below poses on its top', () {
      // Landing exactly on the tall section top (300): pose on it. Past it is
      // the free zone.
      final target = resolveSnapTarget(
        currentPixels: 250,
        naturalLanding: 300,
        velocity: 40,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 300.0);
    });

    test('a short section commits to the next top once past the margin (down)',
        () {
      // Mid-gap between the short section (0) and the tall top (300): beyond the
      // deadband ⇒ pose forward on 300.
      final target = resolveSnapTarget(
        currentPixels: 20,
        naturalLanding: 150,
        velocity: 80,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 300.0);
    });

    test('the margin also holds a short section for a tiny nudge', () {
      // A `within`-px nudge down off the short top (0): pulled back to 0.
      final target = resolveSnapTarget(
        currentPixels: 10,
        naturalLanding: within,
        velocity: 30,
        scrollDirection: 1, // down
        frames: frames,
      );
      expect(target, 0.0);
    });

    test('the controller direction wins over a noisy near-zero lift velocity',
        () {
      // Resting mid-transition (900), heading DOWN per the controller. Whatever
      // the noisy lift velocity reports, commit forward on 1200.
      for (final v in [0.0, -5.0, 12.0]) {
        final target = resolveSnapTarget(
          currentPixels: 900,
          naturalLanding: 900 + v / 10,
          velocity: v,
          scrollDirection: 1, // down (from the controller, reliable)
          frames: frames,
        );
        expect(target, 1200.0, reason: 'velocity=$v should commit to 1200');
      }
    });

    test('scrolling down beyond the last short entry frames it as the finale',
        () {
      // Regression for "Fin de tournée": the final virtual entry is short, so
      // overshooting it at the bottom of the flow must still settle on its frame.
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
      // scrollDirection 0 (idle) ⇒ use velocity.sign. Upward velocity mid-gap ⇒
      // commit back to 600.
      final target = resolveSnapTarget(
        currentPixels: 900,
        naturalLanding: 900,
        velocity: -100, // up
        scrollDirection: 0,
        frames: frames,
      );
      expect(target, 600.0);
    });

    test('falls back to the nearest frame when both direction signals are zero',
        () {
      // scrollDirection 0 and velocity 0 ⇒ nearest frame to the landing (600).
      final target = resolveSnapTarget(
        currentPixels: 500,
        naturalLanding: 850,
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
