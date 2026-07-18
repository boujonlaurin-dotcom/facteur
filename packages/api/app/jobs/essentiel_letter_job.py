"""Job nocturne de pré-génération des lettres Essentiel (Story 9.6).

Tourne à 08h00 Paris, après le digest cron (07h30) et avant le watchdog
(08h15). Population v1 : tous les UserProfile (parité
`DigestGenerationJob._get_active_users`), variante `pour_vous` uniquement —
la variante serein est générée on-demand par le router et cachée.

Leçons pool (PYTHON-5M/5G) :
- une session courte `safe_async_session` par étape, jamais de session
  ouverte pendant l'appel LLM ;
- `Semaphore(4)` pour borner la concurrence sur le pool partagé nocturne.

Idempotent : skip si la ligne `(user, date, false)` existe déjà ; le stockage
est un `ON CONFLICT DO NOTHING` (course avec l'on-demand du router).

Population partagée avec le digest via `get_active_user_ids`.
"""

import asyncio
from datetime import date

import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.jobs.digest_generation_job import get_active_user_ids
from app.models.essentiel_letter import EssentielLetterRow
from app.services.digest_service import read_digest_or_fallback
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.essentiel_letter_service import (
    generate_letter,
    purge_old_letters,
    store_letter,
)
from app.services.essentiel_service import (
    ESSENTIEL_MIN_ARTICLES,
    build_essentiel_response_with_supplements,
    fetch_user_essentiel_context,
)
from app.utils.time import today_paris

logger = structlog.get_logger()

LETTER_JOB_CONCURRENCY = 4
LETTER_RETENTION_DAYS = 30


async def run_essentiel_letter_generation(
    target_date: date | None = None,
    concurrency: int = LETTER_JOB_CONCURRENCY,
) -> dict:
    """Génère la lettre du jour pour tous les utilisateurs actifs."""
    target = target_date or today_paris()
    stats = {"total_users": 0, "generated": 0, "skipped": 0, "failed": 0}

    # Purge de rétention + inventaire, dans une session courte dédiée.
    async with safe_async_session() as session:
        purged = await purge_old_letters(session, older_than_days=LETTER_RETENTION_DAYS)
        user_ids = await get_active_user_ids(session)
        existing = set(
            (
                await session.execute(
                    select(EssentielLetterRow.user_id).where(
                        EssentielLetterRow.target_date == target,
                        EssentielLetterRow.is_serene.is_(False),
                    )
                )
            )
            .scalars()
            .all()
        )

    stats["total_users"] = len(user_ids)
    todo = [uid for uid in user_ids if uid not in existing]
    stats["skipped"] += len(user_ids) - len(todo)

    llm = EditorialLLMClient()
    semaphore = asyncio.Semaphore(concurrency)

    async def process_user(user_id) -> str:
        async with semaphore:
            # Session courte 1 : lire le digest et construire les picks.
            async with safe_async_session() as session:
                digest = await read_digest_or_fallback(
                    session, user_id, target, is_serene=False
                )
                if digest is None or digest.is_stale_fallback:
                    return "skipped"
                user_context = await fetch_user_essentiel_context(session, user_id)
                response = await build_essentiel_response_with_supplements(
                    session,
                    user_id,
                    digest,
                    user_context=user_context,
                    is_serene=False,
                )
            if len(response.articles) < ESSENTIEL_MIN_ARTICLES:
                return "skipped"

            # Appel LLM hors de toute session DB.
            letter = await generate_letter(
                response.articles,
                followed_themes=user_context.followed_themes_by_weight(),
                is_serene=False,
                client=llm,
            )
            if letter is None:
                return "failed"

            # Session courte 2 : stockage idempotent.
            async with safe_async_session() as session:
                await store_letter(
                    session,
                    user_id=user_id,
                    target_date=target,
                    is_serene=False,
                    letter=letter,
                    articles=response.articles,
                )
            return "generated"

    try:
        results = await asyncio.gather(
            *(process_user(uid) for uid in todo), return_exceptions=True
        )
    finally:
        await llm.close()

    for user_id, outcome in zip(todo, results, strict=True):
        if isinstance(outcome, BaseException):
            stats["failed"] += 1
            logger.error(
                "essentiel_letter_job_user_failed",
                user_id=str(user_id),
                error=str(outcome),
            )
        else:
            stats[outcome] += 1

    logger.info(
        "essentiel_letter_job_done",
        target_date=str(target),
        purged=purged,
        **stats,
    )
    return stats
