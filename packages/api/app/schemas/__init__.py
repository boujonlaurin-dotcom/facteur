"""Schemas Pydantic pour l'API."""

from app.models.enums import ContentStatus, ContentType, SourceType
from app.schemas.user import (
    UserProfileCreate,
    UserProfileResponse,
    UserProfileUpdate,
    OnboardingRequest,
    UserPreferenceResponse,
    UserInterestResponse,
    UserStatsResponse,
)
from app.schemas.content import (
    ContentResponse,
    ContentDetailResponse,
    ContentStatusUpdate,
)
from app.schemas.source import (
    SourceResponse,
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
)
from app.schemas.feed import FeedResponse, FeedItemResponse, PaginationMeta
from app.schemas.subscription import SubscriptionResponse, SubscriptionStatus
from app.schemas.streak import StreakResponse

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
]

