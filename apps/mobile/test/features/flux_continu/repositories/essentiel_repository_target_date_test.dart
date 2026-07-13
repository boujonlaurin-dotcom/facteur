import 'package:dio/dio.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late EssentielRepository repo;
  Map<String, dynamic>? captured;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    when(() => apiClient.dio).thenReturn(dio);
    repo = EssentielRepository(apiClient);
    captured = null;
    when(
      () => dio.get<dynamic>(
        'essentiel',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((invocation) async {
      captured = invocation.namedArguments[const Symbol('queryParameters')]
          as Map<String, dynamic>?;
      return Response<dynamic>(
        requestOptions: RequestOptions(path: 'essentiel'),
        statusCode: 200,
        data: const {'articles': <dynamic>[]},
      );
    });
  });

  test('fetch(date:) ajoute target_date au format YYYY-MM-DD', () async {
    await repo.fetch(date: DateTime(2026, 6, 20));
    expect(captured?['target_date'], '2026-06-20');
  });

  test('fetch(date:) zéro-pad mois et jour', () async {
    await repo.fetch(date: DateTime(2026, 1, 5));
    expect(captured?['target_date'], '2026-01-05');
  });

  test('fetch() sans date n\'envoie pas target_date', () async {
    await repo.fetch();
    expect(captured?.containsKey('target_date') ?? false, isFalse);
  });

  test('fetch(serein:, date:) envoie les deux', () async {
    await repo.fetch(serein: true, date: DateTime(2026, 6, 20));
    expect(captured?['serein'], true);
    expect(captured?['target_date'], '2026-06-20');
  });
}
