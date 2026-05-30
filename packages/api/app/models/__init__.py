"""Modèles SQLAlchemy pour Facteur."""

from app.models.analytics import AnalyticsEvent
from app.models.classification_queue import ClassificationQueue
from app.models.cluster_title_annotation import ClusterTitleAnnotation
from app.models.collection import Collection, CollectionItem
from app.models.content import Content, UserContentStatus
from app.models.curation import CurationAnnotation
from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.models.digest_generation_state import DigestGenerationState
from app.models.editorial_highlights_history import EditorialHighlightsHistory
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.failed_source_attempt import FailedSourceAttempt
from app.models.grille_game_state import GrilleGameState
from app.models.grille_puzzle import GrillePuzzle
from app.models.host_feed_resolution import HostFeedResolution
from app.models.learning import UserEntityPreference
from app.models.perspective_analysis import PerspectiveAnalysis
from app.models.progress import TopicQuiz, UserTopicProgress
from app.models.serene_report import SereneReport
from app.models.source import Source, UserSource
from app.models.source_search_log import SourceSearchLog
from app.models.subscription import UserSubscription
from app.models.user import UserInterest, UserPreference, UserProfile, UserStreak
from app.models.user_favorites import UserFavoriteInterest, UserFavoriteSource
from app.models.user_letter_progress import UserLetterProgress
from app.models.user_notification_preferences import UserNotificationPreferences
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleSourceKind,
    VeilleStatus,
    VeilleTopic,
    VeilleTopicKind,
)
from app.models.waitlist import WaitlistEntry
from app.models.waitlist_survey import WaitlistSurveyResponse
from app.models.well_informed_rating import UserWellInformedRating

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
    # Digest Central (Epic 10)
    "DailyDigest",
    "DigestCompletion",
    "DigestGenerationState",
    "EditorialHighlightsHistory",
    # Personalization (Story 4.7)
    "UserPersonalization",
    # Notification preferences (push activation v1)
    "UserNotificationPreferences",
    # Collections (Saved Groups)
    "Collection",
    "CollectionItem",
    # Source Attempt Tracking (Epic 12)
    "FailedSourceAttempt",
    "HostFeedResolution",
    "SourceSearchLog",
    # Perspective Analysis Cache
    "PerspectiveAnalysis",
    # Cluster title annotation cache
    "ClusterTitleAnnotation",
    # Custom Topics (Epic 11)
    "UserTopicProfile",
    # Favoris ordonnés (Story 22.1)
    "UserFavoriteInterest",
    "UserFavoriteSource",
    # Lettres du Facteur (Story 19.1)
    "UserLetterProgress",
    # Curation (Backoffice)
    "CurationAnnotation",
    # Waitlist (Landing Page)
    "WaitlistEntry",
    "WaitlistSurveyResponse",
    # Serene Feedback
    "SereneReport",
    # Entity Preferences (follow/mute on named entities)
    "UserEntityPreference",
    # Self-reported "well-informed" score (Story 14.3)
    "UserWellInformedRating",
    # Ma veille (Story 23.1)
    "VeilleConfig",
    "VeilleTopic",
    "VeilleSource",
    "VeilleKeyword",
    "VeilleStatus",
    "VeilleTopicKind",
    "VeilleSourceKind",
    # La Grille du jour (Story 24.1)
    "GrillePuzzle",
    "GrilleGameState",
]
