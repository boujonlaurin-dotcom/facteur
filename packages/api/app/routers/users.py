"""Routes utilisateur."""

import hashlib
import logging
import time
from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

import certifi
import httpx
import sentry_sdk
import structlog
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Response, status
from pydantic import BaseModel, field_validator
from sqlalchemy import func, text, update
from sqlalchemy import select as sa_select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings

logger = logging.getLogger(__name__)
_perf_logger = structlog.get_logger("streak_perf")

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.user import UserProfile
from app.schemas.streak import StreakResponse
from app.schemas.user import (
    AlgorithmProfileResponse,
    OnboardingRequest,
    OnboardingResponse,
    UserInterestResponse,
    UserPreferenceResponse,
    UserProfileResponse,
    UserProfileUpdate,
    UserStatsResponse,
)
from app.services.digest_service import schedule_initial_digest_generation
from app.services.feed_cache import FEED_CACHE
from app.services.streak_service import StreakService
from app.services.user_service import ALLOWED_PREFERENCE_KEYS, UserService

router = APIRouter()


@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserProfileResponse:
    """Récupérer le profil utilisateur."""
    service = UserService(db)
    profile = await service.get_profile(user_id)

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )

    return UserProfileResponse.model_validate(profile)


@router.put("/profile", response_model=UserProfileResponse)
async def update_profile(
    data: UserProfileUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserProfileResponse:
    """Mettre à jour le profil utilisateur."""
    service = UserService(db)
    profile = await service.update_profile(user_id, data)

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )

    return UserProfileResponse.model_validate(profile)


