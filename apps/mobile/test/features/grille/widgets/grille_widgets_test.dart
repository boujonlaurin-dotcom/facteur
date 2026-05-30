import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/models/tile_state.dart';
import 'package:facteur/features/grille/widgets/azerty_keyboard.dart';
import 'package:facteur/features/grille/widgets/mot_grid.dart';
import 'package:facteur/features/grille/widgets/mot_share_grid.dart';
import 'package:facteur/features/grille/widgets/leaderboard_podium.dart';
import 'package:facteur/features/grille/widgets/leaderboard_distribution.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(
      backgroundColor: FacteurPalettes.light.backgroundPrimary,
      body: Center(child: child),
    ),
  );
}

final _essais = [
  const GrilleEssai(
    mot: 'PLACER',
    etats: ['absent', 'present', 'absent', 'absent', 'absent', 'present'],
  ),
  const GrilleEssai(
    mot: 'CLIMAT',
    etats: ['place', 'place', 'place', 'place', 'place', 'place'],
  ),
];

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('MotGrid (jeu) montre la 1re lettre offerte en hint', (t) async {
    await t.pumpWidget(_wrap(const MotGrid(
      longueur: 6,
      essaisMax: 6,
      premiereLettre: 'C',
      essais: [],
      draft: '',
    )));
    await t.pumpAndSettle();
    // La lettre offerte « C » est visible sur la ligne courante.
    expect(find.text('C'), findsWidgets);
  });

  testWidgets('MotGrid (résultat) rend les lettres révélées', (t) async {
    await t.pumpWidget(_wrap(MotGrid(
      longueur: 6,
      essaisMax: 6,
      premiereLettre: 'C',
      essais: _essais,
      variant: MotGridVariant.resultat,
    )));
    await t.pumpAndSettle();
    expect(find.text('P'), findsWidgets);
    expect(find.text('A'), findsWidgets);
  });

  testWidgets('MotShareGrid : carrés colorés SANS lettre', (t) async {
    await t.pumpWidget(_wrap(MotShareGrid(essais: _essais)));
    await t.pumpAndSettle();
    // Aucune lettre ne doit apparaître (anti-spoiler).
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('Clavier : tap lettre/Entrée/Effacer câblés', (t) async {
    final keys = <String>[];
    var enter = 0;
    var back = 0;
    await t.pumpWidget(_wrap(AzertyKeyboard(
      states: const {'C': TileState.place},
      onKey: keys.add,
      onEnter: () => enter++,
      onBackspace: () => back++,
    )));
    await t.pumpAndSettle();

    await t.tap(find.text('A'));
    await t.tap(find.text('Entrée'));
    expect(keys, ['A']);
    expect(enter, 1);
    expect(back, 0);
  });

  testWidgets('Clavier : une touche « place » est colorée en succès', (t) async {
    await t.pumpWidget(_wrap(AzertyKeyboard(
      states: const {'C': TileState.place},
      onKey: (_) {},
      onEnter: () {},
      onBackspace: () {},
    )));
    await t.pumpAndSettle();
    final success = FacteurPalettes.light.success;
    final hasSuccessKey = t.widgetList<Container>(find.byType(Container)).any((w) {
      final d = w.decoration;
      return d is BoxDecoration && d.color == success;
    });
    expect(hasSuccessKey, isTrue);
  });

  testWidgets('Podium : « Toi » présent et avatar en ocre', (t) async {
    final quartier = [
      const GrilleQuartierItem(initiales: 'A·M', score: '2', rang: 1),
      const GrilleQuartierItem(initiales: 'Toi', score: '3', rang: 2, moi: true),
      const GrilleQuartierItem(initiales: 'L·B', score: '3', rang: 3),
    ];
    await t.pumpWidget(_wrap(LeaderboardPodium(quartier: quartier)));
    await t.pumpAndSettle();
    expect(find.text('Toi'), findsWidgets);

    final primary = FacteurPalettes.light.primary;
    final hasOcreAvatar = t.widgetList<Container>(find.byType(Container)).any((w) {
      final d = w.decoration;
      return d is BoxDecoration &&
          d.color == primary &&
          d.shape == BoxShape.circle;
    });
    expect(hasOcreAvatar, isTrue);
  });

  testWidgets('Distribution : la ligne du joueur porte « · toi »', (t) async {
    await t.pumpWidget(_wrap(const LeaderboardDistribution(
      distribution: [
        GrilleDistributionItem(score: '2', pct: 19),
        GrilleDistributionItem(score: '3', pct: 31),
        GrilleDistributionItem(score: 'X', pct: 3),
      ],
      monScore: '3',
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('· toi'), findsOneWidget);
    expect(find.text('Raté'), findsOneWidget);
  });
}
