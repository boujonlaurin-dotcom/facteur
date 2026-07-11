import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/providers/letters_repository_provider.dart';
import 'package:facteur/features/lettres/repositories/letters_repository.dart';
import 'package:facteur/features/lettres/widgets/lettres_notification_banner.dart';
import 'package:facteur/features/lettres/widgets/ring_avatar.dart';
import 'package:facteur/features/settings/providers/user_profile_provider.dart';

class _MockRepo extends Mock implements LettersRepository {}

/// Stub profil qui n'ouvre pas Hive/Supabase (le notifier réel charge une box
/// au démarrage, indisponible en test).
class _StubProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _StubProfileNotifier()
      : super(const UserProfile(displayName: 'Laurin Boujon'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

Letter _activeLetter() => Letter(
      id: 'letter_1',
      letterNum: '01',
      title: 'Tes premières sources',
      message: 'msg',
      signature: 'Le Facteur',
      status: LetterStatus.active,
      actions: const [
        LetterAction(
          id: 'a0',
          label: 'Action 0',
          help: '',
          status: LetterActionStatus.done,
        ),
        LetterAction(
          id: 'a1',
          label: 'Action 1',
          help: '',
          status: LetterActionStatus.todo,
        ),
      ],
      completedActions: const [],
      progress: 0.5,
      startedAt: DateTime.utc(2026, 5, 2),
      archivedAt: null,
    );

Widget _wrap({
  required _MockRepo repo,
  String initialLocation = '/feed',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/feed',
        builder: (_, __) => const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: LettresNotificationBanner(),
          ),
        ),
      ),
      GoRoute(
        path: '/lettres',
        name: 'lettres',
        builder: (_, __) => const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: LettresNotificationBanner(),
          ),
        ),
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
      userProfileProvider.overrideWith((ref) => _StubProfileNotifier()),
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

  // ⚠️ setMockInitialValues AVANT tout getInstance (poison sinon,
  // cf. memory getInstance poison MissingPluginException).
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('hides when no active letter', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => []);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LettresNotificationBanner), findsOneWidget);
    expect(find.text('Tes premières sources'), findsNothing);
  });

  testWidgets('shows grade title + avatar + compteur', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Nouveau compte (0 lettre archivée) → grade niveau 1.
    expect(find.text('Facteur Stagiaire'), findsOneWidget);
    expect(find.byType(RingAvatar), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    // L'ancien label statique et le titre de lettre ne sont plus affichés.
    expect(find.text('Progression'), findsNothing);
    expect(find.text('Tes premières sources'), findsNothing);
  });

  testWidgets('hides when current route is /lettres*', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo, initialLocation: '/lettres'));
    // Banner masqué → pas d'animation, on peut pump simplement.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Facteur Stagiaire'), findsNothing);
  });

  testWidgets('dismiss X hides for the rest of session', (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Facteur Stagiaire'), findsOneWidget);

    await tester.tap(find.byTooltip('Masquer'));
    await tester.pump();

    expect(find.text('Facteur Stagiaire'), findsNothing);
  });

  testWidgets('throttle : masqué si affiché il y a moins de 7 jours',
      (tester) async {
    final recent = DateTime.now().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'lettres_banner_last_shown_v1': recent.millisecondsSinceEpoch,
    });
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Facteur Stagiaire'), findsNothing);
  });

  testWidgets('throttle : affiché si dernier affichage > 7 jours',
      (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 8));
    SharedPreferences.setMockInitialValues({
      'lettres_banner_last_shown_v1': old.millisecondsSinceEpoch,
    });
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Facteur Stagiaire'), findsOneWidget);
  });

  testWidgets('affichage persiste le timestamp (throttle futur)',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.getLetters()).thenAnswer((_) async => [_activeLetter()]);

    await tester.pumpWidget(_wrap(repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Facteur Stagiaire'), findsOneWidget);

    // L'affichage a écrit lettres_banner_last_shown_v1.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('lettres_banner_last_shown_v1'), isNotNull);
  });
}
