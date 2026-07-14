import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/edition_essentiel_provider.dart';
import 'package:facteur/features/flux_continu/providers/edition_read_status_provider.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Fakes / stubs ─────────────────────────────────────────────────────────────

class _MockDigestRepository extends Mock implements DigestRepository {}

/// Fake essentiel repo : renvoie des héros par jour (clé `YYYY-MM-DD`, ou
/// `today` pour la date courante). `null` ⇒ 202/erreur côté provider.
class _FakeEssentielRepository implements EssentielRepository {
  _FakeEssentielRepository(this.byDay);
  final Map<String, List<EssentielArticle>?> byDay;

  @override
  Future<List<EssentielArticle>?> fetch({bool? serein, DateTime? date}) async {
    final key = date == null ? 'today' : editionDayKey(date);
    return byDay[key];
  }
}

/// Court-circuite le vrai `FluxContinuNotifier` (build lourd) : aujourd'hui vide.
class _StubFluxNotifier extends FluxContinuNotifier {
  @override
  Future<FluxContinuState> build() async =>
      const FluxContinuState(isLoading: false, sections: []);
}

// ── Helpers de données ────────────────────────────────────────────────────────

EssentielArticle _hero(
  String id, {
  int rank = 1,
  bool isRead = false,
  String? theme,
  DateTime? publishedAt,
}) =>
    EssentielArticle(
      contentId: id,
      title: 't$id',
      url: 'https://x/$id',
      publishedAt: publishedAt ?? DateTime(2026, 1, 1),
      sourceName: 'S',
      sourceLetter: 'S',
      sectionLabel: 'Tech',
      rank: rank,
      isRead: isRead,
      theme: theme,
    );

DigestTopic _topic(
  String id, {
  double score = 1,
  int rank = 1,
  String? theme,
  String? leadContentId,
}) =>
    DigestTopic(
      topicId: id,
      label: 'L$id',
      topicScore: score,
      rank: rank,
      theme: theme,
      articles: [
        DigestItem(contentId: leadContentId ?? '$id-a', title: 'a$id'),
      ],
    );

DigestResponse _digest({
  required List<DigestTopic> topics,
  bool stale = false,
  QuoteResponse? quote,
}) =>
    DigestResponse(
      digestId: 'd',
      userId: 'u',
      targetDate: DateTime(2026, 1, 1),
      generatedAt: DateTime(2026, 1, 1),
      topics: topics,
      isStaleFallback: stale,
      quote: quote,
    );

DualDigestResponse _dual(DigestResponse normal) =>
    DualDigestResponse(normal: normal, serein: null, sereinEnabled: false);

