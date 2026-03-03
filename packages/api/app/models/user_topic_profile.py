"""Modèle UserTopicProfile — Custom Topics (Epic 11)."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, Float, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserTopicProfile(Base):
    """Profil de topic personnalisé d'un utilisateur.

    Stocke les sujets libres suivis par l'utilisateur, enrichis par LLM
    (slug_parent, keywords, intent_description) pour le matching articles.
    """

    __tablename__ = "user_topic_profiles"
    __table_args__ = (
        UniqueConstraint("user_id", "slug_parent", name="uq_user_topic_user_slug"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    topic_name: Mapped[str] = mapped_column(String(200), nullable=False)
    slug_parent: Mapped[str] = mapped_column(String(50), nullable=False)
    keywords: Mapped[list[str] | None] = mapped_column(
        ARRAY(Text), nullable=True, default=list
    )
    intent_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default="explicit"
    )
    priority_multiplier: Mapped[float] = mapped_column(Float, default=1.0)
    composite_score: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )
