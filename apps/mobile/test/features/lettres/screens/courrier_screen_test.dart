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
import 'package:facteur/features/lettres/providers/letters_provider.dart';
import 'package:facteur/features/lettres/providers/letters_repository_provider.dart';
import 'package:facteur/features/lettres/repositories/letters_repository.dart';
import 'package:facteur/features/lettres/screens/courrier_screen.dart';
import 'package:facteur/features/lettres/widgets/letter_row.dart';
import 'package:facteur/features/lettres/widgets/lettres_empty_state.dart';

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

Letter _l({
  required String id,
  required String num,
  required LetterStatus status,
  String title = 'Titre',
}) =>
    Letter(
      id: id,
      letterNum: num,
      title: title,
      message: 'msg',
      signature: 'Le Facteur',
      status: status,
      actions: const [],
      completedActions: const [],
      progress: status == LetterStatus.archived ? 1.0 : 0.0,
      startedAt: DateTime.utc(2026, 5, 2),
      archivedAt: status == LetterStatus.archived
          ? DateTime.utc(2026, 5, 1)
          : null,
    );

Widget _wrap(_MockRepo repo) {
  final router = GoRouter(
    initialLocation: '/lettres',
    routes: [
      GoRoute(
        path: '/lettres',
        name: 'lettres',
        builder: (_, __) => const CourrierScreen(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'open-letter',
            builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      lettersRepositoryProvider.overrideWithValue(repo),
      app_auth.authStateProvider.overrideWith((ref) => _AuthNotifier()),
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

  testWidgets('renders 3 sections when letters present', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [
          _l(id: 'l0', num: '00', status: LetterStatus.archived, title: 'Bienvenue'),
          _l(id: 'l1', num: '01', status: LetterStatus.active, title: 'Sources'),
          _l(id: 'l2', num: '02', status: LetterStatus.upcoming, title: 'Rythme'),
        ]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Mon courrier (progression)'), findsOneWidget);
    expect(find.text('— EN COURS —'), findsOneWidget);
    expect(find.text('— À VENIR —'), findsOneWidget);
    expect(find.text('— CLASSÉES —'), findsOneWidget);
    expect(find.byType(LetterRow), findsNWidgets(3));
  });

  testWidgets('shows empty state when no letters', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => []);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.byType(LettresEmptyState), findsOneWidget);
    expect(find.text('Rien à déposer aujourd’hui.'), findsOneWidget);
  });

  testWidgets('tap upcoming letter shows snackbar', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [
          _l(id: 'l1', num: '01', status: LetterStatus.active),
          _l(id: 'l2', num: '02', status: LetterStatus.upcoming, title: 'Future'),
        ]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Future'));
    await tester.pump();

    expect(
      find.text('Cette lettre arrivera après la précédente'),
      findsOneWidget,
    );
  });
}
