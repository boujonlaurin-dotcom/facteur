import 'package:facteur/config/theme.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/screens/sources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  @override
  Future<List<Source>> build() async => [
        Source(
          id: 'source',
          name: 'Source',
          type: SourceType.article,
          isCurated: true,
          isTrusted: true,
        ),
      ];
}

class _FakeSourcesStateNotifier extends UserSourcesStateNotifier {
  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('source settings and tournee actions use neutral hierarchy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSourcesProvider.overrideWith(_FakeUserSourcesNotifier.new),
          userSourcesStateProvider.overrideWith(
            _FakeSourcesStateNotifier.new,
          ),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const SourcesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(SourcesScreen));
    final colors = context.facteurColors;
    final settingsMaterial = tester.widget<Material>(
      find.byKey(const Key('source-settings-cta')),
    );

    expect(settingsMaterial.color, colors.surface);
    expect(find.widgetWithText(OutlinedButton, 'Composer ma Tournée'),
        findsOneWidget);
    expect(find.text('Ajouter une source'), findsOneWidget);
  });
}
