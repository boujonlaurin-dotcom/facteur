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
    # Vérité publique de couverture (média courant inclus).
    coverage_count: int = 0
    coverage_sources: list[dict] = Field(default_factory=list)
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
    # `le=50` et non 5 (Story 33.4) : la pile de tri n'est plus bornée à 5
    # articles — `GET /api/essentiel/more` sert jusqu'à 10 articles par lot,
    # rangés 1..limit, et les compléments du blend digest prolongent les slots
    # du digest. Un `le=5` levait une `ValidationError` en production dès le 6e
    # rang sérialisé (piège n°3 de la story 33.3, rejoué au premier lot de 10).
    rank: int = Field(..., ge=1, le=50, description="Position dans l'essentiel")
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


# --- « Plus d'articles ? » (Story 33.3) ---------------------------------------

# Borne de la liste d'exclusion de `GET /api/essentiel/more`. Le client envoie
# son slate ∪ ses décidés ∪ son pool local ; l'URL doit rester finie.
#
# 300 et non 100 (Story 33.4) : le slate n'est plus coupé à la cible, il porte
# tout le pool proposé et dépasse 100 ids sur une grosse journée de tri. La
# troncature `exclude.split(",")[:N]` du routeur est **silencieuse** — au-delà
# de la borne, on se remettait à proposer des articles déjà écartés.
MAX_MORE_EXCLUDE_IDS = 300

# Nb d'articles servis par défaut — « Deux de plus, tirés du même Essentiel ».
DEFAULT_MORE_LIMIT = 2


class EssentielMoreResponse(BaseModel):
    """Réponse pour `GET /api/essentiel/more` (Story 33.3).

    Deux recommandations Essentiel supplémentaires, servies quand la réserve
    locale du client (carrousel du jour) est épuisée et qu'il faut malgré tout
    honorer « Plus d'articles ? ». Même forme d'article que
    [EssentielResponse] : le client réutilise son parseur.

    Liste **vide** = pas d'inédit disponible, pas une erreur : le client garde
    son CTA visible et affiche un retour sobre.
    """

    articles: list[EssentielArticle] = Field(default_factory=list)


# --- Tri de l'Essentiel (Story 33.1) ------------------------------------------

# Borne du batch : le client peut renvoyer un batch qui recouvre des décisions
# déjà envoyées (re-tri, flush après reprise). Large, mais fini.
MAX_TRIAGE_DECISIONS_PER_BATCH = 50

# Borne de `slate_size`. 200 et non 20 (Story 33.4) : le slate n'est plus borné
# par la cible du jour, il porte tout le pool proposé et grandit à chaque
# prefetch. Le routeur valide `rank <= slate_size` — laisser 20 aurait produit
# des 422 en pleine session de tri, exactement au moment où l'utilisateur
# s'investit le plus.
MAX_TRIAGE_SLATE_SIZE = 200


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
    """Modalité du geste — sépare le swipe du mode boutons (accessibilité).

    `READ` (Story 33.2) : la carte du dessus a été tapée, l'article ouvert et
    lu — au retour, la lecture vaut « Je garde ». La décision reste un `keep`
    ordinaire ; seule la modalité dit qu'elle vient d'une lecture.
    """

    SWIPE = "swipe"
    BUTTON = "button"
    READ = "read"


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
        le=MAX_TRIAGE_SLATE_SIZE,
        description=(
            "Taille du slate au moment de la décision. Croissante depuis la "
            "story 33.4 : le slate porte tout le pool proposé, plus seulement "
            "la cible du jour (qui compte désormais les articles gardés)."
        ),
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
