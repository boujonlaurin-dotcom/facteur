"""Favoris ordonnés — intérêts (Thème/Sujet/Veille, XOR) et sources.

Deux tables dédiées (intérêts vs sources). La position n'est plus bornée à
0..2 : l'utilisateur peut épingler autant de favoris qu'il veut, et seuls
les `FAVORITE_CAP` premiers (par position ASC) sont affichés dans la
« Tournée du jour ».
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
    """Favori intérêt (Thème OU Sujet OU Veille, XOR 3-way), ordonné par position.

    PK composite (user_id, position) → garantit unicité du slot. La position
    est entière >= 0 (plus de cap dur depuis 2026-05-18).
    """

    __tablename__ = "user_favorite_interests"
    __table_args__ = (
        CheckConstraint(
            "(interest_slug IS NOT NULL)::int "
            "+ (custom_topic_id IS NOT NULL)::int "
            "+ (veille_config_id IS NOT NULL)::int = 1",
            name="user_favorite_interests_target_xor_v2",
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
    veille_config_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("veille_configs.id", ondelete="CASCADE"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        server_default=text("NOW()"),
    )


class UserFavoriteSource(Base):
    """Favori source, ordonné par position (>=0, plus de cap dur depuis 2026-05-18).

    UNIQUE (user_id, source_id) en plus du PK composite : un même source ne
    peut pas occuper deux slots simultanément.
    """

    __tablename__ = "user_favorite_sources"
    __table_args__ = (
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
