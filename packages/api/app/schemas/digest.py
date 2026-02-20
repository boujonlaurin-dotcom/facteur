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
    breakdown: List[DigestScoreBreakdown] = Field(default_factory=list)  # Détail par facteur


class DigestTopicArticle(BaseModel):
    """Single article within a topic group (topics_v1 format).

    Contains article metadata + topic-specific info like whether
    the source is followed by the user.
    """

    content_id: UUID
    title: str
    url: str
    thumbnail_url: str | None = None
    description: str | None = None
    topics: list[str] = []
    content_type: ContentType = ContentType.ARTICLE
    duration_seconds: int | None = None
    published_at: datetime
    is_paid: bool = False
    source: SourceMini
    rank: int = Field(..., ge=1, le=3, description="Position within topic (1-3)")
    reason: str
    is_followed_source: bool = False
    recommendation_reason: DigestRecommendationReason | None = None
    is_read: bool = False
    is_saved: bool = False
    is_liked: bool = False
    is_dismissed: bool = False

    class Config:
        from_attributes = True


class DigestTopic(BaseModel):
    """A topic group in the digest (topics_v1 format).

    Represents a "sujet du jour" — a topic covered by 1-3 articles
    from different sources.
    """

    topic_id: str
    label: str
    rank: int = Field(..., ge=1, le=7, description="Position in digest (1-7)")
    reason: str
    is_trending: bool = False
    is_une: bool = False
    theme: str | None = None
    topic_score: float = 0.0
    subjects: list[str] = Field(default_factory=list, description="Clustering keywords for display")
    articles: list[DigestTopicArticle] = Field(default_factory=list)

    class Config:
        from_attributes = True


class DigestItem(BaseModel):
    """Single item in a digest (one of 7 articles).

    Contains all necessary information for display and tracking:
    - content: Article metadata
    - rank: Position in digest (1-7)
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
    topics: list[str] = []  # Topics ML granulaires (slugs), vide si ML désactivé
    content_type: ContentType = ContentType.ARTICLE
    duration_seconds: Optional[int] = None
    published_at: datetime
    is_paid: bool = False

    # Source info
    source: SourceMini

    # Digest-specific info
    rank: int = Field(..., ge=1, le=7, description="Position in digest (1-7)")
    reason: str = Field(..., description="Selection reason for display (backward compatibility)")
    recommendation_reason: Optional[DigestRecommendationReason] = Field(
        None, description="Detailed scoring breakdown with contributions"
    )
    
    # User action tracking (default: no action yet)
    is_read: bool = False
    is_saved: bool = False
    is_liked: bool = False
    is_dismissed: bool = False
    
    class Config:
        from_attributes = True


class DigestResponse(BaseModel):
    """Response for GET /api/digest.

    Returns the daily digest for the current user.
    - format_version="flat_v1": legacy flat list in `items`
    - format_version="topics_v1": grouped topics in `topics` + flat fallback in `items`
    Completion is triggered after completion_threshold interactions.
    """

    digest_id: UUID
    user_id: UUID
    target_date: date
    generated_at: datetime
    mode: str = Field(default="pour_vous", description="Digest mode (pour_vous, serein, perspective, theme_focus)")
    format_version: str = Field(default="flat_v1", description="Storage format: flat_v1 or topics_v1")
    items: list[DigestItem] = Field(default_factory=list, description="Flat list of digest items (always populated for backward compat)")
    topics: list[DigestTopic] = Field(default_factory=list, description="Topic groups (populated when format_version=topics_v1)")
    completion_threshold: int = Field(
        default=5,
        description="Number of interactions needed to complete the digest"
    )
    is_completed: bool = False
    completed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class DigestAction(str, Enum):
    """Possible actions a user can take on a digest item."""

    READ = "read"  # User has read/consumed the article
    SAVE = "save"  # User wants to save/bookmark
    LIKE = "like"  # User likes this article (positive signal)
    UNLIKE = "unlike"  # User removes like
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
