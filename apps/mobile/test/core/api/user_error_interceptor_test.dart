import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/api/user_error_interceptor.dart';
import 'package:facteur/core/errors/user_facing_error_notifier.dart';

/// Notifier qui enregistre les appels [report] au lieu d'appliquer les cooldowns.
class _RecordingNotifier extends UserFacingErrorNotifier {
  _RecordingNotifier()
      : super.forTesting(
          prefs: SharedPreferences.getInstance,
          now: () => DateTime(2026, 7, 10),
        );

  final List<UserErrorSource> reported = [];

  @override
  Future<void> report({
    required UserErrorSource source,
    required String signature,
    String? route,
    String? detail,
  }) async {
    reported.add(source);
  }
}

/// Handler minimal qui note si [next] a bien été appelé (relais non bloquant).
class _FakeHandler implements ErrorInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(DioException err) => nextCalled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingNotifier notifier;
  late UserErrorInterceptor interceptor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifier = _RecordingNotifier();
    interceptor = UserErrorInterceptor(notifier: notifier);
  });

  DioException dioError({
    required DioExceptionType type,
    int? statusCode,
    bool userFacing = false,
  }) {
    final options = RequestOptions(
      path: '/api/x',
      extra: userFacing ? {'userFacing': true} : {},
    );
    return DioException(
      requestOptions: options,
      type: type,
      response: statusCode == null
          ? null
          : Response(requestOptions: options, statusCode: statusCode),
    );
  }

  test('500 + userFacing → report http5xx', () async {
    final handler = _FakeHandler();
    interceptor.onError(
      dioError(
        type: DioExceptionType.badResponse,
        statusCode: 500,
        userFacing: true,
      ),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.reported, [UserErrorSource.http5xx]);
    expect(handler.nextCalled, isTrue);
  });

  test('500 SANS userFacing → silence', () async {
    final handler = _FakeHandler();
    interceptor.onError(
      dioError(type: DioExceptionType.badResponse, statusCode: 500),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.reported, isEmpty);
    expect(handler.nextCalled, isTrue);
  });

  test('404 + userFacing → silence (pas un 5xx)', () async {
    final handler = _FakeHandler();
    interceptor.onError(
      dioError(
        type: DioExceptionType.badResponse,
        statusCode: 404,
        userFacing: true,
      ),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.reported, isEmpty);
  });

  test('timeout + userFacing → report timeout', () async {
    final handler = _FakeHandler();
    interceptor.onError(
      dioError(type: DioExceptionType.receiveTimeout, userFacing: true),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.reported, [UserErrorSource.timeout]);
  });

  test('timeout SANS userFacing → silence', () async {
    final handler = _FakeHandler();
    interceptor.onError(
      dioError(type: DioExceptionType.receiveTimeout),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.reported, isEmpty);
  });
}
