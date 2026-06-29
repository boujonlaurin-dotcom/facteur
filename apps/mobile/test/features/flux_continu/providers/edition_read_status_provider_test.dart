import 'package:facteur/features/flux_continu/providers/edition_read_status_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock prefs dès le 1er accès : sans lui, le premier `getInstance()` lève une
  // MissingPluginException et empoisonne le completer singleton pour tout le run.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Référentiel temps fixe (mardi 23/06/2026, 14h Paris) pour les jours passés.
  final now = DateTime.utc(2026, 6, 23, 12);
  final today = editionTodayDate(now: now); // 2026-06-23
  // La logique lu/non-lu est indépendante de la profondeur du sélecteur
  // (`kEditionMaxPastDays`, réduit à 1) : on fabrique 7 jours passés pour les
  // fixtures (l'agrégat « Cette semaine » couvre toujours J-0…J-6).
  final past = editionPastDays(7, now: now); // J-1 … J-7

  group('EditionReadStatus.isEditionRead — logique pure', () {
    test('today toujours « à jour », même readDayKeys vide', () {
      const status = EditionReadStatus(available: true);
      expect(status.isEditionRead(const EditionToday(), now: null), isTrue);
    });

    test('jour passé : à jour ssi son dayKey ∈ readDayKeys', () {
      final status = EditionReadStatus(
        available: true,
        readDayKeys: {editionDayKey(past[0])}, // J-1 lu
      );
      expect(status.isEditionRead(EditionPastDay(past[0])), isTrue);
      expect(status.isEditionRead(EditionPastDay(past[1])), isFalse);
    });

    test('« Cette semaine » : à jour ssi aucun J-1…J-6 non-lu (J-0 forcé)', () {
      // Tous les J-1…J-6 lus → semaine à jour.
      final allRead = EditionReadStatus(
        available: true,
        readDayKeys: {for (final d in editionPastDays(6, now: now)) editionDayKey(d)},
      );
      expect(allRead.isEditionRead(const EditionWeek(), now: now), isTrue);

      // Un seul jour manquant → semaine non-lue.
      final oneMissing = EditionReadStatus(
        available: true,
        readDayKeys: {
          for (final d in editionPastDays(6, now: now).skip(1)) editionDayKey(d),
        },
      );
      expect(oneMissing.isEditionRead(const EditionWeek(), now: now), isFalse);
    });
  });

  group('editionReadStatusProvider — dégradation gracieuse', () {
    test('streaks vides (gamification off) → available == false', () async {
      final container = ProviderContainer(overrides: [
        streakActivityProvider
            .overrideWith((ref) async => const StreakActivityModel.empty()),
      ]);
      addTearDown(container.dispose);
      // `streakActivityProvider` est autoDispose : on garde le dérivé en écoute
      // pour qu'il reste abonné (sinon il se recrée en `loading` à la lecture).
      final sub = container.listen(editionReadStatusProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(streakActivityProvider.future);
      expect(container.read(editionReadStatusProvider).available, isFalse);
    });

    test('loading (avant résolution) → available == false', () {
      final container = ProviderContainer(overrides: [
        // Future jamais résolu dans cette frame → AsyncLoading.
        streakActivityProvider.overrideWith(
          (ref) => Future.delayed(const Duration(seconds: 30)),
        ),
      ]);
      addTearDown(container.dispose);
      final status = container.read(editionReadStatusProvider);
      expect(status.available, isFalse);
    });
  });

  group('editionReadStatusProvider — union streaks + set local', () {
    test('readDayKeys = jours opened ∪ set local « rattrapé »', () async {
      // Streaks : J-1 opened. Set local « rattrapé » : J-2 (piloté via
      // markCaughtUp, qui met l'état mémoire à jour indépendamment du cache
      // singleton de SharedPreferences — robuste à l'ordre des tests).
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final activity = StreakActivityModel(
        currentStreak: 1,
        longestStreak: 1,
        days: [
          StreakActivityDay(date: today, opened: true),
          StreakActivityDay(date: past[0], opened: true), // J-1 opened
          StreakActivityDay(date: past[2], opened: false), // J-3 non-lu
        ],
      );
      final container = ProviderContainer(overrides: [
        streakActivityProvider.overrideWith((ref) async => activity),
      ]);
      addTearDown(container.dispose);
      // Garde le dérivé (et donc streaks autoDispose) abonné le temps du test.
      final sub = container.listen(editionReadStatusProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(streakActivityProvider.future);
      // Laisse le chargement initial du set local se résoudre, puis ajoute J-2.
      final caughtUp = container.read(editionCaughtUpProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await caughtUp.markCaughtUp(editionDayKey(past[1])); // J-2 rattrapé

      final status = container.read(editionReadStatusProvider);
      expect(status.available, isTrue);
      // J-1 vient de streaks, J-2 du set local.
      expect(status.isEditionRead(EditionPastDay(past[0])), isTrue);
      expect(status.isEditionRead(EditionPastDay(past[1])), isTrue);
      // J-3 explicitement non-lu.
      expect(status.isEditionRead(EditionPastDay(past[2])), isFalse);
      // today toujours à jour.
      expect(status.isEditionRead(const EditionToday()), isTrue);
    });
  });

  group('EditionCaughtUpNotifier — persistance', () {
    test('markCaughtUp ajoute la clé et la persiste', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editionCaughtUpProvider.notifier);
      await notifier.markCaughtUp('2026-06-20');
      expect(container.read(editionCaughtUpProvider), contains('2026-06-20'));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(kEditionCaughtUpPrefsKey),
        contains('2026-06-20'),
      );
    });

    test('markCaughtUp est idempotent (no-op si déjà présent)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editionCaughtUpProvider.notifier);
      await notifier.markCaughtUp('2026-06-20');
      final first = container.read(editionCaughtUpProvider);
      await notifier.markCaughtUp('2026-06-20');
      expect(container.read(editionCaughtUpProvider), first);
    });
  });
}
