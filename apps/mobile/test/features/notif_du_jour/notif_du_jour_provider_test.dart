import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/flux_continu/providers/geoloc_prompt_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:facteur/features/notif_du_jour/models/notif_du_jour_message.dart';
import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_dismissal_store.dart';
import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_provider.dart';
import 'package:facteur/features/notifications/providers/notification_renudge_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:facteur/features/well_informed/providers/well_informed_prompt_provider.dart';

class _FakeUserSources extends UserSourcesNotifier {
  _FakeUserSources(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

class _FakeVeille extends VeilleActiveConfigNotifier {
  _FakeVeille(this._cfg);
  final VeilleConfigDto? _cfg;

  @override
  Future<VeilleConfigDto?> build() async => _cfg;
}

VeilleConfigDto _veilleConfig() => VeilleConfigDto(
      id: 'v1',
      userId: 'u1',
      themeId: 't1',
      themeLabel: 'Climat',
      status: 'active',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      topics: const [],
      sources: const [],
      keywords: const [],
    );

Source _trusted(String id) =>
    Source(id: id, name: id, type: SourceType.article, isTrusted: true);

/// Container de base : tout inéligible sauf ce que le test surcharge.
ProviderContainer _container({
  bool renudge = false,
  bool wellInformed = false,
  bool geoloc = false,
  List<Source> sources = const [],
  List<Source> eligibleSubs = const [],
  VeilleConfigDto? veille,
  bool veilleLoaded = true,
  bool sereinEnabled = true,
  bool sereinLoading = false,
  List<Override> extra = const [],
}) {
  return ProviderContainer(
    overrides: [
      notificationRenudgeShouldShowProvider.overrideWithValue(renudge),
      wellInformedShouldShowProvider.overrideWith((ref) async => wellInformed),
      geolocPromptShouldShowProvider.overrideWith((ref) async => geoloc),
      userSourcesProvider.overrideWith(() => _FakeUserSources(sources)),
      eligibleSubscriptionSourcesProvider.overrideWithValue(eligibleSubs),
      if (veilleLoaded)
        veilleActiveConfigProvider.overrideWith(() => _FakeVeille(veille)),
      sereinToggleProvider.overrideWith((ref) {
        final n = SereinToggleNotifier(ref);
        if (!sereinLoading) n.initFromApi(sereinEnabled);
        return n;
      }),
      ...extra,
    ],
  );
}

/// Résout les providers async watchés par la file puis lit la file.
Future<List<String>> _queue(ProviderContainer container) async {
  final sub = container.listen(notifDuJourQueueProvider, (_, __) {});
  // Laisse les FutureProvider/AsyncNotifier émettre leur valeur.
  await container.read(userSourcesProvider.future);
  await Future<void>.delayed(Duration.zero);
  final queue = container.read(notifDuJourQueueProvider);
  sub.close();
  return queue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // tourneeOrderPrefsProvider réel : prefs vides = non customisée.
    SharedPreferences.setMockInitialValues({});
  });

  test('fallback : file jamais vide, recommencer toujours présent', () async {
    final container = _container(
      veille: _veilleConfig(),
    );
    SharedPreferences.setMockInitialValues({'tournee_customized_v1': true});
    final queue = await _queue(container);
    expect(queue, contains(NotifDuJourIds.recommencer));
    expect(queue, isNotEmpty);
  });

  test('serein éligible seulement si OFF et synchronisé', () async {
    final off = _container(sereinEnabled: false);
    expect(await _queue(off), contains(NotifDuJourIds.serein));

    final on = _container(sereinEnabled: true);
    expect(await _queue(on), isNot(contains(NotifDuJourIds.serein)));

    final loading = _container(sereinLoading: true);
    expect(await _queue(loading), isNot(contains(NotifDuJourIds.serein)));
  });

  test('source éligible si < 3 sources de confiance, relevance ↑ si 0',
      () async {
    final none = _container();
    expect(await _queue(none), contains(NotifDuJourIds.source));

    final two = _container(sources: [_trusted('a'), _trusted('b')]);
    expect(await _queue(two), contains(NotifDuJourIds.source));

    final three = _container(
      sources: [_trusted('a'), _trusted('b'), _trusted('c')],
    );
    expect(await _queue(three), isNot(contains(NotifDuJourIds.source)));

    expect(sourceRelevance(0), 1.0);
    expect(sourceRelevance(2), closeTo(0.33, 0.01));
  });

