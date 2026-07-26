"""Gouverneur de budget push par utilisateur (Epic 30, PR #1).

Fenêtres glissantes 24h/7j en UTC sur les livraisons `sent`, comptées par
`(user, target_date, kind)` distincts (multi-devices = 1 seul push logique).
Règle des 4h : un kind non rituel est refusé si un push rituel a été envoyé il
y a moins de 4h, ou si le prochain créneau rituel tombe dans moins de 4h — le
rituel (tournée) garde son territoire. Le kind rituel n'est jamais bloqué par
le cooldown mais reste soumis aux budgets.

Exception `ritual_companion` (story 30.2) : les alertes source sont
silencieuses et partent dans la même passe que la tournée — le cooldown les
refuserait toutes. Elles en sont donc exemptées, mais restent soumises aux
budgets, ce qui laisse au plus 1 alerte par jour une fois la tournée envoyée.
"""

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.push_notification import PushDelivery, PushDevice

DAILY_BUDGET = 2
WEEKLY_BUDGET = 6
RITUAL_COOLDOWN = timedelta(hours=4)
RITUAL_KINDS = {"daily_digest"}


@dataclass(frozen=True)
class GovernorDecision:
    allowed: bool
    reason: str | None = None


async def check_push_budget(
    session: AsyncSession,
    *,
    user_id: UUID,
    kind: str,
    now: datetime,
    target_date: date | None = None,
    next_ritual_at: datetime | None = None,
    ritual_companion: bool = False,
) -> GovernorDecision:
    """Décide si un push `kind` peut partir maintenant pour `user_id`.

    `target_date` identifie le push logique en cours : ses livraisons déjà
    `sent` (autres devices du même utilisateur) ne comptent pas dans les
    budgets, sinon le 2e device serait bloqué par le 1er.

    `ritual_companion=True` exempte le kind du cooldown rituel (il accompagne
    la tournée au lieu de lui disputer son territoire) sans toucher aux
    budgets.
    """
    week_ago = now - timedelta(days=7)
    day_ago = now - timedelta(hours=24)

    rows = (
        await session.execute(
            select(
                PushDelivery.target_date,
                PushDelivery.kind,
                func.max(PushDelivery.sent_at).label("last_sent_at"),
            )
            .join(PushDevice, PushDevice.device_id == PushDelivery.device_id)
            .where(
                PushDevice.user_id == user_id,
                PushDelivery.status == "sent",
                PushDelivery.sent_at >= week_ago,
            )
            .group_by(PushDelivery.target_date, PushDelivery.kind)
        )
    ).all()

    if kind not in RITUAL_KINDS and not ritual_companion:
        if any(
            row.kind in RITUAL_KINDS and row.last_sent_at >= now - RITUAL_COOLDOWN
            for row in rows
        ):
            return GovernorDecision(allowed=False, reason="ritual_cooldown")
        if next_ritual_at is not None and now <= next_ritual_at < now + RITUAL_COOLDOWN:
            return GovernorDecision(allowed=False, reason="ritual_upcoming")

    budget_rows = [
        row for row in rows if not (row.kind == kind and row.target_date == target_date)
    ]
    daily_count = sum(1 for row in budget_rows if row.last_sent_at >= day_ago)
    if daily_count >= DAILY_BUDGET:
        return GovernorDecision(allowed=False, reason="daily_budget_exceeded")
    if len(budget_rows) >= WEEKLY_BUDGET:
        return GovernorDecision(allowed=False, reason="weekly_budget_exceeded")
    return GovernorDecision(allowed=True)
