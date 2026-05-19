"""Modèles SQLAlchemy pour « Ma veille »."""

from datetime import datetime
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


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


class VeilleConfig(Base):
    """Config de veille d'un user — partial UNIQUE garantit 1 ACTIVE par user."""

    __tablename__ = "veille_configs"
    __table_args__ = (
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
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=text("'active'")
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


class VeilleKeyword(Base):
    """Mot-clé/angle rattaché à une veille_config — matché ILIKE sur title+desc."""

    __tablename__ = "veille_keywords"
    __table_args__ = (
        UniqueConstraint("veille_config_id", "keyword", name="uq_veille_keywords"),
        Index("ix_veille_keywords_config", "veille_config_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    veille_config_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("veille_configs.id", ondelete="CASCADE"),
        nullable=False,
    )
    keyword: Mapped[str] = mapped_column(String(80), nullable=False)
    position: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("0")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
