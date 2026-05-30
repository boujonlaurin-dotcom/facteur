import '../grille_constants.dart';
import '../models/grille_models.dart';
import '../models/tile_state.dart';

/// Construit le **texte de partage sans spoiler** d'une grille terminée.
///
/// Format (façon Wordle, voix Facteur) :
/// ```
/// La Grille du jour N°143 · Ven. 30 mai · 3/6
/// 🟧⬛⬛🟧⬛🟧
/// 🟩🟩⬛🟧⬛🟩
/// 🟩🟩🟩🟩🟩🟩
///
/// https://facteur.app/grille
/// ```
/// Les carrés ne révèlent jamais les lettres → on peut partager sans gâcher.
String buildGrilleShareText(GrilleTodayResponse today) {
  final score = grilleShareScore(today);
  final header =
      'La Grille du jour ${today.numero} · ${today.dateCourt} · $score';
  final grid = buildGrilleEmojiGrid(today.essais);
  return '$header\n$grid\n\n${buildGrilleShareLink(today)}';
}

/// Score d'affichage : `N/essaisMax` si trouvé, `X/essaisMax` sinon.
String grilleShareScore(GrilleTodayResponse today) {
  final base = today.isSolved ? '${today.nbEssais}' : 'X';
  return '$base/${today.essaisMax}';
}

/// La grille d'emojis seule (lignes séparées par `\n`).
String buildGrilleEmojiGrid(List<GrilleEssai> essais) {
  return essais
      .map(
        (e) => e.etats
            .map((etat) => TileStateX.fromServer(etat).shareEmoji)
            .join(),
      )
      .join('\n');
}

/// Lien de partage (sans spoiler). Le deep-link entrant est hors MVP, donc on
/// pointe vers la page publique de la Grille.
String buildGrilleShareLink(GrilleTodayResponse today) =>
    GrilleConstants.shareBaseUrl;
