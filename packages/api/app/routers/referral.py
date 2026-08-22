"""Parrainage — code de partage par utilisateur et attribution d'installation.

Story partage.2. Deux endpoints authentifiés :

- `GET /api/referral/me` → le code stable de l'utilisateur (créé paresseusement)
  et le nombre de filleuls déjà attribués.
- `POST /api/referral/attribution` → pose l'attribution du filleul au premier
  lancement (Install Referrer Android). **Toujours 200** : un premier lancement
  ne doit jamais échouer sur de l'attribution, qui est un signal analytique.
"""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

import structlog
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.referral import (
    REFERRAL_CODE_ALPHABET,
    REFERRAL_CODE_LENGTH,
    ReferralAttribution,
    ReferralCode,
)
from app.services.posthog_client import get_posthog_client
from app.services.user_service import ACQUISITION_SOURCE_KEY, UserService

logger = structlog.get_logger()

router = APIRouter()

# Tentatives de génération avant d'abandonner : une collision sur 30^6 codes est
# déjà improbable, trois de suite le sont assez pour signaler un vrai problème.
_CODE_MAX_ATTEMPTS = 3

_ATTRIBUTION_COLUMNS = ReferralAttribution.__table__.c


class ReferralMeResponse(BaseModel):
    code: str
    joined_count: int


class AttributionRequest(BaseModel):
    code: str = Field(..., description="Code de parrainage lu dans le lien d'install")
    surface: str | None = Field(None, description="Surface de partage (utm_content)")
    platform: str | None = Field(None, description="android | ios")
    store: str | None = Field(None, description="play | app_store")
    utm_source: str | None = None
    utm_medium: str | None = None
    utm_campaign: str | None = None
    referrer_raw: str | None = Field(None, description="Chaîne Install Referrer brute")


class AttributionResponse(BaseModel):
    attributed: bool


def _generate_code() -> str:
    return "".join(
        secrets.choice(REFERRAL_CODE_ALPHABET) for _ in range(REFERRAL_CODE_LENGTH)
    )


def _fit(value: str | None, column: str) -> str | None:
    """Ajuste une valeur client à la largeur de sa colonne.

    On tronque au lieu de rejeter : le « toujours 200 » de l'attribution vaut
    aussi pour une valeur trop longue. La borne vient du modèle, pour qu'élargir
    une colonne suffise à élargir la troncature.
    """
    if value is None:
        return None
    cleaned = value.strip()[: _ATTRIBUTION_COLUMNS[column].type.length]
    return cleaned or None


async def _ensure_code(db: AsyncSession, user_id: UUID) -> str:
    """Retourne le code de l'utilisateur, en le créant au premier appel.

    `on_conflict_do_nothing()` **sans cible** absorbe les deux conflits possibles :
    la PK `user_id` (deux requêtes concurrentes du même utilisateur) et l'unicité
    `code` (collision avec le code d'un autre utilisateur). On distingue les deux
    par un re-select : une ligne présente = la nôtre, absente = collision de code
    à rejouer.
    """
    existing = await db.scalar(
        select(ReferralCode.code).where(ReferralCode.user_id == user_id)
    )
    if existing:
        return existing

    for _ in range(_CODE_MAX_ATTEMPTS):
        await db.execute(
            pg_insert(ReferralCode)
            .values(user_id=user_id, code=_generate_code())
            .on_conflict_do_nothing()
        )
        await db.commit()
        code = await db.scalar(
            select(ReferralCode.code).where(ReferralCode.user_id == user_id)
        )
        if code:
            return code

    logger.error("referral_code_generation_failed", user_id=str(user_id))
    raise RuntimeError("Impossible de générer un code de parrainage unique")


@router.get("/me", response_model=ReferralMeResponse)
async def get_my_referral(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> ReferralMeResponse:
    """Code de parrainage stable + nombre de filleuls attribués."""
    # Le partage est souvent la première écriture d'un compte neuf, et les deux
    # tables ont une FK vers `user_profiles`.
    await UserService(db).get_or_create_profile(current_user_id)
    user_id = UUID(current_user_id)
    code = await _ensure_code(db, user_id)

    joined_count = await db.scalar(
        select(func.count())
        .select_from(ReferralAttribution)
        .where(ReferralAttribution.code == code)
    )
    return ReferralMeResponse(code=code, joined_count=joined_count or 0)


@router.post("/attribution", response_model=AttributionResponse)
async def post_attribution(
    payload: AttributionRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> AttributionResponse:
    """Attribue le filleul au parrain porteur de `code`. Toujours 200.

    `attributed: false` sur code inconnu, auto-parrainage, attribution déjà posée
    ou erreur inattendue — jamais d'exception remontée au premier lancement.
    """
    user_id = UUID(current_user_id)
    code = (payload.code or "").strip().upper()
    if not code:
        return AttributionResponse(attributed=False)

    try:
        await UserService(db).get_or_create_profile(current_user_id)

        owner_id = await db.scalar(
            select(ReferralCode.user_id).where(ReferralCode.code == code)
        )
        if owner_id is None or owner_id == user_id:
            # Code inconnu, ou auto-parrainage (l'app peut relire son propre lien).
            return AttributionResponse(attributed=False)

        # RETURNING plutôt que `rowcount`, qui ne distingue pas l'insertion du
        # no-op sur un INSERT ORM avec `on_conflict_do_nothing`.
        inserted_id = await db.scalar(
            pg_insert(ReferralAttribution)
            .values(
                id=uuid4(),
                referred_user_id=user_id,
                code=code,
                surface=_fit(payload.surface, "surface"),
                platform=_fit(payload.platform, "platform"),
                store=_fit(payload.store, "store"),
                utm_source=_fit(payload.utm_source, "utm_source"),
                utm_medium=_fit(payload.utm_medium, "utm_medium"),
                utm_campaign=_fit(payload.utm_campaign, "utm_campaign"),
                referrer_raw=_fit(payload.referrer_raw, "referrer_raw"),
            )
            .on_conflict_do_nothing(index_elements=["referred_user_id"])
            .returning(ReferralAttribution.id)
        )
        if inserted_id is None:
            await db.rollback()
            return AttributionResponse(attributed=False)

        # Une source déjà connue (waitlist, creator…) est plus spécifique : on ne
        # l'écrase pas, et on ne re-propage vers PostHog que si la base a changé.
        source_written = await UserService(db).upsert_preference(
            current_user_id,
            ACQUISITION_SOURCE_KEY,
            "referral",
            only_if_absent=True,
        )
        await db.commit()
    except Exception as exc:
        await db.rollback()
        logger.error(
            "referral_attribution_failed", user_id=str(user_id), error=str(exc)
        )
        return AttributionResponse(attributed=False)

    posthog = get_posthog_client()
    posthog.capture(
        user_id,
        "referral_attributed",
        {
            "referrer_user_id": str(owner_id),
            "surface": payload.surface,
            "platform": payload.platform,
            "store": payload.store,
        },
    )
    if source_written:
        # Même propagation que le tag admin (`admin_cohorts`), sinon les filleuls
        # sortent des cohortes d'acquisition PostHog.
        posthog.identify(user_id, properties={"acquisition_source": "referral"})

    logger.info(
        "referral_attributed",
        user_id=str(user_id),
        referrer_user_id=str(owner_id),
        surface=payload.surface,
    )
    return AttributionResponse(attributed=True)
