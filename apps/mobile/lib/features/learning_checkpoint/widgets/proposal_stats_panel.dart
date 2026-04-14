import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/learning_proposal_model.dart';

/// Panneau dépliable sous la ligne d'une proposition. Affiche les stats
/// factuelles du `signal_context` (N articles affichés, lus, sauvegardés,
/// période), et un label qualitatif sur la force du signal.
class ProposalStatsPanel extends StatelessWidget {
  final LearningProposal proposal;
  const ProposalStatsPanel({super.key, required this.proposal});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final ctx = proposal.signalContext;

    if (ctx.articlesShown == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 32),
        child: Text(
          'Détails indisponibles',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final shown = ctx.articlesShown ?? 0;
    final clicked = ctx.articlesClicked ?? 0;
    final saved = ctx.articlesSaved ?? 0;
    final periodDays = ctx.periodDays ?? 7;

    final signalLabel = _signalLabel(proposal);

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$shown articles affichés · $clicked lu${clicked > 1 ? 's' : ''} · $saved sauvegardé${saved > 1 ? 's' : ''}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Période : $periodDays derniers jours',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Signal : $signalLabel',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  static String signalLabelFor(LearningProposal p) => _signalLabel(p);

  static String _signalLabel(LearningProposal p) {
    final qualifier = _strengthQualifier(p.signalStrength);
    final sense = _senseFor(p);
    return '$sense $qualifier';
  }

  static String _strengthQualifier(double s) {
    if (s >= 0.8) return 'très fort';
    if (s >= 0.6) return 'fort';
    if (s >= 0.4) return 'modéré';
    return 'faible';
  }

  static String _senseFor(LearningProposal p) {
    switch (p.proposalType) {
      case ProposalType.sourcePriority:
        final current = p.currentValue ?? 0;
        final proposed = p.proposedValue ?? 0;
        return proposed < current
            ? 'faible engagement'
            : 'engagement soutenu';
      case ProposalType.muteEntity:
        return 'faible engagement';
      case ProposalType.followEntity:
        return 'engagement soutenu';
      case ProposalType.unknown:
        return '';
    }
  }
}
