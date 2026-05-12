import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_presets_provider.dart';
import 'package:facteur/features/veille/screens/steps/step1_5_preset_preview_screen.dart';

const _preset = VeillePreset(
  slug: 'ia_agentique',
  label: 'Outils IA agentique',
  accroche: 'Les derniers outils et bonnes pratiques.',
  themeId: 'tech',
  themeLabel: 'Technologie',
  topics: ['Agents LLM', 'Frameworks dev'],
  purposes: ['progresser_au_travail'],
  editorialBrief: 'Plutôt analyses concrètes.',
  sources: [
    VeillePresetSource(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Source A',
      url: 'https://a.example.com',
    ),
  ],
);

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [
      veillePresetsProvider.overrideWith((ref) async => [_preset]),
    ],
  );
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Step15PresetPreviewScreen(
          presetSlug: 'ia_agentique',
          onClose: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders preset label, accroche, topics and source', (tester) async {
    final container = _makeContainer();
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump();

    expect(find.text('Outils IA agentique'), findsOneWidget);
    expect(find.text('Les derniers outils et bonnes pratiques.'), findsOneWidget);
    expect(find.text('Agents LLM'), findsOneWidget);
    expect(find.text('Frameworks dev'), findsOneWidget);
    expect(find.text('Source A'), findsOneWidget);
    expect(find.text('Continuer avec ce pré-set'), findsOneWidget);
    expect(find.text('Personnaliser'), findsOneWidget);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('"Continuer avec ce pré-set" applies preset and jumps to step 4',
      (tester) async {
    final container = _makeContainer();
    container.read(veilleConfigProvider.notifier).openPresetPreview('ia_agentique');

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Continuer avec ce pré-set'));
    await tester.pump();

    final state = container.read(veilleConfigProvider);
    expect(state.step, 4);
    expect(state.previewPresetId, isNull);
    expect(state.selectedTheme, 'tech');
    expect(state.presetId, 'ia_agentique');
    expect(state.purpose, 'progresser_au_travail');
    expect(state.editorialBrief, 'Plutôt analyses concrètes.');
    expect(state.selectedSourceIds.contains('11111111-1111-1111-1111-111111111111'), isTrue);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('"Personnaliser" applies preset and stays on step 1',
      (tester) async {
    final container = _makeContainer();
    container.read(veilleConfigProvider.notifier).openPresetPreview('ia_agentique');

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Personnaliser'));
    await tester.pump();

    final state = container.read(veilleConfigProvider);
    expect(state.step, 1);
    expect(state.previewPresetId, isNull);
    expect(state.selectedTheme, 'tech');
    expect(state.presetId, 'ia_agentique');

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
