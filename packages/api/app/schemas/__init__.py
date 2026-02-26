"""Schemas Pydantic pour l'API."""

from app.models.enums import ContentStatus, ContentType, SourceType
from app.schemas.content import (
    ContentDetailResponse,
    ContentResponse,
    ContentStatusUpdate,
)
from app.schemas.feed import FeedItemResponse, FeedResponse, PaginationMeta
from app.schemas.source import (
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
    SourceResponse,
)
from app.schemas.streak import StreakResponse
from app.schemas.subscription import SubscriptionResponse, SubscriptionStatus
from app.schemas.user import (
    OnboardingRequest,
    UserInterestResponse,
    UserPreferenceResponse,
    UserProfileCreate,
    UserProfileResponse,
    UserProfileUpdate,
    UserStatsResponse,
)

__all__ = [
    # User
    "UserProfileCreate",
    "UserProfileResponse",
    "UserProfileUpdate",
    "OnboardingRequest",
    "UserPreferenceResponse",
    "UserInterestResponse",
    "UserStatsResponse",
    # Content
    "ContentResponse",
    "ContentDetailResponse",
    "ContentStatusUpdate",
    # Source
    "SourceResponse",
    "SourceCreate",
    "SourceDetectRequest",
    "SourceDetectResponse",
    # Feed
    "FeedResponse",
    "FeedItemResponse",
    "PaginationMeta",
    # Subscription
    "SubscriptionResponse",
    "SubscriptionStatus",
    # Streak
    "StreakResponse",
    # Enums
    "ContentStatus",
    "ContentType",
    "SourceType",
]
