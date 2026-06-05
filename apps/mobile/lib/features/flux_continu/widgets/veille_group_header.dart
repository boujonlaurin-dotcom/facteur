import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';

/// Libellés des deux blocs de curation veille (refonte deux blocs).
const String kVeilleSourcesLabel = 'Tes sources';
const String kVeilleElargieLabel = 'Couverture élargie';

/// Mappe le discriminateur backend `group` vers un libellé d'en-tête lisible.
/// Renvoie `null` pour un groupe inconnu/absent (backward-safe).
String? veilleGroupLabel(String? group) {
  return switch (group) {
    'sources' => kVeilleSourcesLabel,
    'elargie' => kVeilleElargieLabel,
    _ => null,
  };
}

/// Une « ligne » du feed veille : soit un en-tête de bloc, soit une carte.
///
/// Les en-têtes sont **dérivés au rendu** sur les transitions de
/// [Content.veilleGroup] — ils ne viennent pas du backend. On garde donc la
/// pagination offset plate côté API : il suffit de reconstruire les lignes
/// depuis la liste accumulée à chaque rendu pour que l'en-tête d'un bloc
/// apparaisse une seule fois, à sa première carte, peu importe la page qui l'a
/// chargée.
sealed class VeilleFeedRow {
  const VeilleFeedRow();
}

class VeilleHeaderRow extends VeilleFeedRow {
  final String label;
  const VeilleHeaderRow(this.label);
}

class VeilleArticleRow extends VeilleFeedRow {
  final Content content;
  final int index; // position dans la liste d'origine (pour le swipe-hint, etc.)
  const VeilleArticleRow(this.content, this.index);
}

/// Interleave les cartes [items] avec un en-tête léger à chaque changement de
/// [Content.veilleGroup] (y compris avant la toute première carte).
///
/// Si aucun item n'a de `veilleGroup` (backend/clients pré-refonte), aucune
/// ligne d'en-tête n'est émise → rendu identique à l'historique.
List<VeilleFeedRow> buildVeilleFeedRows(List<Content> items) {
  final rows = <VeilleFeedRow>[];
  String? lastGroup;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final label = veilleGroupLabel(item.veilleGroup);
    if (label != null && item.veilleGroup != lastGroup) {
      rows.add(VeilleHeaderRow(label));
      lastGroup = item.veilleGroup;
    }
    rows.add(VeilleArticleRow(item, i));
  }
  return rows;
}

/// En-tête de section léger inséré entre les blocs « Tes sources » et
/// « Couverture élargie » du feed veille. Calqué sur `ExploreBlockHeader`.
class VeilleGroupHeader extends StatelessWidget {
  final String label;

  const VeilleGroupHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
