from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Date
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserProfile(Base):
    """Profil utilisateur."""

    __tablename__ = "user_profiles"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), unique=True, nullable=False
    )
    display_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    age_range: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    gender: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    gamification_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    weekly_goal: Mapped[int] = mapped_column(Integer, default=10)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relations
    preferences: Mapped[list["UserPreference"]] = relationship(
        back_populates="profile", cascade="all, delete-orphan"
    )
    interests: Mapped[list["UserInterest"]] = relationship(
        back_populates="profile", cascade="all, delete-orphan"
    )


class UserPreference(Base):
    """Préférences utilisateur (key-value)."""

    __tablename__ = "user_preferences"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("user_profiles.user_id", ondelete="CASCADE")
    )
    preference_key: Mapped[str] = mapped_column(String(50), nullable=False)
    preference_value: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Relations
    profile: Mapped["UserProfile"] = relationship(back_populates="preferences")


class UserInterest(Base):
    """Centres d'intérêt utilisateur."""

    __tablename__ = "user_interests"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("user_profiles.user_id", ondelete="CASCADE")
    )
    interest_slug: Mapped[str] = mapped_column(String(50), nullable=False)
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Relations
    profile: Mapped["UserProfile"] = relationship(back_populates="interests")


class UserStreak(Base):
    """Streak et progression gamification.
    
    Epic 10: Extended with closure tracking for digest-first experience.
    Closure streak tracks consecutive days the user completed their digest,
    creating a sense of accomplishment and "mission accomplished".
    """

    __tablename__ = "user_streaks"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), unique=True, nullable=False
    )
    current_streak: Mapped[int] = mapped_column(Integer, default=0)
    longest_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_activity_date: Mapped[Optional[datetime]] = mapped_column(Date, nullable=True)
    weekly_count: Mapped[int] = mapped_column(Integer, default=0)
    week_start: Mapped[Optional[datetime]] = mapped_column(Date, nullable=True)
    # Epic 10: Closure tracking for digest-first experience
    closure_streak: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    longest_closure_streak: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    last_closure_date: Mapped[Optional[datetime]] = mapped_column(Date, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )


class UserSubtopic(Base):
    """User preferences for granular sub-topics (Story 4.1c)."""

    __tablename__ = "user_subtopics"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("user_profiles.user_id", ondelete="CASCADE")
    )
    topic_slug: Mapped[str] = mapped_column(String(50), nullable=False)
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

