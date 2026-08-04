"""Schemas pour l'endpoint `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour alimenter la carte hi-fi
"L'Essentiel du jour" du feed mobile.

Lecture seule : consomme le digest déjà calculé par la cron nocturne (jamais
de pipeline LLM au request time, comme `/api/digest`).
"""

from datetime import date, datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.content import SourceMini
from app.schemas.feed import CarouselInfo


class EssentielKind(StrEnum):
    """Famille de section côté mobile (pilote l'icône / l'accent générique).

    Aligne avec `SectionKind` côté mobile (`apps/mobile/lib/features/
    flux_continu/models/flux_continu_models.dart`).
    """

    ESSENTIEL = "essentiel"
    BONNES = "bonnes"
    THEME = "theme"
    VEILLE = "veille"


class EssentielArticle(BaseModel):
    """Un article du top 5 transversal de l'Essentiel.

    Reprend les champs nécessaires à la carte hi-fi (lead/médium/light) sans
    réexposer toute la richesse d'un `DigestTopicArticle`.
    """

    content_id: UUID
    title: str
    url: str
    description: str | None = Field(
        None, description="Chapô/description pour l'aperçu au long-press (mobile)"
    )
    thumbnail_url: str | None = None
    published_at: datetime
    source: SourceMini
    source_letter: str = Field(
        ..., min_length=1, max_length=1, description="Initiale source pour la pastille"
    )
    kind: EssentielKind = EssentielKind.THEME
    theme: str | None = Field(
        None, description="Slug du thème du topic d'origine (mapping couleur mobile)"
    )
    section_label: str = Field(..., description="Libellé du topic d'origine")
    perspective_count: int = 0
    # Couverture multi-sources du sujet d'origine — pilote la pastille
    # « N sources » de la carte (seuil mobile : >= 2).
    source_count: int = 0
    # Tronqué à `PERSPECTIVE_SOURCES_CAP` à l'émission : la carte n'affiche que
    # 3 avatars et chaque entrée porte un logo qui déclenche une requête image.
    perspective_sources: list[dict] = Field(default_factory=list)
    # Polarisation du sujet d'origine ("low" | "medium" | "high"), reprise telle
    # quelle du `DigestTopic` — pilote la pastille de divergence de la carte.
    # `None` quand le topic ne la porte pas (article hors sujet transversal) :
    # le mobile reste alors silencieux.
    divergence_level: str | None = None
    rank: int = Field(..., ge=1, le=5, description="Position dans l'essentiel (1..5)")
    is_read: bool = False
    is_saved: bool = False
    is_liked: bool = False
    is_dismissed: bool = False
    read_at: datetime | None = None
    # Temps passé cumulé (s) — départage « Ouvert » (< 5 s) de « Lu en partie ».
    time_spent_seconds: int = 0
    # Lecture aboutie (fin d'article atteinte), pas seulement ouverte : c'est ce
    # qui permet à la carte héros de la Tournée d'afficher le filet de complétion.
    completed_at: datetime | None = None
    # Signaux user-aware pour affichage mobile (badges "Tu suis", pastille "Actu du jour").
    is_followed_source: bool = False
    is_followed_topic: bool = False
    is_actu_du_jour: bool = False
    # Langue détectée du titre (forward-compat).
    language: str | None = None

    class Config:
        from_attributes = True


class EssentielResponse(BaseModel):
    """Réponse pour `GET /api/essentiel`."""

    target_date: date
    generated_at: datetime
    articles: list[EssentielArticle] = Field(default_factory=list)
    is_stale_fallback: bool = Field(
        default=False,
        description=(
            "True quand l'essentiel a été construit depuis le digest d'hier "
            "en attendant que celui d'aujourd'hui soit prêt."
        ),
    )
    new_since_this_morning: int = Field(
        default=0,
        ge=0,
        description=(
            "Nb d'articles frais (sources suivies + thèmes appréciés riches) "
            "publiés depuis la génération du digest du jour, borné pour l'affichage."
        ),
    )
    carousel: CarouselInfo | None = Field(
        default=None,
        description=(
            "Carrousel semi-éditorialisé du jour (Story 32.1), mutualisé avec "
            "Flâner. Rotation déterministe date-seedée ; présent uniquement sur "
            "l'édition du jour. Champ additif (rétro-compat clients anciens)."
        ),
    )

    class Config:
        from_attributes = True


# --- Tri de l'Essentiel (Story 33.1) ------------------------------------------

# Borne du batch : le slate est verrouillé à 5 par doctrine produit, mais le
# client peut renvoyer un batch qui recouvre des décisions déjà envoyées
# (re-tri, flush après reprise). Large, mais fini.
MAX_TRIAGE_DECISIONS_PER_BATCH = 50


class TriageDecisionKind(StrEnum):
    """Issue d'un geste de tri.

    Volontairement disjoint des actions d'interaction existantes : `PASS` n'est
    **pas** `not_interested` (qui mute la source entière et sans expiration), et
    `KEEP` n'est **pas** `read` (qui déclencherait `_W_READ_PENALTY` et ferait
    disparaître de la carte l'article qu'on vient de choisir).
    """

    KEEP = "keep"
    LATER = "later"
    PASS = "pass"


class TriageVia(StrEnum):
    """Modalité du geste — sépare le swipe du mode boutons (accessibilité)."""

    SWIPE = "swipe"
    BUTTON = "button"


class TriageDecisionItem(BaseModel):
    """Une décision de tri sur un article du slate."""

    content_id: UUID
    decision: TriageDecisionKind
    rank: int | None = Field(
        None,
        ge=1,
        description="Rang de l'article dans le slate figé (1-indexé).",
    )
    decided_via: TriageVia | None = None
    latency_ms: int | None = Field(
        None,
        ge=0,
        description="Temps de décision, pour distinguer le tri distrait.",
    )


class TriageBatchRequest(BaseModel):
    """Corps de `POST /api/essentiel/triage`.

    Batché : le tri ne doit jamais attendre le réseau, le client accumule et
    flushe (debounce, fin de tri, passage en arrière-plan).
    """

    digest_date: date = Field(
        ..., description="Jour du slate trié (clé 07h30 Paris côté mobile)."
    )
    slate_size: int = Field(
        ...,
        ge=1,
        le=20,
        description="Taille du slate figé — dénominateur de la jauge.",
    )
    decisions: list[TriageDecisionItem] = Field(
        ...,
        min_length=1,
        max_length=MAX_TRIAGE_DECISIONS_PER_BATCH,
    )


class TriageBatchResponse(BaseModel):
    """Accusé de réception d'un batch de tri."""

    recorded: int = Field(..., description="Nb de décisions enregistrées (upsert).")
    saved_for_later: int = Field(
        default=0,
        description=(
            "Nb de décisions `later` ayant déclenché le save existant — même "
            "effet que le bouton signet de la carte."
        ),
    )
