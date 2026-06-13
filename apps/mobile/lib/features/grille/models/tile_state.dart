/// État d'une case de la grille « Le mot du jour ».
///
/// Trois états sont **renvoyés par le serveur** (métaphore postale) :
///   - [place]   🟩 bien placée  → bonne adresse (livrée)
///   - [present] 🟧 mal placée   → bon quartier, mauvaise rue
///   - [absent]  ⬛ absente       → n'habite pas ici
///
/// Trois états sont **client-only** (jamais renvoyés par l'API) :
///   - [empty]  case vide
///   - [filled] lettre tapée, en attente de validation
///   - [hint]   première lettre offerte (cadeau de départ)
///
/// Fichier **pur** (aucune dépendance Flutter/modèle) pour rester testable et
/// réutilisable par les widgets, providers et utilitaires de partage.
enum TileState { empty, filled, hint, place, present, absent }

extension TileStateX on TileState {
  /// Parse un état **serveur** (`place|present|absent`). Toute autre valeur est
  /// traitée comme [absent] par défaut (le serveur ne renvoie jamais autre
  /// chose, mais on dégrade sans crash).
  static TileState fromServer(String raw) {
    switch (raw) {
      case 'place':
        return TileState.place;
      case 'present':
        return TileState.present;
      case 'absent':
        return TileState.absent;
      default:
        return TileState.absent;
    }
  }

  /// Vrai pour les états révélés par le serveur (colorés).
  bool get isRevealed =>
      this == TileState.place ||
      this == TileState.present ||
      this == TileState.absent;

  /// Emoji de partage sans spoiler (façon Wordle).
  /// Les états non révélés n'ont pas d'emoji → chaîne vide.
  String get shareEmoji {
    switch (this) {
      case TileState.place:
        return '🟩';
      case TileState.present:
        return '🟧';
      case TileState.absent:
        return '⬛';
      default:
        return '';
    }
  }
}

/// Rang d'absorption d'un état pour le clavier : `place > present > absent`.
/// (un état plus fort écrase un état plus faible pour une même lettre).
const Map<TileState, int> kTileStateRank = {
  TileState.absent: 0,
  TileState.present: 1,
  TileState.place: 2,
};

/// Une proposition jouée, réduite à ce dont le clavier a besoin : la chaîne
/// devinée et la liste d'états serveur alignée case par case.
typedef GuessLike = ({String mot, List<String> etats});

/// Replie l'ensemble des essais en un état coloré par lettre du clavier.
///
/// Pour chaque lettre rencontrée, on garde l'état de rang le plus élevé
/// ([place] > [present] > [absent]) — exactement la logique `keyboardStates`
/// du design (`fKkZuc/grille-mot.jsx`). Pur : prend les essais déjà résolus
/// par le serveur, ne recalcule rien depuis la réponse (jamais exposée).
Map<String, TileState> computeKeyboardStates(Iterable<GuessLike> guesses) {
  final result = <String, TileState>{};
  for (final guess in guesses) {
    final mot = guess.mot.toUpperCase();
    for (var i = 0; i < mot.length && i < guess.etats.length; i++) {
      final letter = mot[i];
      final state = TileStateX.fromServer(guess.etats[i]);
      final existing = result[letter];
      if (existing == null ||
          (kTileStateRank[state] ?? 0) > (kTileStateRank[existing] ?? 0)) {
        result[letter] = state;
      }
    }
  }
  return result;
}
