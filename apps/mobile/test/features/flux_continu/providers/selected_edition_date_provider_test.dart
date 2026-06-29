import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('editionTodayDate — frontière 7h30', () {
    test('06:00 Paris (avant 7h30) → édition de la veille', () {
      // DateTime.utc(2026,6,23,4) = 06:00 Paris (CEST, UTC+2).
      final now = DateTime.utc(2026, 6, 23, 4);
      expect(editionTodayDate(now: now), DateTime(2026, 6, 22));
    });

    test('08:00 Paris (après 7h30) → édition du jour', () {
      // DateTime.utc(2026,6,23,6) = 08:00 Paris.
      final now = DateTime.utc(2026, 6, 23, 6);
      expect(editionTodayDate(now: now), DateTime(2026, 6, 23));
    });
  });

  group('editionPillModel — ordre + cardinalité', () {
    final now = DateTime.utc(2026, 6, 23, 12); // mardi, 14h Paris
    final pills = editionPillModel(now: now);

    test('3 pills : semaine + aujourd\'hui + 1 jour passé (rewind à 3 options)',
        () {
      expect(pills.length, 2 + kEditionMaxPastDays);
      expect(pills.length, 3);
    });

    test('ordre : Cette semaine, Aujourd\'hui, Hier (J-1)', () {
      expect(pills[0], isA<EditionWeek>());
      expect(pills[1], isA<EditionToday>());
      expect(pills[2], isA<EditionPastDay>());
      expect((pills[2] as EditionPastDay).date, DateTime(2026, 6, 22)); // J-1
      // Une seule lettre passée : la dernière = J-1.
      expect((pills.last as EditionPastDay).date, DateTime(2026, 6, 22));
    });
  });

  group('EditionSelection — égalité & key', () {
    test('EditionToday / EditionWeek sont des singletons par type', () {
      expect(const EditionToday(), const EditionToday());
      expect(const EditionWeek(), const EditionWeek());
      expect(const EditionToday() == const EditionWeek(), isFalse);
    });

    test('EditionPastDay : égalité par jour calendaire (heure ignorée)', () {
      expect(
        EditionPastDay(DateTime(2026, 6, 22)),
        EditionPastDay(DateTime(2026, 6, 22, 9, 30)),
      );
      expect(
        EditionPastDay(DateTime(2026, 6, 22)) ==
            EditionPastDay(DateTime(2026, 6, 21)),
        isFalse,
      );
    });

    test('key', () {
      expect(const EditionToday().key, 'today');
      expect(const EditionWeek().key, 'week');
      expect(EditionPastDay(DateTime(2026, 6, 22)).key, '2026-06-22');
    });
  });

  group('formatFrenchShortWeekdayDay', () {
    test('mardi 23 → "mar. 23"', () {
      expect(formatFrenchShortWeekdayDay(DateTime(2026, 6, 23)), 'mar. 23');
    });

    test('lundi → "lun.", dimanche → "dim."', () {
      expect(formatFrenchShortWeekdayDay(DateTime(2026, 6, 22)), 'lun. 22');
      expect(formatFrenchShortWeekdayDay(DateTime(2026, 6, 28)), 'dim. 28');
    });
  });

  group('editionPillLabel (déplacé depuis edition_date_strip.dart)', () {
    final now = DateTime.utc(2026, 6, 23, 12); // mardi, 14h Paris

    test('Cette semaine / Aujourd\'hui', () {
      expect(editionPillLabel(const EditionWeek(), now: now), 'Cette semaine');
      expect(editionPillLabel(const EditionToday(), now: now), 'Aujourd’hui');
    });

    test('J-1 → « Hier »', () {
      expect(
        editionPillLabel(EditionPastDay(DateTime(2026, 6, 22)), now: now),
        'Hier',
      );
    });

    test('J-2 et au-delà → libellé court « ven. 19 »', () {
      expect(
        editionPillLabel(EditionPastDay(DateTime(2026, 6, 19)), now: now),
        'ven. 19',
      );
    });
  });
}
