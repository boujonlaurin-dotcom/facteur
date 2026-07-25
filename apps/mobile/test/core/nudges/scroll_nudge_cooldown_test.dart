import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_registry.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

/// Couvre le contrat « 1×/24 h par cible » des nudges de scroll du reader
/// (« Prendre du recul ? » / « Voir plus de points de vue ? »), piloté par
/// [NudgeService] et non par le coordinator (pas de budget de session global).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  NudgeService makeService(DateTime Function() clock) =>
      NudgeService(storage: NudgeStorage(), clock: clock);

  for (final id in [
    NudgeIds.scrollToDeepReco,
    NudgeIds.scrollToPerspectives,
  ]) {
    group('scroll nudge "$id"', () {
      test('is registered with a 24h cooldown', () {
        final nudge = NudgeRegistry.get(id);
        expect(nudge.cooldown, const Duration(days: 1));
      });

      test('showable first, blocked for 24h after markShown, then re-eligible',
          () async {
        var now = DateTime(2026, 7, 24, 9);
        final service = makeService(() => now);

        // Jamais montré → affichable.
        expect(await service.canShow(id), isTrue);

        // Premier affichage réel : pose le cooldown.
        await service.markShown(id);

        // Même journée, < 24 h plus tard → bloqué (« ne réapparaît plus
        // aujourd'hui »).
        now = DateTime(2026, 7, 24, 20);
        expect(await service.canShow(id), isFalse);

        // > 24 h plus tard → de nouveau éligible.
        now = DateTime(2026, 7, 25, 10);
        expect(await service.canShow(id), isTrue);
      });
    });
  }

  test('deep-reco and perspectives cooldowns are independent', () async {
    final now = DateTime(2026, 7, 24, 9);
    final service = makeService(() => now);

    await service.markShown(NudgeIds.scrollToDeepReco);

    // Voir le nudge pas de recul n'entame pas le cooldown des perspectives.
    expect(await service.canShow(NudgeIds.scrollToDeepReco), isFalse);
    expect(await service.canShow(NudgeIds.scrollToPerspectives), isTrue);
  });
}
