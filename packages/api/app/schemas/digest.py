"""Pydantic schemas for digest API (Epic 10).

Defines request/response models for the digest-first mobile app endpoints:
- GET /api/digest - Retrieve today's digest
- POST /api/digest/{id}/action - Mark actions (read/save/not_interested)
- POST /api/digest/{id}/complete - Track completion
"""

from datetime import date, datetime
from enum import Enum
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import ContentType
from app.schemas.content import SourceMini, RecommendationReason


class DigestScoreBreakdown(BaseModel):
    """Contribution d'un facteur au score de recommandation du digest.
    
    Match la structure ScoreContribution du feed pour cohérence UI.
    """
    label: str       # ex: "Thème matché : Tech"
    points: float    # ex: 70.0
    is_positive: bool = True  # True pour bonus, False pour pénalités


class DigestRecommendationReason(BaseModel):
    """Raison complète de la recommandation avec breakdown détaillé.
    
    Fournit la transparence algorithmique "Pourquoi cet article ?"
    """
    label: str                              # ex: "Vos intérêts : Tech"
    score_total: float = 0.0                # Somme de tous les points
    breakdown: List[DigestScoreBreakdown] = []  # Détail par facteur


class DigestItem(BaseModel):
    """Single item in a digest (one of 5 articles).
    
    Contains all necessary information for display and tracking:
    - content: Article metadata
    - rank: Position in digest (1-5)
    - reason: Why this article was selected (legacy, backward compatibility)
    - recommendation_reason: Detailed scoring breakdown (new, full transparency)
    - action: User's current action on this item
    """
    
    # Content metadata
    content_id: UUID
    title: str
    url: str
    thumbnail_url: Optional[str] = None
    description: Optional[str] = None
    content_type: ContentType = ContentType.ARTICLE
    duration_seconds: Optional[int] = None
    published_at: datetime
    
    # Source info
    source: SourceMini
    
    # Digest-specific info
    rank: int = Field(..., ge=1, le=5, description="Position in digest (1-5)")
    reason: str = Field(..., description="Selection reason for display (backward compatibility)")
    recommendation_reason: Optional[DigestRecommendationReason] = Field(
        None, description="Detailed scoring breakdown with contributions"
    )
    
    # User action tracking (default: no action yet)
    is_read: bool = False
    is_saved: bool = False
    is_dismissed: bool = False
    
    class Config:
        from_attributes = True


class DigestResponse(BaseModel):
    """Response for GET /api/digest.
    
    Returns the daily digest for the current user, containing exactly 5 articles
    or empty items array if digest hasn't been generated yet.
    """
    
    digest_id: UUID
    user_id: UUID
    target_date: date
    generated_at: datetime
    items: list[DigestItem] = Field(..., description="Array of 5 digest items")
    is_completed: bool = False
    completed_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class DigestAction(str, Enum):
    """Possible actions a user can take on a digest item."""
    
    READ = "read"  # User has read/consumed the article
    SAVE = "save"  # User wants to save/bookmark
    NOT_INTERESTED = "not_interested"  # User is not interested (triggers personalization mute)
    UNDO = "undo"  # Reset action


class DigestActionRequest(BaseModel):
    """Request for POST /api/digest/{digest_id}/action.
    
    Records a user action on a specific article in the digest.
    """
    
    content_id: UUID = Field(..., description="ID of the content/article")
    action: DigestAction = Field(..., description="Action to apply")


class DigestActionResponse(BaseModel):
    """Response for POST /api/digest/{digest_id}/action."""
    
    success: bool
    content_id: UUID
    action: DigestAction
    applied_at: datetime
    message: str


class DigestCompletionResponse(BaseModel):
    """Response for POST /api/digest/{id}/complete.
    
    Returns completion stats and updated streak information.
    """
    
    success: bool
    digest_id: UUID
    completed_at: datetime
    articles_read: int
    articles_saved: int
    articles_dismissed: int
    closure_time_seconds: Optional[int] = None
    
    # Updated streak info
    closure_streak: int
    streak_message: Optional[str] = None


class DigestGenerationResponse(BaseModel):
    """Response for on-demand digest generation."""
    
    success: bool
    digest_id: UUID
    items_count: int
    generated_at: datetime
    message: str


# Need to import here to avoid circular dependency
# Moved to top to fix NameError: name 'Enum' is not defined
