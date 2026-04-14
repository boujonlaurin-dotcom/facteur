import 'package:facteur/config/theme.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/widgets/proposal_stats_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LearningProposal makeProposal({
  ProposalType type = ProposalType.sourcePriority,
  double signalStrength = 0.7,
  SignalContext signalContext = const SignalContext(
    articlesShown: 15,
    articlesClicked: 0,
    articlesSaved: 0,
    periodDays: 7,
  ),
  num? currentValue = 3,
  num? proposedValue = 1,
}) {
  return LearningProposal(
    id: 'p-1',
    proposalType: type,
    entityType: EntityType.source,
    entityId: 'e-1',
    entityLabel: 'Le Monde',
    currentValue: currentValue,
    proposedValue: proposedValue,
    signalStrength: signalStrength,
    signalContext: signalContext,
    shownCount: 0,
    status: ProposalStatus.pending,
  );
}

Widget wrap(Widget child) => MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: child),
    );

void main() {
  group('ProposalStatsPanel', () {
    testWidgets('SP1 — signal_context complet : affiche les stats formatées',
        (tester) async {
      await tester.pumpWidget(wrap(
        ProposalStatsPanel(proposal: makeProposal()),
      ));

      expect(
          find.text('15 articles affichés · 0 lu · 0 sauvegardé'),
          findsOneWidget);
      expect(find.textContaining('7 derniers jours'), findsOneWidget);
    });

    testWidgets('SP2 — articlesShown == null → "Détails indisponibles"',
        (tester) async {
      await tester.pumpWidget(wrap(
        ProposalStatsPanel(
          proposal: makeProposal(
            signalContext: const SignalContext(),
          ),
        ),
      ));

      expect(find.text('Détails indisponibles'), findsOneWidget);
    });
  });

  group('signalLabelFor qualifier', () {
    test('SP3 — signalStrength >= 0.8 → "très fort"', () {
      final p = makeProposal(signalStrength: 0.85);
      expect(ProposalStatsPanel.signalLabelFor(p), contains('très fort'));
    });

    test('SP4 — signalStrength >= 0.6 → "fort"', () {
      final p = makeProposal(signalStrength: 0.65);
      final label = ProposalStatsPanel.signalLabelFor(p);
      expect(label, contains('fort'));
      expect(label, isNot(contains('très')));
    });

    test('signalStrength >= 0.4 → "modéré"', () {
      final p = makeProposal(signalStrength: 0.5);
      expect(ProposalStatsPanel.signalLabelFor(p), contains('modéré'));
    });

    test('signalStrength < 0.4 → "faible"', () {
      final p = makeProposal(signalStrength: 0.2);
      expect(ProposalStatsPanel.signalLabelFor(p), contains('faible'));
    });
  });
}
