import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/screens/digest_section_screen.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';

/// Rétro hebdo « Tout lire » (Change 3) : `DigestSectionScreen` en mode épinglé
/// (`pinToInitial`) doit rendre l'agrégat de la **semaine** passé en
/// `initialSection`, jamais résoudre la section homonyme du feed **du jour**
/// (même `sectionKey` `bonnes`).

DigestTopicSection _bonnesSection({
  required String label,
  required String leadTitle,
  required String leadId,
}) {
  return DigestTopicSection(
    kind: SectionKind.bonnes,
    label: label,
    accent: const Color(0xFF2E7D32),
    coreVisibleCount: 4,
    topics: [
      DigestTopic(
        topicId: leadId,
        label: 'topic-$leadId',
        topicScore: 1,
        rank: 1,
        articles: [DigestItem(contentId: leadId, title: leadTitle)],
      ),
    ],
  );
}

/// Feed du jour **résolu** (non-loading) contenant une section `bonnes` dont le
/// contenu diffère de l'agrégat hebdo → prouve que l'épinglage ignore le live.
class _TodayFluxNotifier extends FluxContinuNotifier {
  @override
  Future<FluxContinuState> build() async => FluxContinuState(
        isLoading: false,
        sections: [
          _bonnesSection(
            label: 'Bonnes Nouvelles',
            leadTitle: 'title-today',
            leadId: 'today-1',
          ),
        ],
      );
}

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: [
      displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'pinToInitial=true → rend l\'agrégat hebdo (initialSection), ignore la '
      'section homonyme du feed du jour', (tester) async {
    final week = _bonnesSection(
      label: 'Bonnes Nouvelles de la semaine',
      leadTitle: 'title-week',
      leadId: 'week-1',
    );
    await tester.pumpWidget(_wrap(
      DigestSectionScreen(
        sectionKeyValue: 'bonnes',
        initialSection: week,
        pinToInitial: true,
      ),
      overrides: [
        fluxContinuProvider.overrideWith(_TodayFluxNotifier.new),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Titre + contenu de la semaine, pas du jour.
    expect(find.text('title-week'), findsOneWidget);
    expect(find.text('title-today'), findsNothing);
    expect(find.text('Bonnes Nouvelles de la semaine'), findsWidgets);
    // Pas de « Sujet suivant » (rupture vers le feed du jour) : seul « Retour ».
    expect(find.textContaining('Sujet suivant'), findsNothing);
    expect(find.text('Retour à la Tournée'), findsWidgets);
  });

  testWidgets(
      'pinToInitial=false (chemin actuel) → résout la section du feed du jour',
      (tester) async {
    // initialSection = snapshot hebdo, mais sans épinglage le feed du jour
    // résolu prend le dessus (comportement inchangé du « Tout lire » du jour).
    final week = _bonnesSection(
      label: 'Bonnes Nouvelles de la semaine',
      leadTitle: 'title-week',
      leadId: 'week-1',
    );
    await tester.pumpWidget(_wrap(
      DigestSectionScreen(
        sectionKeyValue: 'bonnes',
        initialSection: week,
      ),
      overrides: [
        fluxContinuProvider.overrideWith(_TodayFluxNotifier.new),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('title-today'), findsOneWidget);
    expect(find.text('title-week'), findsNothing);
  });
}
