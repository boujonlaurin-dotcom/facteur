import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/content_model.dart';

/// Plafond du nombre d'articles « Explorer de nouvelles sources » affichés.
/// Au-delà de 6 le bloc cesse d'être un teaser de découverte et ressemble à un
/// feed secondaire — volontairement court. Partagé entre la page de section de
/// la Tournée et les onglets Flâner.
const int kExploreItemCap = 6;

/// Sélectionne les articles du bloc « Explorer » : retire les sources déjà
/// suivies (le bloc sert à *découvrir* de nouvelles sources) et les articles
/// déjà affichés plus haut ([alreadyShownIds], dédup), puis plafonne à
/// [kExploreItemCap]. Partagé entre la page de section de la Tournée et les
/// onglets Flâner pour garder une sémantique de découverte identique.
List<Content> pickExploreItems(
  List<Content> items,
  Set<String> alreadyShownIds,
) =>
    items
        .where((c) => !c.isFollowedSource && !alreadyShownIds.contains(c.id))
        .take(kExploreItemCap)
        .toList(growable: false);

/// Titre de section partagé (« Explorer de nouvelles sources », etc.).
class ExploreBlockHeader extends StatelessWidget {
  final String label;

  const ExploreBlockHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// Squelette de chargement affiché pendant que le bloc « Explorer » charge les
/// articles de sources non-suivies en parallèle.
class ExploreDiscoverySkeleton extends StatelessWidget {
  const ExploreDiscoverySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      children: List.generate(3, (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.04),
              ),
            ),
          ),
        );
      }),
    );
  }
}
