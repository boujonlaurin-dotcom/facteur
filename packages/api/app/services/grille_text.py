"""Primitives texte de « La Grille du jour » : normalisation + états des cases.

Pur (sans I/O ni DB) pour être trivialement testable. La logique d'états
utilise un **comptage d'occurrences** (corrige la version simplifiée du proto
`grille-mot.jsx`, qui sur-colore les lettres doublées en `present`).
"""

import unicodedata

# États possibles d'une case, du meilleur au moins bon (pour la coloration du
# clavier côté client : place > present > absent).
TILE_PLACE = "place"
TILE_PRESENT = "present"
TILE_ABSENT = "absent"


def normalize_word(word: str) -> str:
    """Trim, MAJUSCULES et suppression des accents/diacritiques.

    « Élève » → « ELEVE », « plaçer » → « PLACER ». Ne touche pas à la
    longueur (la validation de longueur est faite en amont).
    """
    stripped = word.strip()
    decomposed = unicodedata.normalize("NFKD", stripped)
    without_accents = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return without_accents.upper()


def compute_tiles(answer: str, guess: str) -> list[str]:
    """Calcule l'état de chaque case par comptage d'occurrences.

    Passe 1 : place les lettres exactement bien placées (`place`) et décrémente
    leur stock. Passe 2 : distribue les `present` restantes selon le stock,
    de sorte qu'une lettre doublée dans la proposition mais unique dans la
    réponse ne soit colorée `present` qu'une fois.
    """
    n = len(answer)
    result = [TILE_ABSENT] * n
    counts: dict[str, int] = {}
    for ch in answer:
        counts[ch] = counts.get(ch, 0) + 1

    for i in range(n):
        if guess[i] == answer[i]:
            result[i] = TILE_PLACE
            counts[guess[i]] -= 1

    for i in range(n):
        if result[i] == TILE_PLACE:
            continue
        if counts.get(guess[i], 0) > 0:
            result[i] = TILE_PRESENT
            counts[guess[i]] -= 1

    return result
