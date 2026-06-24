// PR « Sources dans la Tournée » — couverture des sections SOURCE de la Tournée
// composées par le FluxContinuNotifier : présence (kind=source), ordre
// (après les thèmes), dédup inter-sections, et état vide « toujours visible ».
import 'dart:io';

import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart'
    show kTourneeVisibleCap, kRichSectionMinItems;
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flux_continu_settle.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

class _StubEssentielRepository implements EssentielRepository {
  @override
  Future<List<EssentielArticle>?> fetch() async => const [];
}

class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);
  final UserInterestsState _initial;
  @override
  Future<UserInterestsState> build() async => _initial;
}

class _StubUserSourcesStateNotifier extends UserSourcesStateNotifier {
  _StubUserSourcesStateNotifier(this._initial);
  final UserSourcesState _initial;
  @override
  Future<UserSourcesState> build() async => _initial;
}

class _StubUserSourcesNotifier extends UserSourcesNotifier {
  _StubUserSourcesNotifier(this._initial);
  final List<Source> _initial;
  @override
  Future<List<Source>> build() async => _initial;
}

UserInterestsState _interestsState({List<FavoriteRef> favorites = const []}) {
  return UserInterestsState(
    themes: const [],
    customTopics: const [],
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 7,
  );
}

UserSourcesState _sourcesState({List<SourceFavoriteRef> favorites = const []}) {
  return UserSourcesState(
    sources: favorites
        .map((f) => SourceInterest(
              sourceId: f.sourceId,
              state: InterestState.favorite,
              priorityMultiplier: 1.0,
            ))
        .toList(),
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 7,
  );
}

