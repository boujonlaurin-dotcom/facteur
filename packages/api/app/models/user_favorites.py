"""Favoris ordonnés — Story 22.1.

Deux tables dédiées (intérêts vs sources) parce que le cap=3 est séparé pour
chaque catégorie. La position 0..2 est garantie par CHECK + PK composite.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    SmallInteger,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserFavoriteInterest(Base):
    """Favori intérêt (Thème OU Sujet, XOR), ordonné par position 0..2.

    PK composite (user_id, position) → garantit unicité du slot et cap=3.
    Aucune ligne ne peut exister à position=3+.
    """

    __tablename__ = "user_favorite_interests"
    __table_args__ = (
        CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_interests_position_range",
        ),
        CheckConstraint(
            "(interest_slug IS NOT NULL)::int + (custom_topic_id IS NOT NULL)::int = 1",
            name="user_favorite_interests_target_xor",
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        primary_key=True,
    )
    position: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    interest_slug: Mapped[str | None] = mapped_column(String(50), nullable=True)
    custom_topic_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_topic_profiles.id", ondelete="CASCADE"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        server_default=text("NOW()"),
    )


class UserFavoriteSource(Base):
    """Favori source, ordonné par position 0..2.

    UNIQUE (user_id, source_id) en plus du PK composite : un même source ne
    peut pas occuper deux slots simultanément.
    """

    __tablename__ = "user_favorite_sources"
    __table_args__ = (
        CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_sources_position_range",
        ),
        UniqueConstraint(
            "user_id", "source_id", name="user_favorite_sources_user_source_uniq"
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        primary_key=True,
    )
    position: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    source_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("sources.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        server_default=text("NOW()"),
    )
