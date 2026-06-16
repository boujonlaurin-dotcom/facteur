"""Modèle pré-calcul « Pas de recul » (deep recommendation par article).

Une ligne par article ouvrable depuis le digest (``content_id``), calculée
1×/batch dans la phase globale du pipeline éditorial. Le reader lit cette
table au lieu de relancer un matching LLM à l'ouverture (cf. story 27.1).
"""

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ContentDeepRecommendation(Base):
    """Recommandation « Pas de recul » pré-calculée pour un article ouvert.

    Clé = ``content_id`` (l'article que le lecteur ouvre depuis le digest).
    ``matched_content_id`` NULL = calculé mais aucun match pertinent : c'est
    une **sentinelle** qui mémorise « rien à recommander » et évite tout
    recalcul à la volée jusqu'au prochain batch éditorial.
    """

    __tablename__ = "content_deep_recommendations"

    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        primary_key=True,
    )
    matched_content_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    match_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default="now()",
    )