@router.post("/onboarding", response_model=OnboardingResponse)
async def save_onboarding(
    data: OnboardingRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> OnboardingResponse:
    """Sauvegarder les réponses de l'onboarding.

    Pré-génère le digest des deux variantes en tâche de fond : l'animation de
    conclusion côté mobile dure ~10s, ce qui laisse au scheduler le temps de
    produire un digest avant le premier `GET /digest/both`. Sans ce trigger,
    un nouveau user qui termine l'onboarding hors fenêtre batch (6h Paris)
    attend le lendemain pour voir son Essentiel.
    """
    service = UserService(db)
    try:
        result = await service.save_onboarding(user_id, data.answers)
        await db.commit()
        FEED_CACHE.invalidate(UUID(user_id))
    except Exception as e:
        logger.error(f"Onboarding save failed for user {user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save onboarding data. Please retry.",
        )

    # Schedule digest pre-generation AFTER response is sent and the onboarding
    # transaction is committed (BackgroundTasks guarantees post-commit timing
    # via get_db's yield/commit pattern). The background regen helper opens its
    # own session so it sees the freshly committed UserSource rows.
    background_tasks.add_task(schedule_initial_digest_generation, UUID(user_id))

    try:
        return OnboardingResponse.model_validate(result)
    except Exception as e:
        logger.error(
            f"Onboarding response serialization failed for user {user_id}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Onboarding saved but response serialization failed.",
        )


@router.get("/preferences", response_model=list[UserPreferenceResponse])
async def get_preferences(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[UserPreferenceResponse]:
    """Récupérer les préférences utilisateur."""
    service = UserService(db)
    preferences = await service.get_preferences(user_id)

    return [UserPreferenceResponse.model_validate(p) for p in preferences]


@router.get("/interests", response_model=list[UserInterestResponse])
async def get_interests(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[UserInterestResponse]:
    """Récupérer les intérêts utilisateur."""
    service = UserService(db)
    interests = await service.get_interests(user_id)

    return [UserInterestResponse.model_validate(i) for i in interests]


@router.get("/algorithm-profile", response_model=AlgorithmProfileResponse)
async def get_algorithm_profile(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> AlgorithmProfileResponse:
    """Profil algorithmique : poids appris par thème/subtopic + affinités sources."""
    from app.models.user import UserInterest, UserSubtopic
    from app.services.recommendation_service import RecommendationService

    # Interest weights
    interest_rows = (
        await db.execute(
            sa_select(UserInterest.interest_slug, UserInterest.weight).where(
                UserInterest.user_id == user_id
            )
        )
    ).all()
    interest_weights = {row.interest_slug: row.weight for row in interest_rows}

    # Subtopic weights
    subtopic_rows = (
        await db.execute(
            sa_select(UserSubtopic.topic_slug, UserSubtopic.weight).where(
                UserSubtopic.user_id == user_id
            )
        )
    ).all()
    subtopic_weights = {row.topic_slug: row.weight for row in subtopic_rows}

    # Source affinities (reuse recommendation service logic)
    reco_service = RecommendationService(db)
    affinity_map = await reco_service._compute_source_affinity(user_id)
    source_affinities = {str(sid): score for sid, score in affinity_map.items()}

    return AlgorithmProfileResponse(
        interest_weights=interest_weights,
        subtopic_weights=subtopic_weights,
        source_affinities=source_affinities,
    )


@router.post("/interests/{slug}/reset")
async def reset_interest_weight(
    slug: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    """Remet le poids appris d'un thème à 1.0 (neutre)."""
    from sqlalchemy import update

    from app.models.user import UserInterest

    result = await db.execute(
        update(UserInterest)
        .where(UserInterest.user_id == user_id, UserInterest.interest_slug == slug)
        .values(weight=1.0)
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Interest not found")
    FEED_CACHE.invalidate(UUID(user_id))
    return {"success": True}


@router.post("/subtopics/{slug}/reset")
async def reset_subtopic_weight(
    slug: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    """Remet le poids appris d'un subtopic à 1.0 (neutre)."""
    from sqlalchemy import update

    from app.models.user import UserSubtopic

    result = await db.execute(
        update(UserSubtopic)
        .where(UserSubtopic.user_id == user_id, UserSubtopic.topic_slug == slug)
        .values(weight=1.0)
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Subtopic not found")
    FEED_CACHE.invalidate(UUID(user_id))
    return {"success": True}


@router.get("/stats", response_model=UserStatsResponse)
async def get_stats(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserStatsResponse:
    """Récupérer les statistiques utilisateur."""
    service = UserService(db)
    stats = await service.get_stats(user_id)

    return stats


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> StreakResponse:
    """Récupérer le streak actuel."""
    t0 = time.monotonic()
    service = StreakService(db)
    result = await service.get_streak(user_id)
    _perf_logger.info(
        "streak_handler_duration",
        duration_ms=round((time.monotonic() - t0) * 1000, 2),
        user_id=user_id,
    )
    return result


class PreferenceUpdateRequest(BaseModel):
    """Requête de mise à jour de préférence clé-valeur."""

    key: str
    value: str

    @field_validator("key")
    @classmethod
    def _validate_key(cls, v: str) -> str:
        if v not in ALLOWED_PREFERENCE_KEYS:
            raise ValueError(f"preference_key '{v}' is not allowed")
        return v


class PreferenceUpdateResponse(BaseModel):
    """Réponse de mise à jour de préférence."""

    success: bool
    key: str
    value: str


@router.put("/preferences", response_model=PreferenceUpdateResponse)
async def update_preference(
    data: PreferenceUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> PreferenceUpdateResponse:
    """Mettre à jour une préférence utilisateur (upsert clé-valeur)."""
    service = UserService(db)
    await service.upsert_preference(user_id, data.key, data.value)
    return PreferenceUpdateResponse(success=True, key=data.key, value=data.value)


class TopThemeResponse(BaseModel):
    """Un slot de la Tournée du jour.

    Pour `kind="veille"`, `interest_slug` est le `theme_id` (slug parent) de la
    `VeilleConfig` et `veille_config_id` est rempli — le mobile dispatche alors
    vers `/api/veille/feed` au lieu de `/api/feed?theme=`.
    """

    interest_slug: str
    weight: float
    article_count: int = 0
    kind: Literal["theme", "veille"] = "theme"
    veille_config_id: UUID | None = None


@router.get("/top-themes", response_model=list[TopThemeResponse])
async def get_top_themes(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[TopThemeResponse]:
    """Retourne les thèmes de la « Tournée du jour ».

    Story 22.1 — la table `user_favorite_interests` (ordre user) prime ; les
    Sujets favoris (custom topics) sont projetés sur leur `slug_parent` pour
    rester compatibles avec le format `TopThemeResponse` (rétrocompat mobile).
    Story 22.2 — le user peut avoir > 3 favoris, mais seuls les `FAVORITE_CAP`
    premiers (par `position` ASC) sont sélectionnés pour la Tournée du jour.
    Les thèmes sans article récent (14 derniers jours) sont exclus du fallback.
    """
    from app.constants import FAVORITE_CAP
    from app.models.content import Content
    from app.models.user_favorites import UserFavoriteInterest
    from app.models.user_topic_profile import UserTopicProfile
    from app.models.veille import VeilleConfig, VeilleStatus

    user_uuid = UUID(user_id)

    fav_rows = (
        (
            await db.execute(
                sa_select(UserFavoriteInterest)
                .where(UserFavoriteInterest.user_id == user_uuid)
                .order_by(UserFavoriteInterest.position)
            )
        )
        .scalars()
        .all()
    )

    if fav_rows:
        # Résolution Theme/Sujet → slug. Pour les Sujets, on projette sur
        # `slug_parent` (ex: custom_topic "Donald Trump" → slug "international").
        # Pour Veille, on hydrate la VeilleConfig pour récupérer son `theme_id`
        # et on n'expose le slot que si la config est encore active — un favori
        # orphelin (cfg archivée hors transaction) est skippé silencieusement.
        custom_topic_ids = [
            row.custom_topic_id for row in fav_rows if row.custom_topic_id
        ]
        topic_slug_by_id: dict[UUID, str] = {}
        if custom_topic_ids:
            topic_rows = (
                await db.execute(
                    sa_select(UserTopicProfile.id, UserTopicProfile.slug_parent).where(
                        UserTopicProfile.id.in_(custom_topic_ids)
                    )
                )
            ).all()
            topic_slug_by_id = {row[0]: row[1] for row in topic_rows}

        veille_cfg_ids = [
            row.veille_config_id for row in fav_rows if row.veille_config_id
        ]
        veille_by_id: dict[UUID, VeilleConfig] = {}
        if veille_cfg_ids:
            veille_rows = (
                (
                    await db.execute(
                        sa_select(VeilleConfig).where(
                            VeilleConfig.id.in_(veille_cfg_ids),
                            VeilleConfig.status == VeilleStatus.ACTIVE.value,
                        )
                    )
                )
                .scalars()
                .all()
            )
            veille_by_id = {cfg.id: cfg for cfg in veille_rows}

        # Dedup key = (kind, slug) : un favori veille et un favori thème
        # partageant le même slug parent coexistent (sources distinctes).
        seen: set[tuple[str, str]] = set()
        out: list[TopThemeResponse] = []
        for row in fav_rows:
            if row.veille_config_id:
                cfg = veille_by_id.get(row.veille_config_id)
                if cfg is None:
                    continue
                key = ("veille", cfg.theme_id)
                if key in seen:
                    continue
                seen.add(key)
                out.append(
                    TopThemeResponse(
                        interest_slug=cfg.theme_id,
                        weight=1.5,
                        article_count=0,
                        kind="veille",
                        veille_config_id=cfg.id,
                    )
                )
                continue
            slug = (
                row.interest_slug
                if row.interest_slug
                else topic_slug_by_id.get(row.custom_topic_id)
            )
            if slug is None:
                continue
            key = ("theme", slug)
            if key in seen:
                continue
            seen.add(key)
            out.append(
                TopThemeResponse(interest_slug=slug, weight=1.5, article_count=0)
            )
        return out[:FAVORITE_CAP]

    # Fallback : sort weight desc, exclure les thèmes sans article 14j.
    service = UserService(db)
    interests = await service.get_interests(user_id)

    if not interests:
        return []

    cutoff = datetime.now(UTC) - timedelta(days=14)
    slugs = [i.interest_slug for i in interests]
    count_rows = (
        await db.execute(
            sa_select(Content.theme, func.count(Content.id))
            .where(Content.theme.in_(slugs), Content.published_at >= cutoff)
            .group_by(Content.theme)
        )
    ).all()
    theme_counts = {row[0]: row[1] for row in count_rows}

    themes = sorted(interests, key=lambda i: i.weight, reverse=True)
    return [
        TopThemeResponse(
            interest_slug=i.interest_slug,
            weight=i.weight,
            article_count=theme_counts.get(i.interest_slug, 0),
        )
        for i in themes
        if theme_counts.get(i.interest_slug, 0) > 0
    ][:FAVORITE_CAP]


# ─── Account deletion ────────────────────────────────────────────────────────
# App Store Guideline 5.1.1(v) + Play Store account deletion policy.
# The flow: anonymise the user_profiles row + drop the auth.users row via the
# Supabase Admin API, then a daily cron purges soft-deleted rows after 30 days
# (cf. app/jobs/purge_deleted_users.py).


async def _fetch_auth_email(db: AsyncSession, user_id: str) -> str | None:
    """Read the user email from auth.users (Supabase-managed schema).

    Extracted as a module-level helper so tests can monkeypatch it without
    needing the auth schema in the SQLAlchemy test fixture (the test DB only
    creates tables from Base.metadata, which excludes auth.*).
    """
    row = (
        await db.execute(
            text("SELECT email FROM auth.users WHERE id = :uid"),
            {"uid": user_id},
        )
    ).first()
    return row[0] if row else None


async def _delete_supabase_auth_user(user_id: str) -> None:
    """Call Supabase Admin REST API to remove auth.users row (idempotent).

    Failures are logged but never raised: the local `deleted_at` flag is
    already set, so the cron will purge the row in 30 days regardless. We
    must not return 5xx to a user who has just deleted their account.
    """
    settings = get_settings()
    if not (settings.supabase_url and settings.supabase_service_role_key):
        logger.warning("delete_user_supabase_admin_skipped_missing_config")
        return

    url = f"{settings.supabase_url}/auth/v1/admin/users/{user_id}"
    headers = {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
    }
    try:
        async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:
            resp = await client.delete(url, headers=headers)
        if resp.status_code in (200, 204):
            return
        if resp.status_code == 404:
            # Already gone — treat as success for idempotence.
            logger.info("delete_user_supabase_admin_already_deleted", user_id=user_id)
            return
        logger.warning(
            "delete_user_supabase_admin_unexpected_status",
            user_id=user_id,
            status=resp.status_code,
            body=resp.text[:500],
        )
        sentry_sdk.capture_message(
            "delete_user_supabase_admin_unexpected_status", level="warning"
        )
    except Exception as exc:
        logger.warning(
            "delete_user_supabase_admin_exception", user_id=user_id, error=str(exc)
        )
        sentry_sdk.capture_exception(exc)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Soft-delete the current account (App Store 5.1.1(v) compliance).

    - Anonymises the user_profiles row (display_name/age_range/gender → NULL).
    - Stores SHA256(email) for legal/support traceability post-purge.
    - Removes the auth.users row via Supabase Admin API → blocks reconnection.
    - Idempotent: a 2nd call on an already soft-deleted account returns 204.
    - Cron purge after 30 days (cf. app/jobs/purge_deleted_users.py).
    """
    profile = (
        await db.execute(
            sa_select(UserProfile).where(UserProfile.user_id == UUID(user_id))
        )
    ).scalar_one_or_none()

    if profile is None:
        # No profile yet (user finished signup but skipped onboarding).
        # We still call the Supabase admin endpoint to drop auth.users so
        # reconnection is blocked.
        await _delete_supabase_auth_user(user_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    if profile.deleted_at is not None:
        # Idempotent: already soft-deleted, nothing more to do.
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    email = await _fetch_auth_email(db, user_id)
    email_hash = hashlib.sha256(email.encode("utf-8")).hexdigest() if email else None

    await db.execute(
        update(UserProfile)
        .where(UserProfile.user_id == UUID(user_id))
        .values(
            display_name=None,
            age_range=None,
            gender=None,
            email_hash=email_hash,
            deleted_at=func.now(),
        )
    )
    await db.commit()

    await _delete_supabase_auth_user(user_id)

    FEED_CACHE.invalidate(UUID(user_id))
    logger.info("user_account_soft_deleted", user_id=user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
