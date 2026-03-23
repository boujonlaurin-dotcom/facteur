"""Modèles SQLAlchemy pour Facteur."""

from app.models.analytics import AnalyticsEvent
from app.models.classification_queue import ClassificationQueue
from app.models.collection import Collection, CollectionItem
from app.models.content import Content, UserContentStatus
from app.models.curation import CurationAnnotation
from app.models.daily_digest import DailyDigest
from app.models.daily_top3 import DailyTop3
from app.models.digest_completion import DigestCompletion
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.failed_source_attempt import FailedSourceAttempt
from app.models.progress import TopicQuiz, UserTopicProgress
from app.models.serene_report import SereneReport
from app.models.source import Source, UserSource
from app.models.subscription import UserSubscription
from app.models.user import UserInterest, UserPreference, UserProfile, UserStreak
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.models.waitlist import WaitlistEntry
from app.models.waitlist_survey import WaitlistSurveyResponse

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
    # Custom Topics (Epic 11)
    "UserTopicProfile",
    # Curation (Backoffice)
    "CurationAnnotation",
    # Waitlist (Landing Page)
    "WaitlistEntry",
    "WaitlistSurveyResponse",
    # Serene Feedback
    "SereneReport",
]
