import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/providers/veille_config_provider.dart';

void main() {
  group('VeilleConfigNotifier — purpose + brief setters (PR B)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('setPurpose stores slug', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('preparer_projet');
      expect(container.read(veilleConfigProvider).purpose, 'preparer_projet');
    });

    test('setPurpose to non-autre clears purposeOther', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('rédiger un livre');
      expect(container.read(veilleConfigProvider).purposeOther, 'rédiger un livre');

      notifier.setPurpose('culture_generale');
      expect(container.read(veilleConfigProvider).purpose, 'culture_generale');
      expect(container.read(veilleConfigProvider).purposeOther, isNull);
    });

    test('setPurpose to autre keeps purposeOther', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('rédiger un livre');
      // Re-set purpose to autre — purposeOther doit rester (re-tap UX).
      notifier.setPurpose('autre');
      expect(container.read(veilleConfigProvider).purposeOther, 'rédiger un livre');
    });

    test('setEditorialBrief trims and treats empty as null', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setEditorialBrief('  Plutôt analyses long format  ');
      expect(
        container.read(veilleConfigProvider).editorialBrief,
        'Plutôt analyses long format',
      );

      notifier.setEditorialBrief('   ');
      expect(container.read(veilleConfigProvider).editorialBrief, isNull);
    });

    test('setPurposeOther trims and treats empty as null', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('  veille perso  ');
      expect(container.read(veilleConfigProvider).purposeOther, 'veille perso');

      notifier.setPurposeOther('');
      expect(container.read(veilleConfigProvider).purposeOther, isNull);
    });
  });
}
