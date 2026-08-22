import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/consensus_widgets.dart';

PerspectiveData _perspective({
  String domain = '',
  String name = 'Source',
  String bias = 'center',
}) {
  return PerspectiveData(
    title: 'Titre',
    url: 'https://exemple.fr/a',
    sourceName: name,
    sourceDomain: domain,
    biasStance: bias,
  );
}

/// `sourceDomain: ''` partout dans les tests de rendu : un domaine vide donne
/// `logoUrl == null` → initiale locale, aucun appel réseau.
PerspectivesResponse _response({
  int coverageCount = 3,
  ConsensusBlock consensus = const ConsensusBlock.absent(),
  DisplayGates? display,
  List<PerspectiveData>? perspectives,
}) {
  return PerspectivesResponse(
    perspectives: perspectives ??
        [
          _perspective(name: 'Alpha'),
          _perspective(name: 'Bravo'),
        ],
    keywords: const [],
    biasDistribution: const {},
    coverageCount: coverageCount,
    consensus: consensus,
    display: display ?? DisplayGates.fromCoverageCount(coverageCount),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('resolveConsensusRefs', () {
    final perspectives = [
      _perspective(domain: 'lemonde.fr', name: 'Le Monde', bias: 'center-left'),
      _perspective(domain: 'www.lefigaro.fr', name: 'Le Figaro', bias: 'right'),
    ];

    test('match perspective : nom + biais + favicon', () {
      final refs = resolveConsensusRefs(
        domains: ['lemonde.fr'],
        perspectives: perspectives,
      );
      expect(refs.single.name, 'Le Monde');
      expect(refs.single.biasStance, 'center-left');
      expect(refs.single.logoUrl, contains('lemonde.fr'));
    });

    test('strip www + lowercase des deux côtés du match', () {
      final refs = resolveConsensusRefs(
        domains: ['WWW.LeFigaro.fr'],
        perspectives: perspectives,
      );
      expect(refs.single.name, 'Le Figaro');
      expect(refs.single.domain, 'lefigaro.fr');
    });

    test('match média lu : nom + biais du lecteur', () {
      final refs = resolveConsensusRefs(
        domains: ['liberation.fr'],
        perspectives: perspectives,
        readerDomain: 'www.liberation.fr',
        readerSourceName: 'Libération',
        readerBias: 'left',
      );
      expect(refs.single.name, 'Libération');
      expect(refs.single.biasStance, 'left');
    });

    test('fallback : nom = domaine nu, biais unknown', () {
      final refs = resolveConsensusRefs(
        domains: ['inconnu.example'],
        perspectives: perspectives,
        readerDomain: 'liberation.fr',
      );
      expect(refs.single.name, 'inconnu.example');
      expect(refs.single.biasStance, 'unknown');
    });

    test('ordre servi préservé', () {
      final refs = resolveConsensusRefs(
        domains: ['lefigaro.fr', 'lemonde.fr'],
        perspectives: perspectives,
      );
      expect(refs.map((r) => r.name), ['Le Figaro', 'Le Monde']);
    });
  });

  group('resolveConsensusCtaVariant', () {
    test('réponse null → none', () {
      expect(resolveConsensusCtaVariant(null), ConsensusCtaVariant.none);
    });

    test('gates hidden (erreur réseau) → none, jamais solo', () {
      final res = PerspectivesResponse(
        perspectives: const [],
        keywords: const [],
        biasDistribution: const {},
      );
      expect(resolveConsensusCtaVariant(res), ConsensusCtaVariant.none);
    });

    test('isSolo → solo', () {
      final res = _response(coverageCount: 1);
      expect(resolveConsensusCtaVariant(res), ConsensusCtaVariant.solo);
    });

    test('hasCta + consensus available → statements', () {
      final res = _response(
        consensus: const ConsensusBlock(state: ConsensusBlock.stateAvailable),
      );
      expect(resolveConsensusCtaVariant(res), ConsensusCtaVariant.statements);
    });

    test('hasCta + pending → pending', () {
      final res = _response(
        consensus: const ConsensusBlock(state: ConsensusBlock.statePending),
      );
      expect(resolveConsensusCtaVariant(res), ConsensusCtaVariant.pending);
    });

    test('hasCta + unavailable → bare (ligne d\'entrée seule)', () {
      final res = _response();
      expect(resolveConsensusCtaVariant(res), ConsensusCtaVariant.bare);
    });
  });

  group('consensusQualifierLabel', () {
    test('mapping backend → libellés français', () {
      expect(consensusQualifierLabel('polarized'), 'polarisé');
      expect(consensusQualifierLabel('varied'), 'avis variés');
      expect(consensusQualifierLabel('convergent'), 'avis convergents');
      expect(consensusQualifierLabel(null), isNull);
      expect(consensusQualifierLabel('autre'), isNull);
    });
  });

  group('ConsensusStatementRow', () {
    testWidgets('accord : icône check, +N visible si > 0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ConsensusStatementRow(
            statement: ConsensusStatement(
              text: 'Le fait est confirmé.',
              supportCount: 4,
              plusCount: 2,
            ),
            isAgreement: true,
            refs: [ConsensusSourceRef(domain: '', name: 'Alpha')],
          ),
        ),
      );
      expect(
        find.textContaining('Le fait est confirmé.', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('+2', findRichText: true), findsOneWidget);
      expect(
        find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
        findsOneWidget,
      );
    });

    testWidgets('désaccord : icône flèches, +N masqué à 0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ConsensusStatementRow(
            statement: ConsensusStatement(
              text: 'Les avis divergent.',
              supportCount: 2,
            ),
            isAgreement: false,
            refs: [],
          ),
        ),
      );
      expect(find.textContaining('+0', findRichText: true), findsNothing);
      expect(
        find.byIcon(PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.bold)),
        findsOneWidget,
      );
    });
  });

  group('ConsensusCompareCta — variantes', () {
    testWidgets('none : rien, pas de skeleton', (tester) async {
      await tester.pumpWidget(
        _wrap(const ConsensusCompareCta(response: null)),
      );
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('solo : encart texte, pas de label Comparer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ConsensusCompareCta(
            response: _response(coverageCount: 1),
            readerSourceName: 'Le Parisien',
          ),
        ),
      );
      expect(find.text(consensusSoloText('Le Parisien')), findsOneWidget);
      expect(
        find.textContaining('Comparer les', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('statements : entrée + constats du bloc cta', (tester) async {
      final res = _response(
        coverageCount: 5,
        consensus: const ConsensusBlock(
          state: ConsensusBlock.stateAvailable,
          qualifier: 'varied',
          cta: ConsensusCta(
            agreement: ConsensusStatement(text: 'Accord mis en avant.'),
            disagreement: ConsensusStatement(text: 'Désaccord mis en avant.'),
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(ConsensusCompareCta(response: res, onTap: () {})),
      );
      expect(find.text(consensusCompareCtaLabel(5)), findsOneWidget);
      expect(
        find.textContaining('Accord mis en avant.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Désaccord mis en avant.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('pending : entrée + ligne sablier', (tester) async {
      final res = _response(
        coverageCount: 4,
        consensus: const ConsensusBlock(state: ConsensusBlock.statePending),
      );
      await tester.pumpWidget(_wrap(ConsensusCompareCta(response: res)));
      expect(find.text(consensusCompareCtaLabel(4)), findsOneWidget);
      expect(find.text(consensusPendingCtaText(4)), findsOneWidget);
      expect(
        find.byIcon(PhosphorIcons.hourglass(PhosphorIconsStyle.regular)),
        findsOneWidget,
      );
    });

    testWidgets('bare : ligne d\'entrée seule', (tester) async {
      final res = _response(coverageCount: 2);
      await tester.pumpWidget(_wrap(ConsensusCompareCta(response: res)));
      expect(find.text(consensusCompareCtaLabel(2)), findsOneWidget);
      expect(find.text(consensusPendingCtaText(2)), findsNothing);
    });

    testWidgets('tap → onTap déclenché', (tester) async {
      var tapped = false;
      final res = _response(coverageCount: 2);
      await tester.pumpWidget(
        _wrap(ConsensusCompareCta(response: res, onTap: () => tapped = true)),
      );
      await tester.tap(find.text(consensusCompareCtaLabel(2)));
      expect(tapped, isTrue);
    });
  });

  test('copy 6C : aucun em-dash', () {
    final all = [
      consensusSectionTitle,
      consensusCompareCtaLabel(3),
      consensusPendingCtaText(3),
      consensusSoloText('Source'),
      consensusConvergentFootnote(3),
      consensusPendingFootnote(3),
      consensusCarouselSubtitle(3),
      consensusAiCardTitle,
      consensusAiCardBody(3),
      consensusAiCardAction,
    ];
    for (final copy in all) {
      expect(copy.contains('—'), isFalse, reason: copy);
    }
  });
}
