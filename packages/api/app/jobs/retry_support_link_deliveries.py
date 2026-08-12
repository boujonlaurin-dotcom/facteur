"""Relance bornée des enveloppes soutien restées en attente."""

from datetime import UTC, datetime

import sentry_sdk
import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.models.subscription import (
    SUPPORT_LINK_RETRYABLE_STATUSES,
    SupportLinkDelivery,
)
from app.services.support_link_email import attempt_support_link_delivery

logger = structlog.get_logger()


async def retry_due_support_link_deliveries() -> None:
    """Réessaie une seule fois les demandes temporaires arrivées à échéance."""
    try:
        async with safe_async_session() as db:
            deliveries = (
                (
                    await db.execute(
                        select(SupportLinkDelivery)
                        .where(
                            SupportLinkDelivery.status.in_(
                                SUPPORT_LINK_RETRYABLE_STATUSES
                            ),
                            SupportLinkDelivery.next_retry_at <= datetime.now(UTC),
                            SupportLinkDelivery.auto_retry_used.is_(False),
                        )
                        .order_by(SupportLinkDelivery.next_retry_at)
                        .limit(50)
                    )
                )
                .scalars()
                .all()
            )
            for delivery in deliveries:
                await attempt_support_link_delivery(db, delivery, is_auto_retry=True)
                logger.info(
                    "support_link.auto_retry_attempted",
                    delivery_id=str(delivery.id),
                    status=delivery.status,
                )
    except Exception as exc:  # Le scheduler doit survivre à une panne Resend.
        logger.exception("support_link.auto_retry_failed", error=str(exc))
        sentry_sdk.capture_exception(exc)
