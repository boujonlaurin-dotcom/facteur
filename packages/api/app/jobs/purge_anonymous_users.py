"""Daily purge of abandoned anonymous auth users.

Story 31.1 (onboarding sans compte) ouvre une session **anonyme** Supabase dès
le premier lancement : `auth.users` gagne donc une ligne par install, y compris
pour les installs qui n'iront jamais au bout du questionnaire. Ce job récupère
ce déchet.

Un anonyme est purgeable quand il réunit les trois conditions :

- `is_anonymous = true` — Supabase ne le repasse à `false` qu'à la confirmation
  de l'adresse, donc un compte réellement créé n'est jamais candidat ;
- son onboarding n'est pas terminé : soit aucune ligne `user_profiles`, soit une
  ligne `onboarding_completed = false`. Le profil peut exister très tôt (les
  endpoints d'onboarding appellent `get_or_create_profile` pour satisfaire les
  FK de `user_subtopics` / `user_interests`) : sa seule présence ne prouve donc
  rien, seul `onboarding_completed` le fait ;
- aucune activité depuis plus de PURGE_AFTER_DAYS jours.

La suppression de l'utilisateur passe par l'Admin API Supabase et non par un
`DELETE` SQL : le rôle applicatif n'a qu'un droit de lecture sur le schéma
`auth`, et l'Admin API prend en charge les tables liées (`auth.identities`,
`auth.sessions`, `auth.refresh_tokens`). Le profil applicatif, lui, est supprimé
en SQL — `ON DELETE CASCADE` emporte intérêts, sous-sujets et préférences, comme
dans `purge_deleted_users`. Sans `supabase_service_role_key` configurée le job
est un no-op explicite plutôt qu'une erreur.
"""

import asyncio
from uuid import UUID

import certifi
import httpx
import structlog
from sqlalchemy import delete, text

from app.config import get_settings
from app.database import safe_async_session
from app.models.user import UserProfile

logger = structlog.get_logger()

PURGE_AFTER_DAYS = 30

# Plafond par exécution : le job tourne tous les jours, un pic d'installs se
# résorbe donc en quelques nuits sans jamais tenir l'Admin API des minutes.
MAX_DELETIONS_PER_RUN = 500

_CANDIDATES_SQL = text(
    """
    SELECT u.id::text
    FROM auth.users AS u
    LEFT JOIN user_profiles AS p ON p.user_id = u.id
    WHERE u.is_anonymous IS TRUE
      AND (p.user_id IS NULL OR p.onboarding_completed IS NOT TRUE)
      AND COALESCE(u.last_sign_in_at, u.created_at)
          < now() - make_interval(days => :days)
    ORDER BY COALESCE(u.last_sign_in_at, u.created_at)
    LIMIT :limit
    """
)


async def _delete_auth_user(client: httpx.AsyncClient, user_id: str) -> bool:
    """Supprime un user via l'Admin API. `True` si supprimé (ou déjà absent)."""
    settings = get_settings()
    resp = await client.delete(
        f"{settings.supabase_url}/auth/v1/admin/users/{user_id}",
        headers={
            "Authorization": f"Bearer {settings.supabase_service_role_key}",
            "apikey": settings.supabase_service_role_key,
        },
    )
    if resp.status_code in (200, 204, 404):
        return True
    logger.warning(
        "purge_anonymous_users_delete_failed",
        user_id=user_id,
        status_code=resp.status_code,
    )
    return False


async def purge_anonymous_users() -> dict:
    """Supprime les sessions anonymes abandonnées.

    Returns a stats dict suitable for logging/tests:
        {"candidates": int, "deleted_count": int, "skipped_reason": str | None}
    """
    settings = get_settings()
    if not (settings.supabase_url and settings.supabase_service_role_key):
        logger.warning(
            "purge_anonymous_users_skipped", reason="missing_admin_credentials"
        )
        return {
            "candidates": 0,
            "deleted_count": 0,
            "skipped_reason": "missing_admin_credentials",
        }

    async with safe_async_session() as session:
        result = await session.execute(
            _CANDIDATES_SQL,
            {"days": PURGE_AFTER_DAYS, "limit": MAX_DELETIONS_PER_RUN},
        )
        user_ids = [row[0] for row in result.fetchall()]

    deleted: list[str] = []
    if user_ids:
        # Les suppressions sont indépendantes : on les borne à quelques appels
        # Admin API concurrents plutôt que de sérialiser jusqu'à 500 aller-retours
        # (le volume que ce job existe précisément pour résorber).
        semaphore = asyncio.Semaphore(8)
        async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:

            async def _delete_guarded(user_id: str) -> str | None:
                async with semaphore:
                    return user_id if await _delete_auth_user(client, user_id) else None

            results = await asyncio.gather(
                *(_delete_guarded(user_id) for user_id in user_ids)
            )
        deleted = [user_id for user_id in results if user_id is not None]

    # Profils applicatifs des users réellement supprimés (CASCADE emporte
    # intérêts, sous-sujets, préférences). Fait après l'Admin API : un échec de
    # suppression côté auth doit laisser le profil en place, pas orphelin.
    if deleted:
        async with safe_async_session() as session:
            await session.execute(
                delete(UserProfile).where(
                    UserProfile.user_id.in_([UUID(uid) for uid in deleted])
                )
            )
            await session.commit()

    deleted_count = len(deleted)

    logger.info(
        "purge_anonymous_users_completed",
        candidates=len(user_ids),
        deleted_count=deleted_count,
        purge_after_days=PURGE_AFTER_DAYS,
        capped=len(user_ids) == MAX_DELETIONS_PER_RUN,
    )
    return {
        "candidates": len(user_ids),
        "deleted_count": deleted_count,
        "skipped_reason": None,
    }
