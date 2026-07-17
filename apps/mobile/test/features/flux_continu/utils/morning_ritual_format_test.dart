import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // formatFrenchLongDate
  // ---------------------------------------------------------------------------
  group('formatFrenchLongDate', () {
    test('lundi (1er janvier 2024)', () {
      expect(formatFrenchLongDate(DateTime(2024, 1, 1)), 'lundi 1 janvier');
    });

    test('mercredi 27 mai (exemple PO)', () {
      expect(formatFrenchLongDate(DateTime(2026, 5, 27)), 'mercredi 27 mai');
    });

    test('mois accentués (février, août)', () {
      expect(formatFrenchLongDate(DateTime(2024, 2, 29)), 'jeudi 29 février');
      expect(formatFrenchLongDate(DateTime(2024, 8, 15)), 'jeudi 15 août');
    });

    test('décembre', () {
      expect(formatFrenchLongDate(DateTime(2024, 12, 25)), 'mercredi 25 décembre');
    });
  });

  // ---------------------------------------------------------------------------
  // formatFrenchShortWeekdayDay
  // ---------------------------------------------------------------------------
  group('formatFrenchShortWeekdayDay', () {
    test('abrège le jour de semaine + numéro', () {
      expect(formatFrenchShortWeekdayDay(DateTime(2026, 5, 27)), 'mer. 27');
      expect(formatFrenchShortWeekdayDay(DateTime(2024, 1, 1)), 'lun. 1');
    });
  });

  // ---------------------------------------------------------------------------
  // editionDayKey — libellé calendaire brut (aucune conversion tz)
  // ---------------------------------------------------------------------------
  group('editionDayKey', () {
    test('formate YYYY-MM-DD zéro-paddé', () {
      expect(editionDayKey(DateTime(2026, 6, 3)), '2026-06-03');
      expect(editionDayKey(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('minuit local = même jour calendaire (pas de bascule 7h30)', () {
      expect(editionDayKey(DateTime(2026, 6, 23)), '2026-06-23');
    });
  });
}
