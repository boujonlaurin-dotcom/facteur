import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/widgets/my_interests_sheet.dart';

/// Minimal stub notifier — overrides only `build()` to return a fixed state
/// synchronously. The repository `late` fields stay uninitialized because
/// no other notifier method is called during the widget tests.
class _StubFluxNotifier extends FluxContinuNotifier {
  _StubFluxNotifier(this._state);

  final FluxContinuState _state;

  @override
  Future<FluxContinuState> build() async => _state;
}

FluxContinuState _stateWithFavorites() {
  return const FluxContinuState(
    sections: [
      FeedThemeSection(
        kind: SectionKind.theme1,
        label: 'IA & éducation',
        accent: Color(0xFF2C3E50),
        coreVisibleCount: 2,
        items: <Content>[],
        themeSlug: 'ia_edu',
      ),
      FeedThemeSection(
        kind: SectionKind.theme2,
        label: 'Climat',
        accent: Color(0xFF6C3483),
        coreVisibleCount: 2,
        items: <Content>[],
        themeSlug: 'climat',
      ),
    ],
    isLoading: false,
  );
}

Widget _openerHost(FluxContinuState state) {
  return ProviderScope(
    overrides: [
      fluxContinuProvider.overrideWith(() => _StubFluxNotifier(state)),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMyInterestsBottomSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('showMyInterestsBottomSheet', () {
    testWidgets('lists the followed themes and the primary CTA',
        (tester) async {
      await tester.pumpWidget(_openerHost(_stateWithFavorites()));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mes intérêts'), findsOneWidget);
      expect(find.text('2 SUIVIS'), findsOneWidget);
      expect(find.text('IA & éducation'), findsOneWidget);
      expect(find.text('Climat'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('Gérer mes intérêts'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('Fermer dismisses the sheet', (tester) async {
      await tester.pumpWidget(_openerHost(_stateWithFavorites()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mes intérêts'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Mes intérêts'), findsNothing);
    });
  });
}
