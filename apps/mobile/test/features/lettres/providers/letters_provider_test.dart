import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/providers/letters_provider.dart';
import 'package:facteur/features/lettres/providers/letters_repository_provider.dart';
import 'package:facteur/features/lettres/repositories/letters_repository.dart';

class MockLettersRepository extends Mock implements LettersRepository {}

class _AuthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _AuthNotifier()
      : super(const app_auth.AuthState(
          user: supabase.User(
            id: 'u1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnauthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _UnauthNotifier() : super(const app_auth.AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _l0Json() => {
      'id': 'letter_0',
      'num': '00',
      'title': 'Bienvenue',
      'message': 'msg',
      'signature': 'Le Facteur',
      'actions': <Map<String, dynamic>>[],
      'status': 'archived',
      'completed_actions': <String>[],
      'progress': 1.0,
      'started_at': null,
      'archived_at': '2026-05-02T10:00:00Z',
    };

Map<String, dynamic> _l1Json({List<String> completed = const []}) => {
      'id': 'letter_1',
      'num': '01',
      'title': 'Tes premières sources',
      'message': 'msg',
      'signature': 'Le Facteur',
      'actions': [
        {'id': 'define_editorial_line', 'label': 'L1', 'help': 'h1'},
        {'id': 'add_5_sources', 'label': 'L2', 'help': 'h2'},
        {'id': 'add_2_personal_sources', 'label': 'L3', 'help': 'h3'},
        {'id': 'first_perspectives_open', 'label': 'L4', 'help': 'h4'},
      ],
      'status': 'active',
      'completed_actions': completed,
      'progress': completed.length / 4,
      'started_at': '2026-05-02T10:00:00Z',
      'archived_at': null,
    };

Map<String, dynamic> _l2Json() => {
      'id': 'letter_2',
      'num': '02',
      'title': 'Ton rythme idéal',
      'message': 'msg',
      'signature': 'Le Facteur',
      'actions': [
        {'id': 'set_frequency', 'label': 'X', 'help': 'h'},
      ],
      'status': 'upcoming',
      'completed_actions': <String>[],
      'progress': 0.0,
      'started_at': null,
      'archived_at': null,
    };

void main() {
  late MockLettersRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockLettersRepository();
    container = ProviderContainer(
      overrides: [
        lettersRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => _AuthNotifier()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('returns empty state when not authenticated', () async {
    final unauthContainer = ProviderContainer(
      overrides: [
        lettersRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => _UnauthNotifier()),
      ],
    );

    final state = await unauthContainer.read(lettersProvider.future);
    expect(state.letters, isEmpty);
    expect(state.activeLetter, isNull);
    verifyNever(() => mockRepo.getLetters());

    unauthContainer.dispose();
  });

  test('build loads three letters and exposes activeLetter', () async {
    when(() => mockRepo.getLetters()).thenAnswer((_) async => [
          Letter.fromJson(_l0Json()),
          Letter.fromJson(_l1Json()),
          Letter.fromJson(_l2Json()),
        ]);

    final state = await container.read(lettersProvider.future);

    expect(state.letters.length, 3);
    expect(state.activeLetter, isNotNull);
    expect(state.activeLetter!.id, 'letter_1');
    expect(state.activeLetter!.actions.length, 4);
    expect(state.activeLetter!.actions.first.status, LetterActionStatus.active);
    verify(() => mockRepo.getLetters()).called(1);
  });

  test('refresh re-fetches and updates state', () async {
    when(() => mockRepo.getLetters())
        .thenAnswer((_) async => [Letter.fromJson(_l1Json())]);
    await container.read(lettersProvider.future);

    when(() => mockRepo.getLetters()).thenAnswer((_) async => [
          Letter.fromJson(_l1Json(completed: ['define_editorial_line'])),
        ]);
    await container.read(lettersProvider.notifier).refresh();

    final state = container.read(lettersProvider).value!;
    expect(state.letters.first.completedActions,
        contains('define_editorial_line'));
    expect(state.letters.first.actions.first.status, LetterActionStatus.done);
  });

  test('refreshLetterStatus updates only the target letter', () async {
    when(() => mockRepo.getLetters()).thenAnswer((_) async => [
          Letter.fromJson(_l0Json()),
          Letter.fromJson(_l1Json()),
          Letter.fromJson(_l2Json()),
        ]);
    await container.read(lettersProvider.future);

    when(() => mockRepo.refreshStatus('letter_1')).thenAnswer(
      (_) async =>
          Letter.fromJson(_l1Json(completed: ['define_editorial_line'])),
    );
    await container
        .read(lettersProvider.notifier)
        .refreshLetterStatus('letter_1');

    final state = container.read(lettersProvider).value!;
    expect(state.letters.length, 3);
    expect(state.letters[0].id, 'letter_0');
    expect(
        state.letters[1].completedActions, contains('define_editorial_line'));
    expect(state.letters[2].id, 'letter_2');
    verify(() => mockRepo.refreshStatus('letter_1')).called(1);
  });

  test('build surfaces repository error as AsyncError', () async {
    when(() => mockRepo.getLetters())
        .thenThrow(const LettersApiException('boom', statusCode: 500));

    expect(
      () => container.read(lettersProvider.future),
      throwsA(isA<LettersApiException>()),
    );
  });
}
