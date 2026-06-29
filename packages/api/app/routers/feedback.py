"""Router pour le système de feedback utilisateur (Epic 13).

Deux mécaniques :
- Micro-feedback emoji au moment de fermeture (POST /sentiment).
- Invitation segmentée à un call qualitatif Calendly (GET /invite,
  POST /invite/shown, POST /invite/action).

La logique de segmentation (qui décide quand proposer le call selon le
niveau d'activité) vit dans `classify_segment`, fonction pure et testable.
"""

from datetime import date, datetime, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.digest_completion import DigestCompletion
from app.models.user_feedback import DigestSentiment, FeedbackInvite
from app.schemas.feedback import (
    FeedbackInviteStatus,
    InviteActionRequest,
    SentimentRequest,
)

logger = structlog.get_logger()

router = APIRouter()

# --- Constantes de gating (ajustables) ---
# Au-delà de ce nombre de jours d'absence, un utilisateur qui revient est
# considéré "returning" (de retour) — on le sollicite immédiatement.
RETURNING_GAP_DAYS = 10
# "Peu actif" : au moins LOWACTIVE_MIN digests, étalés sur >= LOWACTIVE_SPREAD_DAYS.
LOWACTIVE_MIN = 2
LOWACTIVE_SPREAD_DAYS = 7
# "Actif" : usage dense.
ACTIVE_MIN = 4
# Durée du snooze après "Pas maintenant".
SNOOZE_DAYS = 21
# Nombre maximum d'affichages avant abandon définitif.
MAX_SHOWS = 2


def classify_segment(completion_dates: list[date], today: date) -> str | None:
    """Détermine le segment d'activité éligible à l'invitation, ou None.

    Args:
        completion_dates: dates (distinctes ou non) de complétion de digest
            pour l'utilisateur, incluant idéalement le jour courant.
        today: date de référence (jour de la fermeture).

    Returns:
        "returning" | "low_active" | "active" si le seuil du segment est
        atteint, sinon None.
    """
    if not completion_dates:
        return None

    dates = sorted(set(completion_dates))
    total = len(dates)

    # Returning : revient après une longue absence.
    prior = [d for d in dates if d < today]
    if prior:
        gap = (today - max(prior)).days
        if gap >= RETURNING_GAP_DAYS:
            return "returning"

    # Actif : usage dense.
    if total >= ACTIVE_MIN:
        return "active"

    # Peu actif : usage sporadique étalé dans le temps.
    if total >= LOWACTIVE_MIN:
        spread = (dates[-1] - dates[0]).days
        if spread >= LOWACTIVE_SPREAD_DAYS:
            return "low_active"

    return None


def _parse_digest_date(raw: str | None) -> date:
    """Parse une date ISO (YYYY-MM-DD), défaut = aujourd'hui (UTC)."""
    if not raw:
        return datetime.utcnow().date()
    try:
        return date.fromisoformat(raw[:10])
    except ValueError:
        raise HTTPException(
            status_code=400, detail=f"Date invalide: '{raw}' (attendu YYYY-MM-DD)"
        )


@router.post("/sentiment")
async def submit_sentiment(
    request: SentimentRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Enregistre (upsert) le micro-feedback emoji du jour."""
    user_uuid = UUID(current_user_id)
    target = _parse_digest_date(request.digest_date)

    try:
        stmt = (
            pg_insert(DigestSentiment)
            .values(
                user_id=user_uuid,
                digest_date=target,
                sentiment=request.sentiment,
            )
            .on_conflict_do_update(
                constraint="uq_digest_sentiments_user_date",
                set_={
                    "sentiment": request.sentiment,
                    "updated_at": datetime.utcnow(),
                },
            )
        )
        await db.execute(stmt)
        await db.commit()
        return {"message": "Merci pour ton retour", "sentiment": request.sentiment}
    except Exception as e:
        logger.error(
            "submit_sentiment_error", error=str(e), user_id=str(user_uuid)
        )
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors de l'enregistrement: {str(e)}"
        )


async def _eligible_segment(db: AsyncSession, user_uuid: UUID) -> str | None:
    """Charge les dates de complétion et calcule le segment éligible."""
    rows = await db.execute(
        select(DigestCompletion.target_date).where(
            DigestCompletion.user_id == user_uuid
        )
    )
    dates = [r[0] for r in rows.all()]
    return classify_segment(dates, datetime.utcnow().date())


@router.get("/invite", response_model=FeedbackInviteStatus)
async def get_invite_status(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Indique si la modal d'invitation au call doit s'afficher."""
    user_uuid = UUID(current_user_id)

    segment = await _eligible_segment(db, user_uuid)
    if segment is None:
        return FeedbackInviteStatus(should_show=False, reason="not_eligible")

    invite = await db.scalar(
        select(FeedbackInvite).where(FeedbackInvite.user_id == user_uuid)
    )

    if invite is not None:
        if invite.status in ("accepted", "declined"):
            return FeedbackInviteStatus(
                should_show=False, segment=segment, reason=invite.status
            )
        if invite.snoozed_until and datetime.utcnow() < invite.snoozed_until:
            return FeedbackInviteStatus(
                should_show=False, segment=segment, reason="snoozed"
            )
        if invite.shown_count >= MAX_SHOWS:
            return FeedbackInviteStatus(
                should_show=False, segment=segment, reason="max_shows"
            )

    return FeedbackInviteStatus(should_show=True, segment=segment)


@router.post("/invite/shown")
async def mark_invite_shown(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Marque la modal comme affichée (incrémente le compteur)."""
    user_uuid = UUID(current_user_id)
    segment = await _eligible_segment(db, user_uuid)

    try:
        stmt = (
            pg_insert(FeedbackInvite)
            .values(
                user_id=user_uuid,
                status="pending",
                segment=segment,
                shown_count=1,
                last_shown_at=datetime.utcnow(),
            )
            .on_conflict_do_update(
                constraint="uq_feedback_invites_user",
                set_={
                    "shown_count": FeedbackInvite.shown_count + 1,
                    "last_shown_at": datetime.utcnow(),
                    "segment": segment,
                    "updated_at": datetime.utcnow(),
                },
            )
        )
        await db.execute(stmt)
        await db.commit()
        return {"message": "ok"}
    except Exception as e:
        logger.error("mark_invite_shown_error", error=str(e), user_id=str(user_uuid))
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors du suivi de l'affichage: {str(e)}"
        )


@router.post("/invite/action")
async def submit_invite_action(
    request: InviteActionRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Enregistre l'action de l'utilisateur sur la modal.

    - "accepted" : a cliqué pour prendre un call → statut terminal.
    - "declined" : "Pas maintenant" → snooze, ou abandon définitif après
      MAX_SHOWS affichages.
    """
    user_uuid = UUID(current_user_id)

    invite = await db.scalar(
        select(FeedbackInvite).where(FeedbackInvite.user_id == user_uuid)
    )
    if invite is None:
        invite = FeedbackInvite(user_id=user_uuid, shown_count=0)
        db.add(invite)

    try:
        if request.action == "accepted":
            invite.status = "accepted"
            invite.snoozed_until = None
        else:  # declined
            if invite.shown_count >= MAX_SHOWS:
                invite.status = "declined"
                invite.snoozed_until = None
            else:
                invite.status = "snoozed"
                invite.snoozed_until = datetime.utcnow() + timedelta(days=SNOOZE_DAYS)

        await db.commit()
        return {"message": "ok", "status": invite.status}
    except Exception as e:
        logger.error(
            "submit_invite_action_error", error=str(e), user_id=str(user_uuid)
        )
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors de l'enregistrement: {str(e)}"
        )
