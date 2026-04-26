"""Cache des résolutions host → feed_url pour smart source search."""

from datetime import datetime

from sqlalchemy import DateTime, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class HostFeedResolution(Base):
    """Mémoïse la détection RSS pour un host.

    Permet de court-circuiter la chaîne RSSParser (httpx + suffixes + index
    page follow) lors d'appels répétés sur le même host depuis la pipeline
    Brave / Google News. Une ligne par host. ``feed_url IS NULL`` indique
    un cache négatif (host probé sans feed découvert) avec un TTL plus
    court pour permettre une re-détection.
    """

    __tablename__ = "host_feed_resolutions"

    host: Mapped[str] = mapped_column(String(255), primary_key=True)
    feed_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    logo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    resolved_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    __table_args__ = (Index("ix_host_feed_resolutions_expires_at", "expires_at"),)
