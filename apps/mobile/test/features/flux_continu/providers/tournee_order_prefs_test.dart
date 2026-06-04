import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clés typées', () {
    test('produisent des préfixes alignés sur sectionKey()', () {
      expect(tourneeThemeKey('tech'), 'theme:tech');
      expect(tourneeSourceKey('s1'), 'source:s1');
      expect(kTourneeVeilleKey, 'veille');
    });
  });

  group('applyOrder (réexporté)', () {
    String keyOf(String s) => s;

    test('ordre vide → items inchangés', () {
      expect(applyOrder(['a', 'b', 'c'], const [], keyOf), ['a', 'b', 'c']);
    });

    test('réordonne selon order, items absents en fin (stable)', () {
      expect(
        applyOrder(['a', 'b', 'c', 'd'], const ['c', 'a'], keyOf),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('mélange thème/source/veille selon les clés', () {
      final items = ['theme:tech', 'source:s1', 'veille'];
      expect(
        applyOrder(items, const ['veille', 'source:s1', 'theme:tech'], keyOf),
        ['veille', 'source:s1', 'theme:tech'],
      );
    });
  });

  group('TourneeOrderPrefsNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setOrder persiste sous tournee_order_v1 + met à jour le state',
        () async {
      final notifier = TourneeOrderPrefsNotifier();
      await notifier.setOrder(['theme:tech', 'source:s1', 'veille']);

      expect(notifier.state.order, ['theme:tech', 'source:s1', 'veille']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('tournee_order_v1'),
        ['theme:tech', 'source:s1', 'veille'],
      );
    });

    test('setVeilleHidden persiste sous tournee_veille_hidden_v1', () async {
      final notifier = TourneeOrderPrefsNotifier();
      expect(notifier.state.veilleHidden, isFalse);

      await notifier.setVeilleHidden(true);
      expect(notifier.state.veilleHidden, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tournee_veille_hidden_v1'), isTrue);
    });

    test('_load relit l\'ordre + le flag veille depuis les prefs', () async {
      SharedPreferences.setMockInitialValues({
        'tournee_order_v1': ['source:s1', 'theme:tech'],
        'tournee_veille_hidden_v1': true,
      });
      final notifier = TourneeOrderPrefsNotifier();
      // _load est async (déclenché dans le constructeur) → on laisse passer un tick.
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.order, ['source:s1', 'theme:tech']);
      expect(notifier.state.veilleHidden, isTrue);
    });
  });
}
