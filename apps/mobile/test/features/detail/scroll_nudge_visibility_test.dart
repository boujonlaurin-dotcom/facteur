import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/detail/screens/content_detail_screen.dart';

/// Base « happy path » : nudge visible. Chaque test dérive de ce cas nominal en
/// ne changeant qu'un signal, pour isoler chaque garde-fou.
ScrollNudgeInputs _base({
  bool armElapsed = true,
  bool spent = false,
  bool webViewActive = false,
  bool ctaTapped = false,
  bool hasActiveScrollController = true,
  bool showPerspectivesBand = true,
  bool isExternal = false,
  bool hasDeepReco = false,
  bool deepRecoMounted = false,
  int perspectivesCount = 2,
  int minCount = 2,
  bool? cooldownOk = true,
  double? targetTopY = 3000,
  double viewportHeight = 800,
  double minBelowFraction = 0.85,
}) {
  return ScrollNudgeInputs(
    armElapsed: armElapsed,
    spent: spent,
    webViewActive: webViewActive,
    ctaTapped: ctaTapped,
    hasActiveScrollController: hasActiveScrollController,
    showPerspectivesBand: showPerspectivesBand,
    isExternal: isExternal,
    hasDeepReco: hasDeepReco,
    deepRecoMounted: deepRecoMounted,
    perspectivesCount: perspectivesCount,
    minCount: minCount,
    cooldownOk: cooldownOk,
    targetTopY: targetTopY,
    viewportHeight: viewportHeight,
    minBelowFraction: minBelowFraction,
  );
}

void main() {
  group('computeScrollNudgeVisibility', () {
    test('happy path (perspectives, offset ignoré, cible sous le pli) → true', () {
      expect(computeScrollNudgeVisibility(_base()), isTrue);
    });

    test('seuil de couverture inclusif : count == minCount → true', () {
      // Bug — la carte affiche la pastille à >= 2 ; le nudge doit s'aligner.
      expect(
        computeScrollNudgeVisibility(_base(perspectivesCount: 2, minCount: 2)),
        isTrue,
      );
    });

    test('count < minCount et pas de deep reco → false', () {
      expect(
        computeScrollNudgeVisibility(_base(perspectivesCount: 1, minCount: 2)),
        isFalse,
      );
    });

    test('délai anti-pop pas encore écoulé → false', () {
      expect(computeScrollNudgeVisibility(_base(armElapsed: false)), isFalse);
    });

    test('déjà consommé sur cet article → false', () {
      expect(computeScrollNudgeVisibility(_base(spent: true)), isFalse);
    });

    test('WebView active → false', () {
      expect(computeScrollNudgeVisibility(_base(webViewActive: true)), isFalse);
    });

    test('CTA tapé (révélation en cours) → false', () {
      expect(computeScrollNudgeVisibility(_base(ctaTapped: true)), isFalse);
    });

    test('aucun contrôleur de scroll actif → false', () {
      expect(
        computeScrollNudgeVisibility(_base(hasActiveScrollController: false)),
        isFalse,
      );
    });

    test('cooldown pas encore résolu (null) → false', () {
      expect(computeScrollNudgeVisibility(_base(cooldownOk: null)), isFalse);
    });

    test('cooldown 24 h non ok → false', () {
      expect(computeScrollNudgeVisibility(_base(cooldownOk: false)), isFalse);
    });

    test('clé de cible non montée (topY null) → false', () {
      expect(computeScrollNudgeVisibility(_base(targetTopY: null)), isFalse);
    });

    test('cible near-fold (au-dessus du seuil below-fold) → false', () {
      // topY = 600, viewport 800, fraction 0.85 → seuil 680 : 600 < 680.
      expect(computeScrollNudgeVisibility(_base(targetTopY: 600)), isFalse);
    });

    test('deep reco monté prime, même count < minCount → true', () {
      expect(
        computeScrollNudgeVisibility(
          _base(
            hasDeepReco: true,
            deepRecoMounted: true,
            perspectivesCount: 0,
          ),
        ),
        isTrue,
      );
    });

    test('hors de la bande perspectives (pas un article) → false', () {
      expect(
        computeScrollNudgeVisibility(_base(showPerspectivesBand: false)),
        isFalse,
      );
    });

    test('article externe → false', () {
      expect(computeScrollNudgeVisibility(_base(isExternal: true)), isFalse);
    });
  });

  group('resolveScrollNudgeTargetKind', () {
    ScrollNudgeTargetKind resolve({
      bool showPerspectivesBand = true,
      bool isExternal = false,
      bool hasDeepReco = false,
      bool deepRecoMounted = false,
      int perspectivesCount = 2,
      int minCount = 2,
    }) {
      return resolveScrollNudgeTargetKind(
        showPerspectivesBand: showPerspectivesBand,
        isExternal: isExternal,
        hasDeepReco: hasDeepReco,
        deepRecoMounted: deepRecoMounted,
        perspectivesCount: perspectivesCount,
        minCount: minCount,
      );
    }

    test('deep reco présent ET monté → deepReco (prioritaire)', () {
      expect(
        resolve(hasDeepReco: true, deepRecoMounted: true, perspectivesCount: 5),
        ScrollNudgeTargetKind.deepReco,
      );
    });

    test('deep reco présent mais NON monté → retombe sur perspectives', () {
      // Bug — branche scroll-vers-le-site : la carte deep-reco n'est pas dans
      // l'arbre ; prioriser sa cible morte bloquait tout le nudge.
      expect(
        resolve(
          hasDeepReco: true,
          deepRecoMounted: false,
          perspectivesCount: 3,
        ),
        ScrollNudgeTargetKind.perspectives,
      );
    });

    test('deep reco NON monté et count insuffisant → none', () {
      expect(
        resolve(
          hasDeepReco: true,
          deepRecoMounted: false,
          perspectivesCount: 1,
          minCount: 2,
        ),
        ScrollNudgeTargetKind.none,
      );
    });

    test('perspectives count == minCount → perspectives', () {
      expect(
        resolve(perspectivesCount: 2, minCount: 2),
        ScrollNudgeTargetKind.perspectives,
      );
    });

    test('hors bande perspectives → none', () {
      expect(resolve(showPerspectivesBand: false), ScrollNudgeTargetKind.none);
    });

    test('externe → none', () {
      expect(resolve(isExternal: true), ScrollNudgeTargetKind.none);
    });
  });
}
