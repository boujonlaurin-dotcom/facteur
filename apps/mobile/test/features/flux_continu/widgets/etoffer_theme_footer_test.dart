import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/widgets/etoffer_theme_footer.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart'
    show InterestState;
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/theme_suggestions_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';

Source _source(
  String id,
  String name, {
  String bias = 'center',
  String reliability = 'high',
  String? recommendedBy,
  String? reason,
}) {
  return Source(
    id: id,
    name: name,
    type: SourceType.article,
    biasStance: bias,
    reliabilityScore: reliability,
    recommendedBy: recommendedBy,
    recommendationReason: reason,
  );
}

ThemeSuggestions _data(List<ThemeSuggestion> list) =>
    ThemeSuggestions(theme: 'tech', label: 'Tech', suggestions: list);

Widget _wrap(
  Widget child, {
  required ThemeSuggestions data,
  List<Override> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      etofferThemeProvider.overrideWith((ref, slug) async => data),
      ...extra,
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// Capture les appels `setSourceState` sans toucher au réseau.
class _FakeUserSourcesStateNotifier extends UserSourcesStateNotifier {
  final List<({String id, InterestState state})> calls = [];

  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 3,
      );

  @override
  Future<void> setSourceState(String sourceId, InterestState newState) async {
    calls.add((id: sourceId, state: newState));
  }
}

void main() {
  testWidgets('Tier 1 facteur_pick : pastille « Recommandé par Facteur » + '
      'raison + Suivre + recherche', (tester) async {
    await tester.pumpWidget(_wrap(
      const EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        initiallyExpanded: true,
      ),
      data: _data([
        ThemeSuggestion(
          tier: ThemeSuggestionTier.facteurPick,
          source: _source(
            's1',
            'Heidi.news',
            reason: 'Le meilleur sur la science.',
          ),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Recommandé par Facteur'), findsOneWidget);
    expect(find.text('Le meilleur sur la science.'), findsOneWidget);
    expect(find.text('Heidi.news'), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);
    expect(find.text('Chercher une source Tech'), findsOneWidget);
  });

  testWidgets('Tier 2 quality_catalog : cadre neutre + badge éval visible '
      '(biais + fiabilité)', (tester) async {
    await tester.pumpWidget(_wrap(
      const EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        initiallyExpanded: true,
      ),
      data: _data([
        ThemeSuggestion(
          tier: ThemeSuggestionTier.qualityCatalog,
          source: _source('s2', 'Le Monde', bias: 'center', reliability: 'high'),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    // Pas de branding fort : cadre neutre.
    expect(find.text('Recommandé par Facteur'), findsNothing);
    expect(find.text('Source de qualité sur Tech'), findsOneWidget);
    // Badge d'évaluation visible.
    expect(find.text('Centre'), findsOneWidget);
    expect(find.text('Fiabilité élevée'), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);
  });

  testWidgets('Cas C — aucune source poussée : pas de phrase descriptive, '
      'seul le lien discret « Chercher une source » subsiste', (tester) async {
    await tester.pumpWidget(_wrap(
      const EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        initiallyExpanded: true,
      ),
      data: _data(const []),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pas encore de source recommandée'),
        findsNothing);
    expect(find.text('Suivre'), findsNothing);
    expect(find.text('Chercher une source Tech'), findsOneWidget);
  });

  testWidgets('Cas A — replié : bouton « Ajouter plus de sources (Tech) » '
      'seul, tap → onSearch (catalogue filtré), pas de dépli in-place',
      (tester) async {
    var searched = false;
    await tester.pumpWidget(_wrap(
      EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        onSearch: () => searched = true,
      ),
      data: _data([
        ThemeSuggestion(
          tier: ThemeSuggestionTier.facteurPick,
          source: _source('s1', 'Heidi.news', reason: 'Top.'),
        ),
      ]),
    ));
    await tester.pump();

    // Replié : ni recherche, ni source — juste le bouton renommé.
    expect(find.text('Ajouter plus de sources (Tech)'), findsOneWidget);
    expect(find.text('Étoffer Tech'), findsNothing);
    expect(find.text('Chercher une source Tech'), findsNothing);
    expect(find.text('Heidi.news'), findsNothing);

    await tester.tap(find.text('Ajouter plus de sources (Tech)'));
    await tester.pumpAndSettle();

    // Plus de dépli in-place : l'action mène au catalogue via onSearch.
    expect(searched, isTrue);
    expect(find.text('Heidi.news'), findsNothing);
  });

  testWidgets('one-tap Suivre appelle setSourceState(id, followed) et retire '
      'la source de la liste', (tester) async {
    final fake = _FakeUserSourcesStateNotifier();
    await tester.pumpWidget(_wrap(
      const EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        initiallyExpanded: true,
      ),
      data: _data([
        ThemeSuggestion(
          tier: ThemeSuggestionTier.facteurPick,
          source: _source('src-42', 'Heidi.news', reason: 'Top.'),
        ),
      ]),
      extra: [userSourcesStateProvider.overrideWith(() => fake)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();

    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.id, 'src-42');
    expect(fake.calls.single.state, InterestState.followed);
    // La source suivie disparaît des suggestions (feedback instantané).
    expect(find.text('Heidi.news'), findsNothing);
  });

  testWidgets('entrée de recherche appelle onSearch (Tier 3)', (tester) async {
    var searched = false;
    await tester.pumpWidget(_wrap(
      EtofferThemeFooter(
        slug: 'tech',
        label: 'Tech',
        initiallyExpanded: true,
        onSearch: () => searched = true,
      ),
      data: _data(const []),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chercher une source Tech'));
    await tester.pumpAndSettle();
    expect(searched, isTrue);
  });
}
