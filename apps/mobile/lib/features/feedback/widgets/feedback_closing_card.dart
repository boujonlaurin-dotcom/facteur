import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../feedback_call_copy.dart';
import 'feedback_stamp.dart';
import 'sentiment_picker.dart';

/// Carte de fin de Tournée du jour dédiée au micro-feedback (Epic 13).
///
/// Insérée juste après la carte « Fin de tournée » sur la page l'Essentiel :
/// un micro-feedback emoji (😴/🙂/🔥) sur la tournée qui vient de se terminer.
///
/// Story 13.3 : l'invitation au call **ne vit plus ici**. Elle a migré vers
/// [CallInviteEntry], posée quelques blocs avant la fin de la Tournée, là où
/// elle est réellement vue. Cette carte redevient donc compacte, ce qui la fait
/// rentrer dans le budget `section_fit` de la boîte de clôture.
class FeedbackClosingCard extends StatelessWidget {
  /// Date de la tournée notée (par défaut : aujourd'hui côté backend).
  final DateTime? digestDate;

  /// Notifie l'hôte quand la hauteur rendue change en asynchrone (vote emoji →
  /// ligne « Merci »). L'Essentiel y branche son recompute d'ancres de snap :
  /// sans ça, l'ancre de la section de clôture reste calée sur l'ancienne
  /// hauteur.
  final VoidCallback? onLayoutChanged;

  /// Quand `true`, la carte est rendue **sans son chrome extérieur** (margin +
  /// decoration + shadow + padding) : juste la Column interne, pour être
  /// embarquée en sous-bloc d'une autre carte (cf. [ClosingCardV18.secondary]).
  final bool embedded;

  const FeedbackClosingCard({
    super.key,
    this.digestDate,
    this.onLayoutChanged,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tampon « TON AVIS COMPTE » dans l'esprit des cartes de tournée.
        const FeedbackStamp(label: FeedbackCallCopy.stamp),
        const SizedBox(height: 2),

        // Micro-feedback emoji (toujours présent).
        SentimentPicker(
          digestDate: digestDate,
          onLayoutChanged: onLayoutChanged,
        ),
      ],
    );

    // Embarquée : pas de chrome propre, la carte hôte fournit boîte + padding.
    if (embedded) return content;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: content,
      ),
    );
  }
}
