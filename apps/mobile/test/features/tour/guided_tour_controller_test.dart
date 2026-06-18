import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/tour/models/tour_step.dart';
import 'package:facteur/features/tour/providers/guided_tour_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé de persistance « vu » pour l'utilisateur anonyme (aucun user injecté →
/// le controller retombe sur `'anonymous'`).
const _seenKey = 'nudge.guided_tour.seen.anonymous';

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      // Évite l'init Supabase du vrai notifier ; user null → userId 'anonymous'.
      authStateProvider.overrideWith(
        (ref) => AuthStateNotifier.test(const AuthState()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start → essentielHero quand jamais vu', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    var completed = 0;
    await c
        .read(guidedTourControllerProvider.notifier)
        .start(onComplete: () => completed++);

    expect(c.read(guidedTourControllerProvider), TourStep.essentielHero);
    expect(completed, 0, reason: 'onComplete ne se déclenche pas au démarrage');
  });

  test('next() parcourt toute la séquence puis termine', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    final notifier = c.read(guidedTourControllerProvider.notifier);
    var completed = 0;
    await notifier.start(onComplete: () => completed++);

    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.descendsCartes);
    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.favorisSheet);
    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.flaner);
    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.reglages);
    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.courrier);
    // Dernière étape → conclusion + onComplete.
    notifier.next();
    expect(c.read(guidedTourControllerProvider), TourStep.done);
    expect(completed, 1);
  });

  test('displayIndex mutualise le point 2 entre les deux panneaux', () {
    expect(TourStep.essentielHero.displayIndex, 1);
    expect(TourStep.descendsCartes.displayIndex, 2);
    expect(TourStep.favorisSheet.displayIndex, 2);
    expect(TourStep.flaner.displayIndex, 3);
    expect(TourStep.reglages.displayIndex, 4);
    expect(TourStep.courrier.displayIndex, 5);
    expect(TourStepDisplay.totalSteps, 5);
  });

  test('finish() → done, flag persisté, onComplete une seule fois', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    final notifier = c.read(guidedTourControllerProvider.notifier);
    var completed = 0;
    await notifier.start(onComplete: () => completed++);

    notifier.finish();
    expect(c.read(guidedTourControllerProvider), TourStep.done);
    // finish() idempotent : un second appel ne re-tire pas onComplete.
    notifier.finish();
    expect(completed, 1);

    // Persistance asynchrone (unawaited dans finish).
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_seenKey), true);
  });

  test('skip() → done + onComplete', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    final notifier = c.read(guidedTourControllerProvider.notifier);
    var completed = 0;
    await notifier.start(onComplete: () => completed++);

    notifier.skip();
    expect(c.read(guidedTourControllerProvider), TourStep.done);
    expect(completed, 1);
  });

  test('dismiss() retire la carte de conclusion', () async {
    SharedPreferences.setMockInitialValues({});
    final c = _container();
    final notifier = c.read(guidedTourControllerProvider.notifier);
    await notifier.start(onComplete: () {});
    notifier.finish();
    notifier.dismiss();
    expect(c.read(guidedTourControllerProvider), isNull);
  });

  test('start() no-op si déjà vu, mais onComplete tiré une fois', () async {
    SharedPreferences.setMockInitialValues({_seenKey: true});
    final c = _container();
    var completed = 0;
    await c
        .read(guidedTourControllerProvider.notifier)
        .start(onComplete: () => completed++);

    expect(c.read(guidedTourControllerProvider), isNull);
    expect(completed, 1, reason: 'rend la main directement aux modales');
  });
}