  test('premium éligible si sources payantes non liées', () async {
    final with2 = _container(eligibleSubs: [_trusted('lemonde')]);
    expect(await _queue(with2), contains(NotifDuJourIds.premium));

    final without = _container();
    expect(await _queue(without), isNot(contains(NotifDuJourIds.premium)));

    expect(premiumRelevance(3), 1.0);
    expect(premiumRelevance(1), closeTo(0.33, 0.01));
  });

  test('veille éligible si aucune config serveur ; non résolue = inéligible',
      () async {
    final noConfig = _container(veille: null);
    expect(await _queue(noConfig), contains(NotifDuJourIds.veille));

    final configured = _container(veille: _veilleConfig());
    expect(await _queue(configured), isNot(contains(NotifDuJourIds.veille)));
  });

  test('tournee éligible si non customisée', () async {
    final fresh = _container();
    expect(await _queue(fresh), contains(NotifDuJourIds.tournee));
  });

  test('nudges absorbés pilotés par leurs shouldShow, priorité haute',
      () async {
    final container = _container(
      renudge: true,
      wellInformed: true,
      geoloc: true,
      sereinEnabled: false,
    );
    final queue = await _queue(container);
    expect(
      queue,
      containsAll([
        NotifDuJourIds.notifRenudge,
        NotifDuJourIds.wellInformed,
        NotifDuJourIds.geoloc,
      ]),
    );
    // relevance 0.9/0.85 : devant serein (0.55) même avec jitter max (0.15).
    expect(
      queue.indexOf(NotifDuJourIds.notifRenudge),
      lessThan(queue.indexOf(NotifDuJourIds.serein)),
    );

    final off = _container();
    final quiet = await _queue(off);
    expect(quiet, isNot(contains(NotifDuJourIds.notifRenudge)));
    expect(quiet, isNot(contains(NotifDuJourIds.wellInformed)));
    expect(quiet, isNot(contains(NotifDuJourIds.geoloc)));
  });

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  test('id dismissé (< 30j) filtré de la file (cooldown)', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({NotifDuJourIds.serein: _today()}),
    });
    final container = _container(sereinEnabled: false);
    expect(await _queue(container), isNot(contains(NotifDuJourIds.serein)));
  });

  test('cooldown expiré (> 30j) → id de nouveau éligible', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey:
          jsonEncode({NotifDuJourIds.serein: '2020-01-01'}),
    });
    final container = _container(sereinEnabled: false);
    expect(await _queue(container), contains(NotifDuJourIds.serein));
  });

  test('serein remonte quand les autres messages profil sont en cooldown',
      () async {
    final today = _today();
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({
        NotifDuJourIds.source: today,
        NotifDuJourIds.tournee: today,
        NotifDuJourIds.veille: today,
      }),
    });
    // Profil : source < 3, tournée non customisée, veille absente, serein OFF.
    final container = _container(sereinEnabled: false, veille: null);
    final queue = await _queue(container);
    // Concurrents profil filtrés → serein passe devant le fallback recommencer.
    expect(queue, contains(NotifDuJourIds.serein));
    expect(queue, isNot(contains(NotifDuJourIds.source)));
    expect(
      queue.indexOf(NotifDuJourIds.serein),
      lessThan(queue.indexOf(NotifDuJourIds.recommencer)),
    );
  });

  test('catalogue : chaque id de la file a un message affichable', () async {
    final container = _container(
      renudge: true,
      wellInformed: true,
      geoloc: true,
      sereinEnabled: false,
      eligibleSubs: [_trusted('lemonde')],
      veille: null,
    );
    final queue = await _queue(container);
    for (final id in queue) {
      expect(buildNotifDuJourMessage(id), isNotNull, reason: id);
    }
    expect(buildNotifDuJourMessage('id_inconnu_v0'), isNull);
  });
}
