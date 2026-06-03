import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_snap.dart';

void main() {
  // Canonical layout: four section starts, one usable viewport tall apart.
  const anchors = [0.0, 300.0, 600.0, 900.0];
  const viewport = 700.0;

  group('resolveSnapTarget', () {
    test('snaps to the nearest anchor on a calm landing', () {
      // Lands 20px below the 600 anchor, gentle velocity → snap up to 600.
      final target = resolveSnapTarget(
        currentPixels: 540,
        naturalLanding: 620,
        velocity: 40,
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, 600.0);
    });

    test('returns null when landing is deep inside a tall section', () {
      // Tall section 300→1500; user rests at 900, far from both 300 and 1500.
      final target = resolveSnapTarget(
        currentPixels: 880,
        naturalLanding: 900, // |900-300|=600, |900-1500|=600 → both > 350
        velocity: 20,
        anchors: const [0.0, 300.0, 1500.0],
        usableViewport: viewport,
      );
      expect(target, isNull);
    });

    test('commits firmly across the boundary on a fast flick', () {
      // currentPixels just past the 300 boundary; a fast forward flick must not
      // snap back to 300 — it crosses to the next anchor (600).
      final target = resolveSnapTarget(
        currentPixels: 310,
        naturalLanding: 340, // nearest would be 300 (behind the gesture)
        velocity: 600, // > kBoundaryCrossVelocity → firm crossing
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, 600.0);
    });

    test('the same lift snaps backward to the nearest anchor when slow', () {
      // Proves the firmness branch is velocity-gated, while the snap itself is
      // NOT (a slow lift still snaps — just to the nearest anchor).
      final target = resolveSnapTarget(
        currentPixels: 310,
        naturalLanding: 340,
        velocity: 60, // below kBoundaryCrossVelocity
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, 300.0);
    });

    test('snaps on a slow near-anchor lift (un-gated by speed)', () {
      final target = resolveSnapTarget(
        currentPixels: 580,
        naturalLanding: 590, // 10px below the 600 anchor
        velocity: 8, // very slow
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, 600.0);
    });

    test('returns null when already aligned with an anchor', () {
      final target = resolveSnapTarget(
        currentPixels: 600,
        naturalLanding: 600.4, // within kSnapEpsilon of the 600 anchor
        velocity: 10,
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, isNull);
    });

    test('returns null for an empty anchor list', () {
      final target = resolveSnapTarget(
        currentPixels: 400,
        naturalLanding: 450,
        velocity: 200,
        anchors: const [],
        usableViewport: viewport,
      );
      expect(target, isNull);
    });

    test('a hard multi-section fling lands aligned near the natural landing',
        () {
      // Fast fling whose natural landing reaches the third section: we honour
      // the far anchor (900) rather than truncating at the first boundary.
      final target = resolveSnapTarget(
        currentPixels: 120,
        naturalLanding: 880, // nearest = 900
        velocity: 900,
        anchors: anchors,
        usableViewport: viewport,
      );
      expect(target, 900.0);
    });
  });
}
