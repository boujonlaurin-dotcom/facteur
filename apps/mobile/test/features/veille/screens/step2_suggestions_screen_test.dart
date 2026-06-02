import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';
import 'package:facteur/features/veille/screens/steps/step2_suggestions_screen.dart';

class _FakeRepo implements VeilleRepository {
  final Future<List<VeilleAngleSuggestionDto>> Function() loadAngles;

  _FakeRepo(this.loadAngles);

  @override
  Future<List<VeilleAngleSuggestionDto>> suggestAngles({
    required String themeId,
    required String themeLabel,
    String brief = '',
  }) {
    return loadAngles();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Step2SuggestionsScreen(onClose: () {})),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('loading affiche la carte explicative centrée', (tester) async {
    final pending = Completer<List<VeilleAngleSuggestionDto>>();
    final container = ProviderContainer(
      overrides: [
        veilleRepositoryProvider.overrideWithValue(
          _FakeRepo(() => pending.future),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(veilleConfigProvider, (_, __) {});
    addTearDown(sub.close);
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const []);
    });
    container.read(veilleConfigProvider.notifier).selectTheme('tech');

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final title = find.text('Recherche des bons angles');
    expect(title, findsOneWidget);
    expect(
      find.textContaining('Un angle est une facette précise'),
      findsOneWidget,
    );
    expect(
      tester.getCenter(title).dx,
      closeTo(tester.getSize(find.byType(MaterialApp)).width / 2, 1),
    );
  });

  testWidgets('angle sélectionné ouvre le gestionnaire de mots clés', (
    tester,
  ) async {
    const angle = VeilleAngleSuggestionDto(
      title: 'IA générative',
      keywords: ['llm', 'agents', 'régulation'],
      reason: 'Impact sur les workflows',
    );
    final container = ProviderContainer(
      overrides: [
        veilleRepositoryProvider.overrideWithValue(
          _FakeRepo(() async => const [angle]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(veilleConfigProvider, (_, __) {});
    addTearDown(sub.close);
    final notifier = container.read(veilleConfigProvider.notifier);
    notifier.selectTheme('tech');
    notifier.toggleAngle(angle);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('3 mots clés trackés'), findsOneWidget);
    await tester.tap(find.text('3 mots clés trackés'));
    await tester.pumpAndSettle();

    expect(find.text('Mots clés trackés'), findsOneWidget);
    expect(find.text('llm'), findsOneWidget);

    await tester.tap(find.text('llm'));
    await tester.pumpAndSettle();

    final slug = VeilleConfigNotifier.angleSlug(angle.title);
    expect(
      container.read(veilleConfigProvider).angleKeywords[slug],
      isNot(contains('llm')),
    );
    expect(find.text('llm'), findsNothing);
  });
}