/// Variante avec digest **serein** (source des « Bonnes Nouvelles »).
DualDigestResponse _dualS(DigestResponse normal, {DigestResponse? serein}) =>
    DualDigestResponse(
      normal: normal,
      serein: serein,
      sereinEnabled: serein != null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    required Map<String, List<EssentielArticle>?> heroByDay,
    required Map<String, DualDigestResponse?> dualByDay,
    // Statut lu/non-lu injecté : par défaut indisponible (weekMissedDays = 0).
    // Override `editionReadStatusProvider` directement → ne construit jamais
    // `streakActivityProvider` (évite le poison MissingPluginException prefs).
    EditionReadStatus readStatus = const EditionReadStatus.unavailable(),
  }) {
    final digestRepo = _MockDigestRepository();
    when(() => digestRepo.fetchBothDigests(date: any(named: 'date')))
        .thenAnswer((inv) async {
      final d = inv.namedArguments[const Symbol('date')] as DateTime?;
      final key = d == null ? 'today' : editionDayKey(d);
      final v = dualByDay[key];
      if (v == null) throw DigestPreparingException();
      return v;
    });
    return ProviderContainer(
      overrides: [
        essentielRepositoryProvider
            .overrideWithValue(_FakeEssentielRepository(heroByDay)),
        digestRepositoryProvider.overrideWithValue(digestRepo),
        authStateProvider
            .overrideWith((ref) => AuthStateNotifier.test(const AuthState())),
        fluxContinuProvider.overrideWith(_StubFluxNotifier.new),
        editionReadStatusProvider.overrideWithValue(readStatus),
      ],
    );
  }

  group('jour passé', () {
    test('digest propre (non stale) → héros + topics mappés, non stale',
        () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1'), _hero('h2', rank: 2)],
        },
        dualByDay: {
          key: _dual(_digest(topics: [_topic('t1')])),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isFalse);
      expect(state.isWeek, isFalse);
      expect(state.heroArticles.map((a) => a.contentId), ['h1', 'h2']);
      expect(state.topics.map((t) => t.topicId), ['t1']);
    });

    test('is_stale_fallback → isStaleOrEmpty, héros & topics vides', () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {
          key: _dual(_digest(topics: [_topic('t1')], stale: true)),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isTrue);
      expect(state.heroArticles, isEmpty);
      expect(state.topics, isEmpty);
    });

    test('202 / digest absent / héros null → isStaleOrEmpty', () async {
      final date = DateTime(2026, 6, 20);
      final container = makeContainer(heroByDay: {}, dualByDay: {});
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isTrue);
    });

    test('héros présent mais digest 202 → isStaleOrEmpty (pas de demi-lettre)',
        () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {}, // digest throws preparing → digest null
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isTrue);
    });

    test(
        'Bonnes Nouvelles = topics du digest serein (indépendant du toggle off)',
        () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {
          key: _dualS(
            _digest(topics: [_topic('t1')]),
            serein: _digest(topics: [_topic('bn1'), _topic('bn2')]),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      // Actus = digest normal ; Bonnes Nouvelles = digest serein, tous deux
      // captés même toggle serein éteint.
      expect(state.topics.map((t) => t.topicId), ['t1']);
      expect(state.bonnesTopics.map((t) => t.topicId), ['bn1', 'bn2']);
    });

    test('serein absent → bonnesTopics vide', () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {
          key: _dual(_digest(topics: [_topic('t1')])), // serein null
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.topics.map((t) => t.topicId), ['t1']);
      expect(state.bonnesTopics, isEmpty);
    });

    test(
        'normal stale mais serein valide → jour stale, mais bonnes captées '
        '(Change 4 : alimentent l\'agrégat hebdo ; le rendu single-day reste '
        'gardé par isStaleOrEmpty)', () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {
          // Le digest **pické** (normal, toggle off) est stale ⇒ jour stale
          // pour le héros/Actus… mais le serein est valide.
          key: _dualS(
            _digest(topics: [_topic('t1')], stale: true),
            serein: _digest(topics: [_topic('bn1')]),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      // Le jour reste « sans lettre » pour le rendu single-day (héros + Actus
      // absents ⇒ empty-state affiché).
      expect(state.isStaleOrEmpty, isTrue);
      expect(state.heroArticles, isEmpty);
      expect(state.topics, isEmpty);
      // Change 4 — les bonnes sereines sont désormais captées même quand le
      // digest normal est périmé : c'est ce qui permet à un tel jour de
      // contribuer ses bonnes à « Cette semaine » (avant, elles étaient
      // perdues).
      expect(state.bonnesTopics.map((t) => t.topicId), ['bn1']);
    });

    test('serein aussi stale (fallback cloné) → bonnesTopics vide', () async {
      final date = DateTime(2026, 6, 20);
      final key = editionDayKey(date);
      final container = makeContainer(
        heroByDay: {
          key: [_hero('h1')],
        },
        dualByDay: {
          // Digest normal valide mais serein = fallback cloné ⇒ ne jamais
          // présenter les bonnes d'un autre jour.
          key: _dualS(
            _digest(topics: [_topic('t1')]),
            serein: _digest(topics: [_topic('bn1')], stale: true),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          EditionPastDay(date);

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isFalse);
      expect(state.topics.map((t) => t.topicId), ['t1']);
      expect(state.bonnesTopics, isEmpty);
    });
  });

  // « Cette semaine » se rend via le **même chemin single-day** : sa valeur
  // « ce que tu as manqué » vit dans la sélection de contenu (héros = non-lus
  // de la semaine, triés par importance). On asserte donc `heroArticles` +
  // `topics` + `isWeek`, comme un jour passé.
  group('Cette semaine', () {
    test(
        'héros = non-lus d\'abord, dédup contentId, tri rank asc, cap 5 ; '
        'jours manquants ignorés', () async {
      final today = editionTodayDate();
      DateTime past(int i) => DateTime(today.year, today.month, today.day - i);
      final k1 = editionDayKey(past(1));
      final k2 = editionDayKey(past(2));
      final k3 = editionDayKey(past(3));
      // past(4) absent → jour manquant ignoré (pas de contribution).
      final container = makeContainer(
        heroByDay: {
          k1: [
            _hero('b', rank: 1),
            _hero('x', rank: 6),
            _hero('e', rank: 4, isRead: true),
          ],
          k2: [_hero('c', rank: 2), _hero('d', rank: 3), _hero('b', rank: 9)],
          k3: [_hero('f', rank: 5), _hero('z', rank: 8)],
        },
        dualByDay: {
          k1: _dual(_digest(topics: [_topic('t1', score: 1)])),
          k2: _dual(_digest(topics: [_topic('t2', score: 5)])),
          k3: _dual(_digest(topics: [_topic('t3', score: 3)])),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isWeek, isTrue);
      expect(state.isStaleOrEmpty, isFalse);
      // 'e' (lu) exclu ; 'b' dédupliqué (1ʳᵉ occurrence rank 1 gardée) ; tri
      // rank asc ; cap 5 (b1,c2,d3,f5,x6 — z8 hors cap).
      expect(state.heroArticles.map((a) => a.contentId), ['b', 'c', 'd', 'f', 'x']);
      // « Actus de la semaine » = Σ topics normaux, tri topicScore desc.
      expect(state.topics.map((t) => t.topicId), ['t2', 't3', 't1']);
    });

    test('tout lu → fallback read-agnostic (mêmes tri/cap)', () async {
      final today = editionTodayDate();
      final k1 = editionDayKey(DateTime(today.year, today.month, today.day - 1));
      final container = makeContainer(
        heroByDay: {
          k1: [
            _hero('a', rank: 2, isRead: true),
            _hero('b', rank: 1, isRead: true),
          ],
        },
        dualByDay: {
          k1: _dual(_digest(topics: [_topic('t1')])),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      // Aucun non-lu → héros reconstruit sur tous les articles, tri rank asc.
      expect(state.heroArticles.map((a) => a.contentId), ['b', 'a']);
      expect(state.isStaleOrEmpty, isFalse);
    });

    test('héros d\'un jour plafonnés à kEditionWeekMaxArticlesPerDay avant dédup',
        () async {
      final today = editionTodayDate();
      final k1 = editionDayKey(DateTime(today.year, today.month, today.day - 1));
      final container = makeContainer(
        heroByDay: {
          // 5 héros un même jour → seuls les 3 premiers (par rank servi)
          // entrent dans le pool candidat.
          k1: [
            _hero('a', rank: 1),
            _hero('b', rank: 2),
            _hero('c', rank: 3),
            _hero('d', rank: 4),
            _hero('e', rank: 5),
          ],
        },
        dualByDay: {
          k1: _dual(_digest(topics: [_topic('t1')])),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.heroArticles, hasLength(kEditionWeekMaxArticlesPerDay));
      expect(state.heroArticles.map((a) => a.contentId), ['a', 'b', 'c']);
    });

    test('tout vide → isStaleOrEmpty ; héros et Actus vides', () async {
      final container = makeContainer(heroByDay: {}, dualByDay: {});
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isTrue);
      expect(state.heroArticles, isEmpty);
      expect(state.topics, isEmpty);
    });

    test(
        'Bonnes Nouvelles hebdo = Σ topics serein, dédup topicId, tri score desc',
        () async {
      final today = editionTodayDate();
      DateTime past(int i) => DateTime(today.year, today.month, today.day - i);
      final k1 = editionDayKey(past(1));
      final k2 = editionDayKey(past(2));
      final container = makeContainer(
        heroByDay: {
          k1: [_hero('a', rank: 1)],
          k2: [_hero('b', rank: 2)],
        },
        dualByDay: {
          k1: _dualS(
            _digest(topics: [_topic('t1')]),
            serein: _digest(topics: [_topic('bn1', score: 1)]),
          ),
          k2: _dualS(
            _digest(topics: [_topic('t2')]),
            serein: _digest(
              topics: [_topic('bn2', score: 5), _topic('bn1', score: 1)],
            ),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      // bn1 dédupliqué (1ʳᵉ occurrence gardée) ; tri topicScore desc : bn2, bn1.
      expect(state.bonnesTopics.map((t) => t.topicId), ['bn2', 'bn1']);
    });

    test(
        'Change 4 — un jour au normal périmé mais serein valide contribue ses '
        'bonnes à l\'agrégat hebdo (bug « seulement hier »)', () async {
      final today = editionTodayDate();
      DateTime past(int i) => DateTime(today.year, today.month, today.day - i);
      final k1 = editionDayKey(past(1)); // digest normal frais
      final k2 = editionDayKey(past(2)); // normal périmé, serein valide
      final container = makeContainer(
        heroByDay: {
          k1: [_hero('a', rank: 1)],
          k2: [_hero('b', rank: 2)],
        },
        dualByDay: {
          k1: _dualS(
            _digest(topics: [_topic('t1')]),
            serein: _digest(topics: [_topic('bnFresh', score: 1)]),
          ),
          k2: _dualS(
            _digest(topics: [_topic('t2')], stale: true),
            serein: _digest(topics: [_topic('bnStaleDay', score: 5)]),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      // k2 (normal périmé) ne contribue PAS au héros ni aux Actus…
      expect(state.heroArticles.map((a) => a.contentId), ['a']);
      expect(state.topics.map((t) => t.topicId), ['t1']);
      // … mais SES bonnes sereines rejoignent bien l'agrégat hebdo. Avant le
      // correctif, le `continue` sur le jour stale les jetait → « seulement
      // hier ». Tri score desc : bnStaleDay(5), bnFresh(1).
      expect(
        state.bonnesTopics.map((t) => t.topicId),
        ['bnStaleDay', 'bnFresh'],
      );
    });

    test(
        'Change 3 — agrégats « Tout lire » (topicsAll/bonnesAll) plus larges '
        'que l\'aperçu inline (cap 6)', () async {
      final today = editionTodayDate();
      final k1 = editionDayKey(DateTime(today.year, today.month, today.day - 1));
      // 8 topics normaux + 8 bonnes sereines distincts (score décroissant pour
      // un tri déterministe) → l'inline plafonne à 6, « Tout lire » en garde 8.
      final normalTopics = [
        for (var i = 0; i < 8; i++) _topic('n$i', score: (8 - i).toDouble()),
      ];
      final sereinTopics = [
        for (var i = 0; i < 8; i++) _topic('s$i', score: (8 - i).toDouble()),
      ];
      final container = makeContainer(
        heroByDay: {
          k1: [_hero('a', rank: 1)],
        },
        dualByDay: {
          k1: _dualS(
            _digest(topics: normalTopics),
            serein: _digest(topics: sereinTopics),
          ),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      // Aperçu inline plafonné (kEditionWeekMaxTopics = 6).
      expect(state.topics, hasLength(kEditionWeekMaxTopics));
      expect(state.bonnesTopics, hasLength(kEditionWeekMaxTopics));
      // Agrégat « Tout lire » : les 8 (sous le cap large 20).
      expect(state.topicsAll, hasLength(8));
      expect(state.bonnesAll, hasLength(8));
      // Superset ordonné : l'inline est le préfixe de l'agrégat complet.
      expect(
        state.topicsAll.take(kEditionWeekMaxTopics).map((t) => t.topicId),
        state.topics.map((t) => t.topicId),
      );
    });
  });
}
