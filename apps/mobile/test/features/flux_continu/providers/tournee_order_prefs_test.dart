import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clés typées', () {
    test('produisent des préfixes alignés sur sectionKey()', () {
      expect(tourneeThemeKey('tech'), 'theme:tech');
      expect(tourneeSourceKey('s1'), 'source:s1');
      expect(kTourneeActusKey, 'essentiel');
      expect(kTourneeBonnesKey, 'bonnes');
      expect(kTourneeGrilleKey, 'grille');
      expect(kTourneeVeilleKey, 'veille');
    });
  });

  group('applyOrder (réexporté)', () {
    String keyOf(String s) => s;

    test('ordre vide → items inchangés', () {
      expect(applyOrder(['a', 'b', 'c'], const [], keyOf), ['a', 'b', 'c']);
    });

    test('réordonne selon order, items absents en fin (stable)', () {
      expect(applyOrder(['a', 'b', 'c', 'd'], const ['c', 'a'], keyOf), [
        'c',
        'a',
        'b',
        'd',
      ]);
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

    test(
      'setOrder persiste sous tournee_order_v1 + met à jour le state',
      () async {
        final notifier = TourneeOrderPrefsNotifier();
        await notifier.setOrder(['theme:tech', 'source:s1', 'veille']);

        expect(notifier.state.order, ['theme:tech', 'source:s1', 'veille']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('tournee_order_v1'), [
          'theme:tech',
          'source:s1',
          'veille',
        ]);
      },
    );

    test('setHidden persiste sous tournee_hidden_keys_v1', () async {
      final notifier = TourneeOrderPrefsNotifier();

      await notifier.setHidden(kTourneeActusKey, true);
      await notifier.setHidden(kTourneeGrilleKey, true);
      expect(notifier.state.hiddenKeys, {kTourneeActusKey, kTourneeGrilleKey});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tournee_hidden_keys_v1'), [
        kTourneeActusKey,
        kTourneeGrilleKey,
      ]);

      await notifier.setHidden(kTourneeActusKey, false);
      expect(notifier.state.hiddenKeys, {kTourneeGrilleKey});
      expect(prefs.getStringList('tournee_hidden_keys_v1'), [
        kTourneeGrilleKey,
      ]);
    });

    test(
      'setVeilleHidden shim met à jour hiddenKeys + getter compat',
      () async {
        final notifier = TourneeOrderPrefsNotifier();
        expect(notifier.state.veilleHidden, isFalse);

        await notifier.setVeilleHidden(true);
        expect(notifier.state.veilleHidden, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('tournee_hidden_keys_v1'), [
          kTourneeVeilleKey,
        ]);
      },
    );

    test('_load relit l\'ordre + hiddenKeys depuis les prefs', () async {
      SharedPreferences.setMockInitialValues({
        'tournee_order_v1': ['source:s1', 'theme:tech'],
        'tournee_hidden_keys_v1': [kTourneeActusKey, kTourneeVeilleKey],
      });
      final notifier = TourneeOrderPrefsNotifier();
      // _load est async (déclenché dans le constructeur) → on laisse passer un tick.
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.order, ['source:s1', 'theme:tech']);
      expect(notifier.state.hiddenKeys, {kTourneeActusKey, kTourneeVeilleKey});
      expect(notifier.state.veilleHidden, isTrue);
    });

    test(
      '_load migre le bool legacy veille vers hiddenKeys sans réécrire',
      () async {
        SharedPreferences.setMockInitialValues({
          'tournee_veille_hidden_v1': true,
        });
        final notifier = TourneeOrderPrefsNotifier();
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.hiddenKeys, {kTourneeVeilleKey});
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('tournee_hidden_keys_v1'), isNull);
      },
    );

    test('_load ignore le bool legacy si la nouvelle clé existe', () async {
      SharedPreferences.setMockInitialValues({
        'tournee_hidden_keys_v1': <String>[],
        'tournee_veille_hidden_v1': true,
      });
      final notifier = TourneeOrderPrefsNotifier();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.hiddenKeys, isEmpty);
      expect(notifier.state.veilleHidden, isFalse);
    });

    test(
      'markCustomized persiste sous tournee_customized_v1 (idempotent)',
      () async {
        final notifier = TourneeOrderPrefsNotifier();
        expect(notifier.state.customized, isFalse);

        await notifier.markCustomized();
        expect(notifier.state.customized, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('tournee_customized_v1'), isTrue);

        // Idempotent : un 2ᵉ appel ne change rien.
        await notifier.markCustomized();
        expect(notifier.state.customized, isTrue);
      },
    );

    test('_load restaure customized depuis les prefs', () async {
      SharedPreferences.setMockInitialValues({'tournee_customized_v1': true});
      final notifier = TourneeOrderPrefsNotifier();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.customized, isTrue);
    });
  });
}
