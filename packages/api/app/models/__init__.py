"""Modèles SQLAlchemy pour Facteur."""

from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.user import UserProfile, UserPreference, UserInterest, UserStreak
from app.models.source import Source, UserSource
from app.models.content import Content, UserContentStatus
from app.models.classification_queue import ClassificationQueue
from app.models.progress import UserTopicProgress, TopicQuiz
from app.models.analytics import AnalyticsEvent
from app.models.subscription import UserSubscription
from app.models.daily_top3 import DailyTop3
from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.models.user_personalization import UserPersonalization
from app.models.collection import Collection, CollectionItem
from app.models.failed_source_attempt import FailedSourceAttempt

__all__ = [
    # Enums
    "SourceType",
    "ContentType",
    "ContentStatus",
    # User models
    "UserProfile",
    "UserPreference",
    "UserInterest",
    "UserStreak",
    # Source models
    "Source",
    "UserSource",
    # Content models
    "Content",
    "UserContentStatus",
    # Classification Queue (US-2)
    "ClassificationQueue",
    # Analytics
    "AnalyticsEvent",
    # Subscription
    "UserSubscription",
    # Progress (Epic 8)
    "UserTopicProgress",
    "TopicQuiz",
    # Daily Briefing (Story 4.4)
    "DailyTop3",
    # Digest Central (Epic 10)
    "DailyDigest",
    "DigestCompletion",
    # Personalization (Story 4.7)
    "UserPersonalization",
    # Collections (Saved Groups)
    "Collection",
    "CollectionItem",
    # Source Attempt Tracking (Epic 12)
    "FailedSourceAttempt",
]

