import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/providers/letters_repository_provider.dart';
import 'package:facteur/features/lettres/repositories/letters_repository.dart';
import 'package:facteur/features/settings/providers/user_profile_provider.dart';
import 'package:facteur/features/settings/widgets/profile_progression_card.dart';

class _MockRepo extends Mock implements LettersRepository {}

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

class _FakeProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _FakeProfileNotifier()
      : super(const UserProfile(displayName: 'Laurin Boujon'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Letter _l({
  required String id,
  required LetterStatus status,
  int actionCount = 2,
  double progress = 0.0,
}) =>
    Letter(
      id: id,
      letterNum: '02',
      title: 'Titre',
      message: 'msg',
      signature: 'Le Facteur',
      status: status,
      actions: List.generate(
        actionCount,
        (i) => LetterAction(
          id: 'a$i',
          label: 'Action $i',
          help: '',
          status:
              i == 0 ? LetterActionStatus.done : LetterActionStatus.todo,
        ),
      ),
      completedActions: const [],
      progress: progress,
      startedAt: null,
      archivedAt: null,
    );

Widget _wrap(_MockRepo repo) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: ProfileProgressionCard()),
      ),
      GoRoute(
        path: '/lettres',
        name: 'lettres',
        builder: (_, __) =>
            const Scaffold(body: Text('Écran Progression')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      lettersRepositoryProvider.overrideWithValue(repo),
      app_auth.authStateProvider.overrideWith((ref) => _AuthNotifier()),
      userProfileProvider.overrideWith((ref) => _FakeProfileNotifier()),
    ],
    child: MaterialApp.router(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows grade title and active letter steps', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [
          _l(id: 'letter_1', status: LetterStatus.archived),
          _l(id: 'letter_2', status: LetterStatus.active, progress: 0.5),
        ]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('PROGRESSION'), findsOneWidget);
    expect(find.text('Facteur Alternant'), findsOneWidget);
    // La petite écriture « Lettre 02 · 1/2 étapes » a été retirée.
    expect(find.text('Lettre 02 · 1/2 étapes'), findsNothing);
  });

  testWidgets('shrinks while letters are loading', (tester) async {
    final repo = _MockRepo();
    final never = Completer<List<Letter>>();
    when(() => repo.getLetters()).thenAnswer((_) => never.future);

    await tester.pumpWidget(_wrap(repo));
    await tester.pump();

    expect(find.text('PROGRESSION'), findsNothing);
  });

  testWidgets('tap navigates to the Progression screen', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [
          _l(id: 'letter_2', status: LetterStatus.active),
        ]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Facteur Stagiaire'));
    await tester.pumpAndSettle();

    expect(find.text('Écran Progression'), findsOneWidget);
  });
}
