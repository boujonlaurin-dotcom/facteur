import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/edition_essentiel_provider.dart';
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

EssentielArticle _hero(String id, {int rank = 1}) => EssentielArticle(
      contentId: id,
      title: 't$id',
      url: 'https://x/$id',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: 'S',
      sourceLetter: 'S',
      sectionLabel: 'Tech',
      rank: rank,
    );

DigestTopic _topic(String id, {double score = 1, int rank = 1}) => DigestTopic(
      topicId: id,
      label: 'L$id',
      topicScore: score,
      rank: rank,
      articles: [DigestItem(contentId: '$id-a', title: 'a$id')],
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    required Map<String, List<EssentielArticle>?> heroByDay,
    required Map<String, DualDigestResponse?> dualByDay,
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
  });

  group('Cette semaine', () {
    test('agrège, dédup contentId, re-tri rank, jours manquants ignorés',
        () async {
      final today = editionTodayDate();
      DateTime past(int i) => DateTime(today.year, today.month, today.day - i);
      final k1 = editionDayKey(past(1));
      final k2 = editionDayKey(past(2));
      // past(3) absent → jour manquant ignoré.
      final container = makeContainer(
        heroByDay: {
          k1: [_hero('a', rank: 3), _hero('b', rank: 1)],
          k2: [_hero('b', rank: 1), _hero('c', rank: 2)], // 'b' dupliqué
        },
        dualByDay: {
          k1: _dual(_digest(topics: [_topic('t1', score: 1)])),
          k2: _dual(_digest(
            topics: [_topic('t2', score: 5), _topic('t1', score: 1)],
          )), // t1 dupliqué
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isWeek, isTrue);
      expect(state.isStaleOrEmpty, isFalse);
      // dédup 'b' + re-tri rank (1 lead) : b(1), c(2), a(3).
      expect(state.heroArticles.map((a) => a.contentId), ['b', 'c', 'a']);
      // dédup t1 + tri topicScore desc : t2(5), t1(1).
      expect(state.topics.map((t) => t.topicId), ['t2', 't1']);
    });

    test('héros plafonnés à kEditionWeekMaxHero', () async {
      final today = editionTodayDate();
      final k1 = editionDayKey(DateTime(today.year, today.month, today.day - 1));
      final container = makeContainer(
        heroByDay: {
          k1: [for (var i = 1; i <= 7; i++) _hero('h$i', rank: i)],
        },
        dualByDay: {
          k1: _dual(_digest(topics: const [])),
        },
      );
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.heroArticles.length, kEditionWeekMaxHero);
      expect(state.heroArticles.first.contentId, 'h1'); // rank 1 en tête
    });

    test('tout vide → isStaleOrEmpty', () async {
      final container = makeContainer(heroByDay: {}, dualByDay: {});
      addTearDown(container.dispose);
      container.read(selectedEditionDateProvider.notifier).state =
          const EditionWeek();

      final state = await container.read(editionEssentielProvider.future);
      expect(state.isStaleOrEmpty, isTrue);
      expect(state.heroArticles, isEmpty);
      expect(state.topics, isEmpty);
    });
  });
}
