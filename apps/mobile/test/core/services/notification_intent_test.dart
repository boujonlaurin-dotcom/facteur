import 'package:facteur/core/services/notification_intent.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 10:00 Paris (CEST, UTC+2) le 2026-08-08 → après la frontière 7h30, donc
  // l'édition « aujourd'hui » est le 2026-08-08 (cf. editionTodayDate).
  final now = DateTime.utc(2026, 8, 8, 8);

  group('parseFromFcmData — mapping target_date → édition (#1/#3)', () {
    test(
        'sans target_date → aujourd\'hui (vivant), section nulle, /flux-continu',
        () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'kind': 'daily_digest'},
        now: now,
      );
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });

    test('target_date d\'un jour passé → EditionPastDay figée', () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'target_date': '2026-08-07'},
        now: now,
      );
      expect(intent.edition, EditionPastDay(DateTime(2026, 8, 7)));
      expect(intent.edition.key, '2026-08-07');
      expect(intent.navigationPath, '/flux-continu');
    });

    test('target_date == jour d\'édition courant → EditionToday', () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'target_date': '2026-08-08'},
        now: now,
      );
      expect(intent.edition, const EditionToday());
    });

    test('target_date dans le futur → EditionToday (dégradé sûr)', () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'target_date': '2026-08-09'},
        now: now,
      );
      expect(intent.edition, const EditionToday());
    });

    test('target_date illisible → EditionToday (jamais un plantage)', () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'target_date': 'pas-une-date'},
        now: now,
      );
      expect(intent.edition, const EditionToday());
    });

    test('data vide → défaut EditionToday / /flux-continu', () {
      final intent = NotificationIntent.parseFromFcmData({}, now: now);
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });

    test('section explicite dans data → portée telle quelle', () {
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'section': 'bonnes'},
        now: now,
      );
      expect(intent.section, 'bonnes');
    });

    test('route article (alerte) → passthrough, aucune édition/section imposée',
        () {
      final intent = NotificationIntent.parseFromFcmData(
        {
          'route': '/article/00000000-0000-4000-8000-0000000000a1',
          'kind': 'source_alert',
          'target_date': '2026-08-07',
        },
        now: now,
      );
      expect(
        intent.navigationPath,
        '/article/00000000-0000-4000-8000-0000000000a1',
      );
      // Le mapping target_date reste calculé, mais il ne sera pas appliqué :
      // `targetsFeed` est faux, donc l'applier ne touche pas aux providers du
      // feed (cf. groupe « targetsFeed »). La route n'est pas réécrite.
      expect(intent.targetsFeed, isFalse);
      expect(intent.edition, EditionPastDay(DateTime(2026, 8, 7)));
      expect(intent.section, isNull);
    });
  });

  group('parseFromLocalPayload — payload `route:<url>`', () {
    test('bonnes nouvelles (#2) → section bonnes, aujourd\'hui, /flux-continu',
        () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/flux-continu?section=bonnes',
        now: now,
      );
      expect(intent.section, 'bonnes');
      expect(intent.edition, const EditionToday());
      expect(intent.navigationPath, '/flux-continu');
    });

    test('digest local stampé target_date (Android) → EditionPastDay', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/digest?target_date=2026-08-07',
        now: now,
      );
      expect(intent.edition, EditionPastDay(DateTime(2026, 8, 7)));
      expect(intent.navigationPath, '/flux-continu');
    });

    test('digest local récurrent (route:/digest) → aujourd\'hui', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/digest',
        now: now,
      );
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });

    test('veille (route:/flux-continu) → aujourd\'hui, section nulle', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/flux-continu',
        now: now,
      );
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });

    test('target_date + section combinés', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/digest?target_date=2026-08-07&section=bonnes',
        now: now,
      );
      expect(intent.edition, EditionPastDay(DateTime(2026, 8, 7)));
      expect(intent.section, 'bonnes');
    });

    test('section vide → null (pas de clé pending vide)', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/flux-continu?section=',
        now: now,
      );
      expect(intent.section, isNull);
    });

    test('route article local → passthrough', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/article/abc',
        now: now,
      );
      expect(intent.navigationPath, '/article/abc');
      expect(intent.edition, const EditionToday());
    });

    test('payload null → défaut EditionToday / /flux-continu', () {
      final intent = NotificationIntent.parseFromLocalPayload(null, now: now);
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });

    test('payload hors format `route:` → défaut', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'garbage',
        now: now,
      );
      expect(intent.edition, const EditionToday());
      expect(intent.navigationPath, '/flux-continu');
    });

    test(
        'ancien payload `route:/digest?serein=1` (notif déjà planifiée) → '
        'aujourd\'hui, section nulle (pas de régression)', () {
      final intent = NotificationIntent.parseFromLocalPayload(
        'route:/digest?serein=1',
        now: now,
      );
      expect(intent.edition, const EditionToday());
      expect(intent.section, isNull);
      expect(intent.navigationPath, '/flux-continu');
    });
  });

  group('encodeLocalPayload — équivalence Android (local) / iOS (FCM)', () {
    // La propriété qui compte : un même push serveur doit produire la MÊME
    // intention, qu'il soit rendu localement (Android data-only → pipeline
    // local) ou remis par FCM (iOS). C'est ce que l'encodeur garantit.
    for (final data in <Map<String, dynamic>>[
      {'route': '/digest', 'target_date': '2026-08-07'},
      {'route': '/digest', 'section': 'bonnes'},
      {'route': '/digest', 'target_date': '2026-08-07', 'section': 'bonnes'},
      {'route': '/digest'},
      {'route': '/digest', 'kind': 'daily_digest', 'intro': 'coucou'},
    ]) {
      test('round-trip $data', () {
        final payload = NotificationIntent.encodeLocalPayload(
          data['route'] as String,
          data,
        );
        expect(
          NotificationIntent.parseFromLocalPayload(payload, now: now),
          NotificationIntent.parseFromFcmData(data, now: now),
        );
      });
    }

    test('aucune clé de routing → payload nu, sans query parasite', () {
      expect(
        NotificationIntent.encodeLocalPayload('/digest', const {}),
        'route:/digest',
      );
    });

    test('les clés hors routing (teasers, intro…) ne fuient pas dans l\'URL',
        () {
      final payload = NotificationIntent.encodeLocalPayload(
        '/digest',
        const {'intro': 'Voici', 'teasers': '["a"]', 'kind': 'daily_digest'},
      );
      expect(payload, 'route:/digest');
    });
  });

  group('targetsFeed — l\'état de feed ne vaut que pour le feed', () {
    test('digest → cible le feed', () {
      expect(
        NotificationIntent.parseFromFcmData({'route': '/digest'}, now: now)
            .targetsFeed,
        isTrue,
      );
    });

    test('alerte article → ne cible PAS le feed', () {
      // Garde structurelle : même si une alerte portait un `target_date`, elle
      // ne doit pas figer l'Essentiel sur une édition passée en sortant de
      // l'article (l'applier ne pose l'état que si `targetsFeed`).
      final intent = NotificationIntent.parseFromFcmData(
        {'route': '/flux-continu/content/abc', 'target_date': '2026-08-07'},
        now: now,
      );
      expect(intent.navigationPath, '/flux-continu/content/abc');
      expect(intent.targetsFeed, isFalse);
    });
  });
}
