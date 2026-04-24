"""Schemas pour les preferences entite (follow/mute).

Historique : ce module contenait aussi les schemas Learning Checkpoint
(Epic 13), supprimes en Sprint 2 PR1.
"""

from pydantic import BaseModel


class EntityPreferenceRequest(BaseModel):
    """Requete pour creer/modifier une preference entite."""

    entity_canonical: str
    preference: str  # follow | mute


class EntityPreferenceResponse(BaseModel):
    """Reponse d'une preference entite."""

    entity_canonical: str
    preference: str
