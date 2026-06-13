import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';

void main() {
  const specs = [
    DisplayModeSpec.normal,
    DisplayModeSpec.minimal,
    DisplayModeSpec.playful,
  ];

  test('minimal hides images, normal and playful show them', () {
    expect(DisplayModeSpec.minimal.showImages, isFalse);
    expect(DisplayModeSpec.normal.showImages, isTrue);
    expect(DisplayModeSpec.playful.showImages, isTrue);
  });

  test('card heights are ordered minimal < normal < playful', () {
    expect(
      DisplayModeSpec.minimal.regularCardHeight,
      lessThan(DisplayModeSpec.normal.regularCardHeight),
    );
    expect(
      DisplayModeSpec.normal.regularCardHeight,
      lessThan(DisplayModeSpec.playful.regularCardHeight),
    );
    expect(
      DisplayModeSpec.minimal.heroLeadHeight,
      lessThan(DisplayModeSpec.normal.heroLeadHeight),
    );
    expect(
      DisplayModeSpec.normal.heroLeadHeight,
      lessThan(DisplayModeSpec.playful.heroLeadHeight),
    );
    expect(
      DisplayModeSpec.minimal.heroMediumHeight,
      lessThan(DisplayModeSpec.normal.heroMediumHeight),
    );
    expect(
      DisplayModeSpec.normal.heroMediumHeight,
      lessThan(DisplayModeSpec.playful.heroMediumHeight),
    );
  });

  test('all heights and font scales are positive', () {
    for (final spec in specs) {
      expect(spec.regularCardHeight, greaterThan(0));
      expect(spec.heroLeadHeight, greaterThan(0));
      expect(spec.heroMediumHeight, greaterThan(0));
      expect(spec.fontScale, greaterThan(0));
    }
  });

  test('normal heights match the historical section_fit constants', () {
    expect(DisplayModeSpec.normal.regularCardHeight, 146);
    expect(DisplayModeSpec.normal.heroLeadHeight, 160);
    expect(DisplayModeSpec.normal.heroMediumHeight, 88);
  });

  test('playful : image élément principal (image on top, textes recalibrés)',
      () {
    const p = DisplayModeSpec.playful;
    expect(p.imageOnTop, isTrue);
    expect(p.regularImageHeight, 130); // raccourcie (170→130) pour tenir 2-3
    expect(p.thumbSize, 0); // plus de thumb carré à droite
    expect(p.fontScale, 1.05); // était 1.15, trop grossi
    expect(p.regularCardHeight, 272); // image 130 + bloc texte
    expect(p.heroLeadHeight, 164);
    expect(p.heroMediumHeight, 90);
  });

  test('normal/minimal gardent le layout thumb à droite', () {
    expect(DisplayModeSpec.normal.imageOnTop, isFalse);
    expect(DisplayModeSpec.minimal.imageOnTop, isFalse);
    expect(DisplayModeSpec.normal.regularImageHeight, 0);
  });

  test('titres des cartes régulières : 4 normal / 5 minimal / 3 ludique', () {
    expect(DisplayModeSpec.normal.regularTitleMaxLines, 4);
    expect(DisplayModeSpec.minimal.regularTitleMaxLines, 5);
    expect(DisplayModeSpec.playful.regularTitleMaxLines, 3);
  });

  test('titleMaxLinesDelta (hero-only) : 0/0/-1', () {
    expect(DisplayModeSpec.normal.titleMaxLinesDelta, 0);
    expect(DisplayModeSpec.minimal.titleMaxLinesDelta, 0);
    expect(DisplayModeSpec.playful.titleMaxLinesDelta, -1);
  });

  test('sectionFitCeiling : chaque mode porte son plafond (cibles 3-4/4-6/2-3)',
      () {
    expect(DisplayModeSpec.normal.sectionFitCeiling, 4);
    expect(DisplayModeSpec.minimal.sectionFitCeiling, 6);
    expect(DisplayModeSpec.playful.sectionFitCeiling, 3);
  });
}
