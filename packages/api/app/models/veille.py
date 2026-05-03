"""Modèles SQLAlchemy pour « Ma veille »."""

from datetime import date, datetime
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import (
    Date,
    DateTime,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class VeilleFrequency(StrEnum):
    """Cadence de livraison d'une veille."""

    WEEKLY = "weekly"
    BIWEEKLY = "biweekly"
    MONTHLY = "monthly"


class VeilleStatus(StrEnum):
    """Statut d'une config veille."""

    ACTIVE = "active"
    PAUSED = "paused"
    ARCHIVED = "archived"


class VeilleTopicKind(StrEnum):
    """Origine d'un topic rattaché à une veille."""

    PRESET = "preset"
    SUGGESTED = "suggested"
    CUSTOM = "custom"


class VeilleSourceKind(StrEnum):
    """Origine d'une source rattachée à une veille."""

    FOLLOWED = "followed"
    NICHE = "niche"


class VeilleGenerationState(StrEnum):
    """État de génération d'une livraison."""

    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class VeilleConfig(Base):
    """Config de veille d'un user — partial UNIQUE garantit 1 ACTIVE par user."""

    __tablename__ = "veille_configs"
    __table_args__ = (
        Index(
            "ix_veille_configs_next_scheduled",
            "next_scheduled_at",
            postgresql_where=text("status = 'active'"),
        ),
        Index("ix_veille_configs_user_id", "user_id"),
        Index(
            "uq_veille_configs_user_active",
            "user_id",
            unique=True,
            postgresql_where=text("status = 'active'"),
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    theme_id: Mapped[str] = mapped_column(String(50), nullable=False)
    theme_label: Mapped[str] = mapped_column(String(120), nullable=False)
    frequency: Mapped[str] = mapped_column(String(20), nullable=False)
    day_of_week: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    delivery_hour: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("7")
    )
    timezone: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'Europe/Paris'")
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=text("'active'")
    )
    last_delivered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    next_scheduled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
        onupdate=text("now()"),
    )

    purpose: Mapped[str | None] = mapped_column(Text, nullable=True)
    purpose_other: Mapped[str | None] = mapped_column(Text, nullable=True)
    editorial_brief: Mapped[str | None] = mapped_column(Text, nullable=True)
    preset_id: Mapped[str | None] = mapped_column(Text, nullable=True)


class VeilleTopic(Base):
    """Topic rattaché à une veille_config."""

    __tablename__ = "veille_topics"
    __table_args__ = (
        UniqueConstraint(
            "veille_config_id", "topic_id", name="uq_veille_topics_config_topic"
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    veille_config_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("veille_configs.id", ondelete="CASCADE"),
        nullable=False,
    )
    topic_id: Mapped[str] = mapped_column(String(80), nullable=False)
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("0")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class VeilleSource(Base):
    """Source rattachée à une veille_config (toutes sont en catalogue)."""

    __tablename__ = "veille_sources"
    __table_args__ = (
        UniqueConstraint(
            "veille_config_id", "source_id", name="uq_veille_sources_config_source"
        ),
        Index("ix_veille_sources_source_id", "source_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    veille_config_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("veille_configs.id", ondelete="CASCADE"),
        nullable=False,
    )
    source_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("sources.id", ondelete="RESTRICT"),
        nullable=False,
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    why: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("0")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class VeilleDelivery(Base):
    """Livraison périodique de veille."""

    __tablename__ = "veille_deliveries"
    __table_args__ = (
        UniqueConstraint(
            "veille_config_id",
            "target_date",
            name="uq_veille_deliveries_config_target",
        ),
        Index("ix_veille_deliveries_target_date", "target_date"),
        Index("ix_veille_deliveries_state", "generation_state"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    veille_config_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("veille_configs.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_date: Mapped[date] = mapped_column(Date, nullable=False)
    items: Mapped[list[dict]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    generation_state: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=text("'pending'")
    )
    attempts: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("0")
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    version: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("1")
    )
    generated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
        onupdate=text("now()"),
    )
