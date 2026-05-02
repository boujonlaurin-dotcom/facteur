import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/providers.dart';
import 'package:facteur/features/veille/providers/veille_themes_provider.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient api;
  late _MockDio dio;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    api = _MockApiClient();
    dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
  }

  Response<dynamic> okResponse(List<Map<String, Object?>> rows) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: 'users/top-themes'),
      statusCode: 200,
      data: rows,
    );
  }

  test('user themes come first, sorted as backend returns; completes with Facteur themes',
      () async {
    when(() => dio.get<dynamic>('users/top-themes')).thenAnswer(
      (_) async => okResponse([
        {'interest_slug': 'science', 'weight': 1.5, 'article_count': 12},
        {'interest_slug': 'tech', 'weight': 1.2, 'article_count': 5},
      ]),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final themes = await container.read(veilleThemesProvider.future);

    // First two are user themes in backend order.
    expect(themes[0].id, 'science');
    expect(themes[0].meta, '12 articles · 14 j');
    expect(themes[0].hot, isTrue);
    expect(themes[1].id, 'tech');
    expect(themes[1].meta, '5 articles · 14 j');
    expect(themes[1].hot, isTrue);

    // Then completed with remaining Facteur themes (no article_count → meta='Disponible',
    // hot=false because they're suggestions).
    expect(themes.length, kVeilleFacteurThemes.length); // 9 total
    final completionSlugs = themes.skip(2).map((t) => t.id).toSet();
    expect(completionSlugs, contains('society'));
    expect(completionSlugs, contains('politics'));
    expect(themes[2].meta, 'Disponible');
    expect(themes[2].hot, isFalse);
  });

  test('emoji is present and label uses the canonical FR name', () async {
    when(() => dio.get<dynamic>('users/top-themes')).thenAnswer(
      (_) async => okResponse([
        {'interest_slug': 'environment', 'article_count': 7},
      ]),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final themes = await container.read(veilleThemesProvider.future);

    expect(themes.first.id, 'environment');
    expect(themes.first.label, 'Environnement');
    expect(themes.first.emoji, '🌿');
  });

  test('falls back to Facteur themes when API throws', () async {
    when(() => dio.get<dynamic>('users/top-themes')).thenThrow(
      DioException(requestOptions: RequestOptions(path: 'users/top-themes')),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final themes = await container.read(veilleThemesProvider.future);

    expect(themes.length, kVeilleFacteurThemes.length);
    expect(themes.first.id, 'tech'); // canonical order
    expect(themes.first.meta, 'Disponible');
    expect(themes.first.hot, isFalse);
  });

  test('caps the rendered themes at 9 even with many user themes', () async {
    when(() => dio.get<dynamic>('users/top-themes')).thenAnswer(
      (_) async => okResponse([
        for (final t in kVeilleFacteurThemes)
          {'interest_slug': t.slug, 'article_count': 1},
      ]),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final themes = await container.read(veilleThemesProvider.future);

    expect(themes.length, kVeilleFacteurThemes.length);
  });

  test('article_count = 0 yields a softer meta', () async {
    when(() => dio.get<dynamic>('users/top-themes')).thenAnswer(
      (_) async => okResponse([
        {'interest_slug': 'sport', 'article_count': 0},
      ]),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final themes = await container.read(veilleThemesProvider.future);

    expect(themes.first.id, 'sport');
    expect(themes.first.meta, 'Peu d\'actualité · 14 j');
  });

  test('veilleThemeLabelForSlug exposes the canonical label', () {
    expect(veilleThemeLabelForSlug('tech'), 'Technologie');
    expect(veilleThemeLabelForSlug('international'), 'Géopolitique');
    expect(veilleThemeLabelForSlug('unknown'), 'Unknown');
  });
}
