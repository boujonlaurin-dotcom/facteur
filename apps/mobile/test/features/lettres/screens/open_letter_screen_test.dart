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
import 'package:facteur/features/lettres/screens/open_letter_screen.dart';

class _MockRepo extends Mock implements LettersRepository {}

class _AuthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _AuthNotifier()
      : super(
          const app_auth.AuthState(
            user: supabase.User(
              id: 'u1',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            ),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Letter _letterWithAction({
  required String actionId,
  required String label,
  required String targetRoute,
}) =>
    Letter(
      id: 'letter_2',
      letterNum: '02',
      title: 'Tes premieres lectures',
      message: 'Message',
      signature: 'Le Facteur',
      status: LetterStatus.active,
      actions: [
        LetterAction(
          id: actionId,
          label: label,
          help: 'Help',
          status: LetterActionStatus.active,
          targetRoute: targetRoute,
        ),
      ],
      completedActions: const [],
      progress: 0.0,
      startedAt: DateTime.utc(2026, 5, 2),
      archivedAt: null,
    );

Widget _destination(String label) => Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(child: Text(label)),
    );

Widget _wrap(_MockRepo repo) {
  final router = GoRouter(
    initialLocation: '/lettres/letter_2',
    routes: [
      GoRoute(
        path: '/lettres/:id',
        builder: (_, state) =>
            OpenLetterScreen(letterId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/flaner', builder: (_, __) => _destination('Flaner')),
      GoRoute(
        path: '/settings/interests',
        builder: (_, __) => _destination('Interests'),
      ),
      GoRoute(
        path: '/settings/sources',
        builder: (_, __) => _destination('Sources'),
      ),
      GoRoute(
        path: '/settings/sources/add',
        builder: (_, __) => _destination('Add source'),
      ),
      GoRoute(
        path: '/flux-continu/section/:key',
        builder: (_, state) =>
            _destination('Section ${state.pathParameters['key']}'),
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

  Future<void> _pumpForAction(
    WidgetTester tester,
    _MockRepo repo,
    Letter letter,
  ) async {
    when(() => repo.getLetters()).thenAnswer((_) async => [letter]);
    when(() => repo.refreshStatus('letter_2')).thenAnswer((_) async => letter);

    await tester.pumpWidget(_wrap(repo));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('normalizes Actu du jour action and preserves back stack', (
    tester,
  ) async {
    final repo = _MockRepo();
    await _pumpForAction(
      tester,
      repo,
      _letterWithAction(
        actionId: 'read_first_essentiel',
        label: 'Lire Actu du jour',
        targetRoute: '/digest',
      ),
    );

    await tester.tap(find.text('Lire Actu du jour'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Section essentiel'), findsWidgets);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tes premieres lectures'), findsOneWidget);
  });

  testWidgets('normalizes Bonnes nouvelles action and preserves back stack', (
    tester,
  ) async {
    final repo = _MockRepo();
    await _pumpForAction(
      tester,
      repo,
      _letterWithAction(
        actionId: 'read_first_bonnes_nouvelles',
        label: 'Decouvrir Les bonnes nouvelles',
        targetRoute: '/digest?serein=1',
      ),
    );

    await tester.tap(find.text('Decouvrir Les bonnes nouvelles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Section bonnes'), findsWidgets);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tes premieres lectures'), findsOneWidget);
  });

  testWidgets('normalizes Flaner action and preserves back stack', (
    tester,
  ) async {
    final repo = _MockRepo();
    await _pumpForAction(
      tester,
      repo,
      _letterWithAction(
        actionId: 'recommend_first_article',
        label: 'Recommander un article',
        targetRoute: '/feed',
      ),
    );

    await tester.tap(find.text('Recommander un article'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Flaner'), findsWidgets);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tes premieres lectures'), findsOneWidget);
  });
}
