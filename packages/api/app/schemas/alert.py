"""Schémas des alertes (Epic 30, stories 30.2 puis 30.3 « alertes v2 »)."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel


class UpdateAlertRequest(BaseModel):
    """Corps commun du toggle, sources et sujets.

    `filtered` = « seulement les plus marquantes, 1 max par jour ». Défaut
    `False` pour que les clients de la v1 (qui n'envoient que `enabled`)
    gardent exactement le comportement qu'ils connaissent.
    """

    enabled: bool
    filtered: bool = False


#: Alias historique — le corps est identique côté source.
UpdateSourceAlertRequest = UpdateAlertRequest


class AlertToggleResponse(BaseModel):
    """Réponse du toggle : l'état posé + le compteur pour l'en-tête « x / 5 »."""

    enabled: bool
    filtered: bool = False
    active_count: int
    cap: int


SourceAlertToggleResponse = AlertToggleResponse


class TopicFrequencyResponse(BaseModel):
    """Devis de bruit d'un sujet, lu à l'ouverture de la fiche.

    Pendant de `sourceProfileProvider` côté source : la cadence est calculée
    ici, pas dans la liste, pour ne pas payer une agrégation par sujet affiché.
    """

    articles_30d: int = 0
    cadence_per_week: float = 0.0
    cadence_phrase: str = ""
    noisy: bool = False


class AlertContent(BaseModel):
    """Un contenu déclencheur, embarqué dans la cloche (story 30.4).

    Sans lui, la carte « Tes alertes » de la Tournée ne peut annoncer qu'un
    compteur : elle cache l'article derrière un rappel, puis le fait recharger.
    Avec lui, la carte *est* l'article et le tap ouvre le lecteur avec le titre
    déjà peint.

    `source_*` décrit la **source réelle de l'article**, pas la cible de la
    cloche : une alerte sujet ramène des articles de médias variés, et c'est
    exactement ce qui la rend lisible.
    """

    content_id: UUID
    title: str
    url: str | None = None
    thumbnail_url: str | None = None
    published_at: datetime | None = None
    content_type: str | None = None
    source_id: UUID | None = None
    source_name: str = ""
    source_logo_url: str | None = None


class AlertItem(BaseModel):
    """Une cloche active, telle que rendue par l'écran « Mes alertes ».

    `last_published_at` porte le « silence comme preuve » : c'est lui qui
    permet d'écrire « Rien de neuf depuis N semaines, et c'est vérifié ».

    `kind` distingue les deux familles ; pour un sujet, `source_id` /
    `source_name` portent l'identité du sujet (le client ne manipule qu'une
    liste). Les champs restent nommés `source_*` pour ne pas casser les clients
    de la v1, qui les lisent sans condition.

    `contents` (30.4) est **additif** : `new_content` reste le compteur de la
    pastille, et un client v1 qui ignore `contents` parse la réponse à
    l'identique. C'est la contrainte du split staging/prod — le backend
    `production` sert des clients qui ont une semaine de retard.
    """

    kind: Literal["source", "topic"] = "source"
    source_id: UUID
    source_name: str
    source_logo_url: str | None = None
    filtered: bool = False
    articles_30d: int = 0
    cadence_per_week: float = 0.0
    last_published_at: datetime | None = None
    last_alert_sent_at: datetime | None = None
    new_content: int = 0
    contents: list[AlertContent] = []


class AlertsResponse(BaseModel):
    cap: int
    active_count: int
    items: list[AlertItem] = []
