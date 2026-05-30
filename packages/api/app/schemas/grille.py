"""Schémas Pydantic de « La Grille du jour » (Story 24.1).

⚠️ Contrat IDENTIQUE côté mobile (PR 2). Les champs portent **directement** les
clés FR du contrat (`dateAffichee`, `nbEssais`, `premiereLettre`,
`prochainMotDansSec`, …) — pas d'`alias_generator` — pour garantir des clés
JSON byte-exactes. Toute évolution se synchronise des deux côtés.
"""

from pydantic import BaseModel


class GrilleEssai(BaseModel):
    """Une proposition jouée et ses états par case."""

    mot: str
    etats: list[str]


class GrilleTodayResponse(BaseModel):
    """Réponse de `GET /api/grille/today`.

    `mot` et `pourquoi` restent `null` tant que `statut == in_progress`
    (le mot n'est jamais exposé avant la fin de partie).
    """

    date: str
    dateAffichee: str
    dateCourt: str
    numero: str
    longueur: int
    essaisMax: int
    premiereLettre: str
    indice: str
    theme: str
    statut: str
    essais: list[GrilleEssai]
    nbEssais: int
    mot: str | None = None
    pourquoi: str | None = None
    streak: int
    prochainMotDansSec: int


class GrilleGuessRequest(BaseModel):
    """Corps de `POST /api/grille/today/guess`."""

    mot: str


class GrilleGuessResponse(BaseModel):
    """Réponse de `POST /api/grille/today/guess`.

    En cas de refus (`valide=false`), seul `raison` est renseigné et l'essai
    n'est pas consommé. En cas d'acceptation, `etats`/`statut`/`nbEssais` sont
    renseignés ; `mot`/`pourquoi` uniquement sur `solved`/`failed`.
    """

    valide: bool
    raison: str | None = None
    etats: list[str] | None = None
    statut: str | None = None
    nbEssais: int | None = None
    mot: str | None = None
    pourquoi: str | None = None


class GrilleDistributionItem(BaseModel):
    """Part (%) des joueurs pour un nombre d'essais donné (`score` ou "X")."""

    score: int | str
    pct: int


class GrilleQuartierItem(BaseModel):
    """Une ligne du podium anonymisé (`moi=true` pour le joueur courant)."""

    initiales: str
    score: int | str
    rang: int
    moi: bool = False


class GrilleLeaderboardResponse(BaseModel):
    """Réponse de `GET /api/grille/today/leaderboard` (partie terminée requise)."""

    percentile: int
    joueurs: int
    monScore: int | str
    distribution: list[GrilleDistributionItem]
    quartier: list[GrilleQuartierItem]
    streak: int