FeedResponse _feedWithIds(List<String> ids, {String sourceId = 's'}) {
  return FeedResponse(
    items: ids
        .map((id) => Content(
              id: id,
              title: 'title-$id',
              url: 'https://x.test/$id',
              contentType: ContentType.article,
              publishedAt: DateTime(2026, 1, 1),
              source: Source(
                id: sourceId,
                name: 'S',
                type: SourceType.article,
              ),
            ))
        .toList(),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  setUpAll(() {
    // Le FluxContinuNotifier ouvre une box Hive (cache Tournée) au build.
    // `readToday` avale l'erreur, mais une box ouvrable garde le build propre.
    Hive.init(Directory.systemTemp.createTempSync('flux_sources_hive').path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
  });

  /// Un seul stub couvrant tous les named args que le provider peut passer
  /// (thème vs source), avec branchement sur l'invocation.
  void stubFeed({
    required Map<String, List<String>> themeIds,
    required Map<String, List<String>> sourceIds,
  }) {
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          sourceId: any(named: 'sourceId'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        )).thenAnswer((invocation) async {
      final src = invocation.namedArguments[#sourceId] as String?;
      final theme = invocation.namedArguments[#theme] as String?;
      if (src != null) {
        return _feedWithIds(sourceIds[src] ?? const [], sourceId: src);
      }
      if (theme != null) {
        return _feedWithIds(themeIds[theme] ?? const []);
      }
      return _feedWithIds(const []);
    });
  }

  Future<ProviderContainer> buildContainer({
    required UserInterestsState interests,
    required UserSourcesState sourcesState,
    required List<Source> catalog,
    List<String> tourneeOrder = const [],
  }) async {
    // Story 10.2 — une source ne s'affiche dans la Tournée que si sa clé
    // `source:<id>` est en mode « Essentiel » (dans `tournee_order_v1`).
    if (tourneeOrder.isNotEmpty) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': tourneeOrder,
      });
    }
    final container = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(_StubEssentielRepository()),
        userInterestsProvider
            .overrideWith(() => _StubUserInterestsNotifier(interests)),
        userSourcesStateProvider
            .overrideWith(() => _StubUserSourcesStateNotifier(sourcesState)),
        userSourcesProvider
            .overrideWith(() => _StubUserSourcesNotifier(catalog)),
        // Évite la chaîne authStateProvider → Supabase.instance (non initialisé
        // en test). Notifier réel mais sans le `ref.watch(authStateProvider)`.
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
        // Le cap de fit lit displayModeSpecProvider (box Hive 'settings' non
        // ouverte en test) ⇒ court-circuit.
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
    // Pré-résout les providers de sources : le FluxContinuNotifier les lit en
    // `ref.read(...).valueOrNull` (synchrone) pendant son build.
    await container.read(userSourcesStateProvider.future);
    await container.read(userSourcesProvider.future);
    await container.read(userInterestsProvider.future);
    return container;
  }

  Source _source(String id, {String? theme, String? logoUrl}) => Source(
        id: id,
        name: 'Source $id',
        type: SourceType.article,
        theme: theme,
        logoUrl: logoUrl,
      );

  List<FeedThemeSection> feedSections(ProviderContainer container) {
    final state = container.read(fluxContinuProvider).requireValue;
    return state.sections.whereType<FeedThemeSection>().toList();
  }

  test(
      'une source favorite produit une section kind=source ordonnée après les '
      'thèmes, avec nom + logo', () async {
    stubFeed(
      themeIds: {
        'tech': ['t1', 't2']
      },
      sourceIds: {
        'src1': ['a1', 'a2', 'a3']
      },
    );
    final container = await buildContainer(
      interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [
        _source('src1', theme: 'society', logoUrl: 'https://logo.test/x.png'),
      ],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = feedSections(container);

    final themeIdx = sections.indexWhere((s) => s.kind == SectionKind.theme);
    final sourceIdx = sections.indexWhere((s) => s.kind == SectionKind.source);
    expect(themeIdx, isNonNegative, reason: 'section thème attendue');
    expect(sourceIdx, isNonNegative, reason: 'section source attendue');
    expect(sourceIdx, greaterThan(themeIdx),
        reason: 'la source doit être composée après les thèmes');

    final src = sections[sourceIdx];
    expect(src.sourceId, 'src1');
    expect(src.label, 'Source src1');
    expect(src.sourceLogoUrl, 'https://logo.test/x.png');
    expect(src.items.map((c) => c.id), ['a1', 'a2', 'a3']);
  });

  test(
      'dédup inter-sections : un article partagé thème(au-dessus)/source '
      'n\'apparaît que dans le thème', () async {
    stubFeed(
      themeIds: {
        'tech': ['shared', 't2']
      },
      // src1 garde 2 survivants uniques (a2/a3) après dédup ⇒ section **riche**,
      // donc pas de réinjection (backfill) qui repiocherait l'article partagé :
      // on teste ici la seule règle de dédup (le thème au-dessus gagne).
      sourceIds: {
        'src1': ['shared', 'a2', 'a3']
      },
    );
    final container = await buildContainer(
      interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [_source('src1', theme: 'society')],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = feedSections(container);

    final theme = sections.firstWhere((s) => s.kind == SectionKind.theme);
    final source = sections.firstWhere((s) => s.kind == SectionKind.source);
    expect(theme.items.map((c) => c.id), contains('shared'));
    expect(source.items.map((c) => c.id), isNot(contains('shared')),
        reason: 'le thème au-dessus gagne l\'article partagé');
    expect(source.items.map((c) => c.id), ['a2', 'a3']);
  });

  test(
      'source sans article frais : section TOUJOURS visible (items vides), '
      'jamais masquée', () async {
    stubFeed(
      themeIds: const {},
      sourceIds: {'src1': const []},
    );
    final container = await buildContainer(
      interests: _interestsState(),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [_source('src1', theme: 'society')],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = feedSections(container);

    final source = sections.where((s) => s.kind == SectionKind.source).toList();
    expect(source, hasLength(1),
        reason: 'la section source reste rendue même vide (parité veille)');
    expect(source.first.items, isEmpty);
    expect(source.first.sourceId, 'src1');
  });

  test(
      'plusieurs sources favorites respectent l\'ordre par position et le '
      'cap (parité thèmes = 10)', () async {
    stubFeed(
      themeIds: const {},
      sourceIds: {
        'a': ['a1', 'a2'],
        'b': ['b1', 'b2'],
        'c': ['c1', 'c2'],
        'd': ['d1', 'd2'],
        'e': ['e1', 'e2'],
        'f': ['f1', 'f2'],
        'g': ['g1', 'g2'],
        'h': ['h1', 'h2'],
        'i': ['i1', 'i2'],
        'j': ['j1', 'j2'],
        'k': ['k1', 'k2'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(),
      sourcesState: _sourcesState(favorites: [
        SourceFavoriteRef(sourceId: 'c', position: 2),
        SourceFavoriteRef(sourceId: 'a', position: 0),
        SourceFavoriteRef(sourceId: 'b', position: 1),
        SourceFavoriteRef(sourceId: 'd', position: 3),
        SourceFavoriteRef(sourceId: 'f', position: 5),
        SourceFavoriteRef(sourceId: 'e', position: 4),
        SourceFavoriteRef(sourceId: 'h', position: 7),
        SourceFavoriteRef(sourceId: 'g', position: 6),
        SourceFavoriteRef(sourceId: 'j', position: 9),
        SourceFavoriteRef(sourceId: 'i', position: 8),
        SourceFavoriteRef(sourceId: 'k', position: 10),
      ]),
      catalog: [
        _source('a'),
        _source('b'),
        _source('c'),
        _source('d'),
        _source('e'),
        _source('f'),
        _source('g'),
        _source('h'),
        _source('i'),
        _source('j'),
        _source('k'),
      ],
      tourneeOrder: const [
        'source:a',
        'source:b',
        'source:c',
        'source:d',
        'source:e',
        'source:f',
        'source:g',
        'source:h',
        'source:i',
        'source:j',
        'source:k',
      ],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sources = feedSections(container)
        .where((s) => s.kind == SectionKind.source)
        .map((s) => s.sourceId)
        .toList();

    // Triées par position (a..k) puis capées à 10 → a,b,c,d,e,f,g,h,i,j.
    expect(sources, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']);
  });

  // ── Cohérence Tournée : dépriorisation / enrichissement des maigres ────────
  group('cohérence Tournée (maigre/riche)', () {
    test(
        'classification : un favori à 1 survivant ∈ thinFavoriteKeys ; '
        'à ≥2 absent', () async {
      stubFeed(
        themeIds: {
          'tech': ['t1', 't2'] // riche (2)
        },
        sourceIds: {
          'src1': ['b1'] // maigre (1)
        },
      );
      final container = await buildContainer(
        interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
        sourcesState: _sourcesState(
          favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
        ),
        catalog: [_source('src1', theme: 'society')],
        tourneeOrder: const ['theme:tech', 'source:src1'],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      expect(state.thinFavoriteKeys, contains('source:src1'));
      expect(state.thinFavoriteKeys, isNot(contains('theme:tech')));

      // La section riche n'est jamais marquée underfilled.
      final theme = feedSections(container)
          .firstWhere((s) => s.kind == SectionKind.theme);
      expect(theme.underfilled, isFalse);
    });

    test(
        'dépriorisation : 5 riches + 1 maigre → le maigre passe après les '
        'riches (gate ≥5)', () async {
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2'],
          'science': ['sc1', 'sc2'],
          'culture': ['cu1'], // maigre
          'economy': ['ec1', 'ec2'],
          'politics': ['po1', 'po2'],
          'environment': ['en1', 'en2'],
        },
        sourceIds: const {},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'environment'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      // 5 riches d'abord (ordre relatif préservé), le maigre 'culture' en fin.
      expect(order, [
        'tech',
        'science',
        'economy',
        'politics',
        'environment',
        'culture',
      ]);
    });

    test('gate ≥5 : 4 riches + 1 maigre → ordre inchangé', () async {
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2'],
          'science': ['sc1', 'sc2'],
          'culture': ['cu1'], // maigre, en 3ᵉ position
          'economy': ['ec1', 'ec2'],
          'politics': ['po1', 'po2'],
        },
        sourceIds: const {},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      // 4 riches < seuil ⇒ pas de dépriorisation : 'culture' reste en place.
      expect(order, ['tech', 'science', 'culture', 'economy', 'politics']);
    });

    test(
        'cap : >10 favoris dont un maigre → le maigre est coupé des sections '
        'mais présent dans thinFavoriteKeys', () async {
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2'],
          'science': ['sc1', 'sc2'],
          'economy': ['ec1', 'ec2'],
          'politics': ['po1', 'po2'],
          'environment': ['en1', 'en2'],
          'culture': ['cu1'], // maigre → dépriorisé en fin → coupé par le cap
        },
        sourceIds: {
          'a': ['a1', 'a2'],
          'b': ['b1', 'b2'],
          'c': ['c1', 'c2'],
          'd': ['d1', 'd2'],
          'e': ['e1', 'e2'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'environment'),
            ThemeFavoriteRef(slug: 'culture'),
          ],
        ),
        sourcesState: _sourcesState(
          favorites: const [
            SourceFavoriteRef(sourceId: 'a', position: 0),
            SourceFavoriteRef(sourceId: 'b', position: 1),
            SourceFavoriteRef(sourceId: 'c', position: 2),
            SourceFavoriteRef(sourceId: 'd', position: 3),
            SourceFavoriteRef(sourceId: 'e', position: 4),
          ],
        ),
        catalog: [
          _source('a'),
          _source('b'),
          _source('c'),
          _source('d'),
          _source('e'),
        ],
        tourneeOrder: const [
          'source:a',
          'source:b',
          'source:c',
          'source:d',
          'source:e',
        ],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final slugs = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      // 11 favoris (5 sources + 6 thèmes), cap 10 ⇒ le maigre 'culture'
      // (dépriorisé en dernier) est coupé, mais reste signalé pour la modal.
      expect(state.sections.length, kTourneeVisibleCap);
      expect(slugs, isNot(contains('culture')));
      expect(state.thinFavoriteKeys, contains('theme:culture'));
    });

    test(
        'backfill : une source maigre affichée est réinjectée jusqu\'à 2 items '
        '+ underfilled (doublons inter-sections tolérés)', () async {
      stubFeed(
        themeIds: {
          'tech': ['s1', 's2'] // riche, gagne s1/s2
        },
        sourceIds: {
          'src1': ['s1', 's2'] // tout partagé → 0 survivant → maigre
        },
      );
      final container = await buildContainer(
        interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
        sourcesState: _sourcesState(
          favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
        ),
        catalog: [_source('src1', theme: 'society')],
        tourneeOrder: const ['theme:tech', 'source:src1'],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final source = feedSections(container)
          .firstWhere((s) => s.kind == SectionKind.source);
      // Réinjection bornée à kRichSectionMinItems (2), depuis les retirés.
      expect(source.items.length, kRichSectionMinItems);
      expect(source.items.map((c) => c.id), containsAll(['s1', 's2']));
      expect(source.underfilled, isTrue);
      expect(state.thinFavoriteKeys, contains('source:src1'));
    });
  });
}
