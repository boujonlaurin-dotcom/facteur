import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/lettres/providers/letters_repository_provider.dart';
import 'package:facteur/features/lettres/repositories/letters_repository.dart';
import 'package:facteur/features/saved/models/collection_model.dart';
import 'package:facteur/features/saved/providers/collections_provider.dart';
import 'package:facteur/features/saved/repositories/collections_repository.dart';
import 'package:facteur/features/saved/widgets/collection_picker_sheet.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

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

void main() {
  late MockCollectionsRepository mockCollectionsRepo;
  late MockLettersRepository mockLettersRepo;

  setUp(() {
    mockCollectionsRepo = MockCollectionsRepository();
    mockLettersRepo = MockLettersRepository();
  });

  testWidgets('confirm déclenche un silent refresh des lettres',
      (tester) async {
    final defaultCollection = Collection(
      id: 'default-col',
      name: 'Par défaut',
      isDefault: true,
      createdAt: DateTime.parse('2026-05-01T10:00:00Z'),
    );

    when(
      () => mockCollectionsRepo.listCollections(),
    ).thenAnswer((_) async => [defaultCollection]);
    when(
      () => mockCollectionsRepo.addToCollection('default-col', 'content-1'),
    ).thenAnswer((_) async {});
    when(() => mockLettersRepo.getLetters()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(mockCollectionsRepo),
          lettersRepositoryProvider.overrideWithValue(mockLettersRepo),
          app_auth.authStateProvider.overrideWith((ref) => _AuthNotifier()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [FacteurPalettes.light]),
          home: const Scaffold(
            body: CollectionPickerSheet(contentId: 'content-1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Confirmer (1)'), findsOneWidget);

    await tester.tap(find.text('Confirmer (1)'));
    await tester.pump();
    await tester.pumpAndSettle();

    verify(
      () => mockCollectionsRepo.addToCollection('default-col', 'content-1'),
    ).called(1);
    verify(() => mockLettersRepo.getLetters()).called(greaterThanOrEqualTo(1));
  });
}
