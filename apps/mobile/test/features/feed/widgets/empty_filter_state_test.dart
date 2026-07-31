import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart'
    show FeedFilterKind;
import 'package:facteur/features/feed/widgets/empty_filter_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('EmptyFilterState — variante mot-clé (story 30.1)', () {
    testWidgets('affiche les trois rattrapages + la sortie neutre',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Mediapart',
        kind: FeedFilterKind.keyword,
        onClearFilter: () {},
        onBroaden: () {},
        onSearchSource: () {},
        onFollowTopic: () {},
      )));

      expect(find.text('Rien sur « Mediapart »'), findsOneWidget);
      expect(find.text('Élargir à toutes les sources'), findsOneWidget);
      expect(find.text('Chercher « Mediapart » comme source'), findsOneWidget);
      expect(find.text('Suivre « Mediapart » comme sujet'), findsOneWidget);
      expect(find.text('Revenir au feed'), findsOneWidget);
    });

    testWidgets('masque « élargir » quand la recherche l\'est déjà',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Mediapart',
        kind: FeedFilterKind.keyword,
        alreadyBroadened: true,
        onClearFilter: () {},
        onBroaden: () {},
        onSearchSource: () {},
        onFollowTopic: () {},
      )));

      expect(find.text('Élargir à toutes les sources'), findsNothing);
      expect(
        find.textContaining('même hors de tes sources'),
        findsOneWidget,
      );
    });

    testWidgets('chaque CTA déclenche son callback', (tester) async {
      var broadened = 0;
      var searched = 0;
      var followed = 0;
      var cleared = 0;

      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'écologie',
        kind: FeedFilterKind.keyword,
        onClearFilter: () => cleared++,
        onBroaden: () => broadened++,
        onSearchSource: () => searched++,
        onFollowTopic: () => followed++,
      )));

      await tester.tap(find.text('Élargir à toutes les sources'));
      await tester.tap(find.text('Chercher « écologie » comme source'));
      await tester.tap(find.text('Suivre « écologie » comme sujet'));
      await tester.tap(find.text('Revenir au feed'));
      await tester.pump();

      expect(broadened, 1);
      expect(searched, 1);
      expect(followed, 1);
      expect(cleared, 1);
    });
  });

  group('EmptyFilterState — filtres non mot-clé', () {
    testWidgets('un filtre source n\'expose que la sortie neutre',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Le Monde',
        kind: FeedFilterKind.source,
        onClearFilter: () {},
      )));

      expect(find.text('Revenir au feed'), findsOneWidget);
      expect(find.text('Élargir à toutes les sources'), findsNothing);
      expect(find.textContaining('Aucun article récent de cette source'),
          findsOneWidget);
    });

    testWidgets('un filtre thème n\'expose que la sortie neutre',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Sport',
        kind: FeedFilterKind.theme,
        onClearFilter: () {},
      )));

      expect(find.text('Revenir au feed'), findsOneWidget);
      expect(find.text('Élargir à toutes les sources'), findsNothing);
      expect(find.text('Suivre « Sport » comme sujet'), findsNothing);
    });

    testWidgets('une entité sans résultat garde son libellé propre',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Emmanuel Macron',
        kind: FeedFilterKind.entity,
        onClearFilter: () {},
      )));

      expect(find.text('Rien sur « Emmanuel Macron »'), findsOneWidget);
      expect(
        find.textContaining('Aucun article récent ne mentionne ce sujet'),
        findsOneWidget,
      );
    });

    testWidgets('la variante compacte annonce le vide sans bloquer le scroll',
        (tester) async {
      await tester.pumpWidget(_host(EmptyFilterState(
        filterName: 'Sport',
        kind: FeedFilterKind.theme,
        compact: true,
        onClearFilter: () {},
      )));

      expect(find.text('Rien sur « Sport »'), findsOneWidget);
      expect(
        find.textContaining('Voici ce qui se dit ailleurs'),
        findsOneWidget,
      );
      // Un bloc « Explorer » suit : la sortie neutre détournerait de lui.
      expect(find.text('Revenir au feed'), findsNothing);
    });
  });
}
