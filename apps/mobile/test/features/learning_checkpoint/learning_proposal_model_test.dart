import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';

void main() {
  Map<String, dynamic> basePayload({
    String id = 'p-1',
    String type = 'source_priority',
    String entityType = 'source',
    String? entityId,
    String? entityLabel,
    num? currentValue = 3,
    num? proposedValue = 1,
    double signalStrength = 0.75,
    Map<String, dynamic>? signalContext,
  }) {
    return {
      'id': id,
      'proposal_type': type,
      'entity_type': entityType,
      'entity_id': entityId ?? 'e-1',
      'entity_label': entityLabel ?? 'Le Monde',
      'current_value': currentValue,
      'proposed_value': proposedValue,
      'signal_strength': signalStrength,
      'signal_context': signalContext ??
          {
            'articles_shown': 15,
            'articles_clicked': 0,
            'articles_saved': 0,
            'period_days': 7,
          },
    };
  }

  group('LearningProposal.fromJson', () {
    test('M1 — payload complet : tous les champs parsés', () {
      final p = LearningProposal.fromJson(basePayload());

      expect(p.id, 'p-1');
      expect(p.proposalType, ProposalType.sourcePriority);
      expect(p.entityType, EntityType.source);
      expect(p.entityLabel, 'Le Monde');
      expect(p.currentValue, 3);
      expect(p.proposedValue, 1);
      expect(p.signalStrength, closeTo(0.75, 1e-6));
      expect(p.signalContext.articlesShown, 15);
      expect(p.signalContext.periodDays, 7);
    });

    test('M2 — signal_context.articles_saved manquant : pas d\'exception',
        () {
      final payload = basePayload(signalContext: {
        'articles_shown': 10,
        'articles_clicked': 2,
        'period_days': 7,
      });

      final p = LearningProposal.fromJson(payload);
      expect(p.signalContext.articlesSaved, isNull);
      expect(p.signalContext.articlesShown, 10);
    });

    test('M3 — proposal_type inconnu : fallback unknown', () {
      final payload = basePayload(type: 'mystery_type');
      final p = LearningProposal.fromJson(payload);
      expect(p.proposalType, ProposalType.unknown);
    });
  });

  group('justificationPhrase', () {
    test('M4 — source_priority DOWN : "rarement ouvert"', () {
      final p = LearningProposal.fromJson(basePayload(
        type: 'source_priority',
        currentValue: 3,
        proposedValue: 1,
      ));
      expect(p.justificationPhrase(), 'rarement ouvert');
    });

    test('M5 — source_priority UP : "souvent ouvert"', () {
      final p = LearningProposal.fromJson(basePayload(
        type: 'source_priority',
        currentValue: 1,
        proposedValue: 3,
      ));
      expect(p.justificationPhrase(), 'souvent ouvert');
    });

    test('M6 — mute_entity : "vue mais ignorée"', () {
      final p = LearningProposal.fromJson(basePayload(
        type: 'mute_entity',
        currentValue: null,
        proposedValue: null,
      ));
      expect(p.justificationPhrase(), 'vue mais ignorée');
    });

    test('M7 — follow_entity : "suivie de près"', () {
      final p = LearningProposal.fromJson(basePayload(
        type: 'follow_entity',
        currentValue: null,
        proposedValue: null,
      ));
      expect(p.justificationPhrase(), 'suivie de près');
    });
  });

  group('ApplyAction.toJson', () {
    test('M8 — modify + value inclut value', () {
      const a = ApplyAction(
        proposalId: 'p-1',
        action: ApplyActionType.modify,
        value: 2,
      );
      expect(a.toJson(), {
        'proposal_id': 'p-1',
        'action': 'modify',
        'value': 2,
      });
    });

    test('M9 — accept sans value : pas de champ value', () {
      const a = ApplyAction(
        proposalId: 'p-1',
        action: ApplyActionType.accept,
      );
      expect(a.toJson(), {
        'proposal_id': 'p-1',
        'action': 'accept',
      });
    });

    test('M9b — dismiss : toWire = dismiss', () {
      const a = ApplyAction(
        proposalId: 'p-1',
        action: ApplyActionType.dismiss,
      );
      expect(a.toJson()['action'], 'dismiss');
    });
  });
}
