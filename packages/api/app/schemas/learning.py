"""Schemas pour le Learning Checkpoint (Epic 13)."""

from uuid import UUID

from pydantic import BaseModel


class SignalContext(BaseModel):
    """Contexte du signal qui justifie la proposition."""

    articles_shown: int
    articles_clicked: int
    period_days: int


class ProposalResponse(BaseModel):
    """Une proposition individuelle dans le checkpoint."""

    id: UUID
    proposal_type: str  # source_priority | follow_entity | mute_entity
    entity_type: str  # source | entity
    entity_id: str
    entity_label: str
    current_value: str | None
    proposed_value: str
    signal_strength: float
    signal_context: SignalContext
    shown_count: int
    status: str

    model_config = {"from_attributes": True}


class LearningCheckpointResponse(BaseModel):
    """Carte Learning Checkpoint inseree dans le feed."""

    proposals: list[ProposalResponse]
    total_pending: int


class ApplyProposalAction(BaseModel):
    """Action sur une proposition individuelle."""

    proposal_id: UUID
    action: str  # accept | modify | dismiss
    value: str | None = None  # Valeur choisie si action=modify


class ApplyProposalsRequest(BaseModel):
    """Requete pour appliquer des propositions."""

    actions: list[ApplyProposalAction]


class ApplyProposalResult(BaseModel):
    """Resultat d'application d'une proposition."""

    proposal_id: UUID
    action: str
    success: bool
    detail: str | None = None


class ApplyProposalsResponse(BaseModel):
    """Reponse apres application des propositions."""

    applied: int
    results: list[ApplyProposalResult]


class EntityPreferenceRequest(BaseModel):
    """Requete pour creer/modifier une preference entite."""

    entity_canonical: str
    preference: str  # follow | mute


class EntityPreferenceResponse(BaseModel):
    """Reponse d'une preference entite."""

    entity_canonical: str
    preference: str
