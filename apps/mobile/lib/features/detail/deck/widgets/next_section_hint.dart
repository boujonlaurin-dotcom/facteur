import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';

/// Bulle éphémère annonçant la suite de la tournée, sur le **dernier article
/// d'une section** du deck (Story 34.2).
///
/// C'est un *souffle*, pas un bouton : elle apparaît à l'arrivée, dit vers quoi
/// glisser, puis s'efface d'elle-même. Rien à fermer, rien à viser — et donc
/// aucun élément posté en permanence par-dessus le texte de l'article. Le geste
/// reste l'unique chemin vers la section suivante (cf. l'affordance de tirage
/// en fin de deck, `ArticleDeckView`).
class NextSectionHint extends StatelessWidget {
  const NextSectionHint({super.key, required this.label});

  /// Nom de la section suivante — la bulle dit **où** mène le geste.
  final String label;

  static const ValueKey<String> hintKey = ValueKey('deck-next-section-hint');

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return DecoratedBox(
      key: hintKey,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Glisse pour $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Icon(
              PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
              size: 14,
              color: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
