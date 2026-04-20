"""Jobs pour la génération quotidienne des digests.

Ce module contient les tâches de génération batch des digests pour tous
les utilisateurs actifs. Le job est conçu pour être exécuté via un
scheduler (APScheduler, Celery Beat, etc.) une fois par jour.

Usage:
    # Via CLI ou script
    from app.jobs.digest_generation_job import run_digest_generation
    await run_digest_generation()

    # Via scheduler
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    scheduler.add_job(run_digest_generation, 'cron', hour=8, minute=0)
"""

import asyncio
import datetime
from typing import Any
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session_maker
from app.models.daily_digest import DailyDigest
from app.models.user import UserPreference, UserProfile
from app.services.digest_generation_state_service import (
    mark_failed as state_mark_failed,
)
from app.services.digest_generation_state_service import (
    mark_in_progress as state_mark_in_progress,
)
from app.services.digest_generation_state_service import (
    mark_pending as state_mark_pending,
)
from app.services.digest_generation_state_service import (
    mark_success as state_mark_success,
)
from app.services.digest_selector import (
    DigestSelector,
    DiversityConstraints,
    GlobalTrendingContext,
)
from app.services.editorial.schemas import EditorialPipelineResult
from app.utils.time import today_paris

logger = structlog.get_logger()


class DigestGenerationJob:
    """Job de génération quotidienne des digests.

    Cette classe gère la génération batch des digests pour tous les
    utilisateurs actifs. Elle est conçue pour être exécutée une fois
    par jour, typiquement à 8h du matin (heure de Paris).

    Attributes:
        batch_size: Nombre d'utilisateurs traités par batch (défaut: 100)
        concurrency_limit: Nombre de digests générés en parallèle (défaut: 10)
    """

    def __init__(
        self,
        batch_size: int = 100,
        concurrency_limit: int = 10,
        hours_lookback: int = 48,
    ):
        self.batch_size = batch_size
        self.concurrency_limit = concurrency_limit
        self.hours_lookback = hours_lookback
        self.stats = {
            "total_users": 0,
            "processed": 0,
            "success": 0,
            "failed": 0,
            "skipped": 0,
        }

    async def run(
        self, session: AsyncSession, target_date: datetime.date | None = None
    ) -> dict[str, Any]:
        """Exécute le job de génération pour tous les utilisateurs.

        Args:
            session: Session SQLAlchemy async — used only for queries that
                are safe to share across the batch (reading user list, the
                global editorial context, etc.). Per-user generation opens
                its own fresh session in `_process_batch` so that one user
                failing cannot poison the session for everyone else.
            target_date: Date du digest (défaut: aujourd'hui, Paris TZ)

        Returns:
            Statistiques d'exécution
        """
        if target_date is None:
            target_date = today_paris()

        logger.info(
            "digest_generation_job_started",
            target_date=str(target_date),
            batch_size=self.batch_size,
            concurrency_limit=self.concurrency_limit,
        )

        start_time = datetime.datetime.utcnow()

        try:
            # 1. Récupérer tous les utilisateurs avec un profil
            user_ids = await self._get_active_users(session)
            self.stats["total_users"] = len(user_ids)

            logger.info(
                "digest_generation_users_loaded",
                count=len(user_ids),
                target_date=str(target_date),
            )

            # Retention: prune the rotation-memory table so it doesn't
            # grow forever. 30 days covers any reasonable rotation window
            # plus a month of observability for post-mortem.
            await self._prune_old_highlights(session, target_date)

            # Seed generation-state rows for every (user, variant) as
            # "pending" so observability queries can distinguish "never
            # attempted" from "not yet run".
            # Wrapped in try/except so a missing table never crashes
            # the entire batch — observability must not block generation.
            try:
                for uid in user_ids:
                    for is_ser in (False, True):
                        await state_mark_pending(session, uid, target_date, is_ser)
                await session.commit()
            except Exception:
                logger.exception("digest_generation_state_seeding_failed")
                await session.rollback()

            # 1.5 Build global trending context ONCE for the entire batch
            global_trending_context: GlobalTrendingContext | None = None
            try:
                selector = DigestSelector(session)
                global_trending_context = (
                    await selector._build_global_trending_context()
                )
                logger.info(
                    "digest_generation_global_context_built",
                    trending_count=len(global_trending_context.trending_content_ids),
                    une_count=len(global_trending_context.une_content_ids),
                )
            except Exception as e:
                logger.error("digest_generation_global_context_failed", error=str(e))
                # Graceful degradation: continue without trending

            # 1.6 Pre-compute editorial global context ONCE for the batch,
            # for BOTH variants (pour_vous + serein). Previously only
            # pour_vous was pre-computed, forcing each serene user to do
            # clustering again on-demand. Also, the pool used to build the
            # context came from `user_ids[0]`'s personal candidates — if
            # that user had an empty pool, every downstream user paid the
            # cold-path cost. We now build the pool from a global,
            # user-agnostic candidate query.
            editorial_ctx_pour_vous = None
            editorial_ctx_serein = None
            try:
                from app.services.editorial.pipeline import EditorialPipelineService

                # session_maker : la pipeline ouvre ses propres sessions
                # courtes pendant les 3-5 min de LLM ; évite d'agripper la
                # session batch pour toute la durée. Cf. bug-infinite-load-requests.md P1.
                pipeline = EditorialPipelineService(
                    session, session_maker=async_session_maker
                )
                if pipeline.llm.is_ready and user_ids:
                    global_candidates = await self._get_global_candidates(session)
                    if global_candidates:
                        for mode in ("pour_vous", "serein"):
                            try:
                                # Serein: re-fetch a mode-specific pool
                                # filtered by apply_serein_filter at the SQL
                                # level so the editorial pipeline clusters on
                                # serein-compatible articles only.
                                mode_candidates = (
                                    global_candidates
                                    if mode == "pour_vous"
                                    else await self._get_global_candidates(
                                        session, mode="serein"
                                    )
                                )
                                if not mode_candidates:
                                    logger.warning(
                                        "digest_generation_editorial_empty_pool",
                                        mode=mode,
                                    )
                                    continue
                                ctx = await pipeline.compute_global_context(
                                    mode_candidates, mode=mode
                                )
                                # Retry once if precompute failed
                                if ctx is None:
                                    logger.warning(
                                        "digest_generation_editorial_ctx_retry",
                                        mode=mode,
                                    )
                                    await asyncio.sleep(5)
                                    ctx = await pipeline.compute_global_context(
                                        mode_candidates, mode=mode
                                    )
                                if ctx:
                                    from app.services.digest_selector import (
                                        _set_cached_editorial_ctx,
                                    )

                                    _set_cached_editorial_ctx(target_date, mode, ctx)
                                    if mode == "pour_vous":
                                        editorial_ctx_pour_vous = ctx
                                    else:
                                        editorial_ctx_serein = ctx
                                    logger.info(
                                        "digest_generation_editorial_ctx_precomputed",
                                        mode=mode,
                                        subjects=len(ctx.subjects),
                                    )
                            except Exception as mode_err:
                                logger.error(
                                    "digest_generation_editorial_ctx_mode_failed",
                                    mode=mode,
                                    error=str(mode_err),
                                )
                    else:
                        logger.warning(
                            "digest_generation_editorial_no_global_candidates",
                        )
                    await pipeline.close()
                else:
                    logger.warning("digest_generation_editorial_no_api_key")
            except Exception as e:
                logger.error(
                    "digest_generation_editorial_precompute_failed", error=str(e)
                )

            # 2. Traiter par batches pour limiter la charge mémoire
            for i in range(0, len(user_ids), self.batch_size):
                batch = user_ids[i : i + self.batch_size]
                await self._process_batch(
                    batch,
                    target_date,
                    global_trending_context,
                    editorial_ctx_pour_vous,
                    editorial_ctx_serein,
                )

                logger.debug(
                    "digest_generation_batch_complete",
                    batch_start=i,
                    batch_size=len(batch),
                    processed=self.stats["processed"],
                )

            # 3. Finaliser
            duration = (datetime.datetime.utcnow() - start_time).total_seconds()

            logger.info(
                "digest_generation_job_completed",
                target_date=str(target_date),
                duration_seconds=duration,
                **self.stats,
            )

            # Story 14.1 — operational event to PostHog for ops dashboards.
            # Uses a synthetic distinct_id since this is a system-level event.
            try:
                from app.services.posthog_client import get_posthog_client

                get_posthog_client().capture(
                    user_id="system:digest_job",
                    event="digest_generated",
                    properties={
                        "target_date": str(target_date),
                        "duration_seconds": round(duration, 1),
                        **self.stats,
                    },
                )
            except Exception as exc:  # pragma: no cover — defensive
                logger.warning("digest_generation_posthog_failed", error=str(exc))

            return {
                "success": True,
                "target_date": str(target_date),
                "duration_seconds": duration,
                "stats": self.stats.copy(),
            }

        except Exception as e:
            logger.error(
                "digest_generation_job_failed",
                target_date=str(target_date),
                error=str(e),
            )
            raise

    async def _get_global_candidates(
        self,
        session: AsyncSession,
        mode: str = "pour_vous",
    ) -> list[Any]:
        """Fetch a user-agnostic global candidate pool for editorial context.

        Used to build the LLM subject/cluster context once per batch,
        regardless of whether the first user in the list has a warm pool.
        Falls back to a broad recent-content query so the pipeline never
        cold-paths because of one unlucky user.

        Args:
            session: Async SQLAlchemy session.
            mode: "pour_vous" (default, no filter) or "serein" (apply
                ``apply_serein_filter`` so anxious articles are excluded
                from the clustering pool).
        """
        from datetime import UTC, timedelta

        from sqlalchemy.orm import selectinload

        from app.models.content import Content
        from app.models.source import Source

        # Content.published_at is stored as tz-aware, so the comparison
        # value must also be tz-aware (and utcnow() is deprecated in 3.12).
        cutoff = datetime.datetime.now(UTC) - timedelta(hours=self.hours_lookback)
        # Serein filter references Source.theme so we need an explicit join.
        # The join is harmless for pour_vous (every Content has a Source) but
        # we keep it behind the mode branch to match existing behaviour.
        stmt = select(Content).options(selectinload(Content.source))
        if mode == "serein":
            from app.services.recommendation.filter_presets import apply_serein_filter

            stmt = stmt.join(Source, Content.source_id == Source.id)
            stmt = apply_serein_filter(stmt)
        stmt = (
            stmt.where(Content.published_at >= cutoff)
            .order_by(Content.published_at.desc())
            .limit(200)
        )
        try:
            result = await session.execute(stmt)
            return list(result.scalars().all())
        except Exception as e:
            logger.error(
                "digest_generation_global_candidates_failed",
                mode=mode,
                error=str(e),
            )
            return []

    async def _prune_old_highlights(
        self,
        session: AsyncSession,
        target_date: datetime.date,
    ) -> None:
        """Delete rotation-memory rows older than 30 days.

        `editorial_highlights_history` is append-only (one row per featured
        article per day) and only the last few days are ever read, so
        anything beyond a month is dead weight. Runs at batch start, once
        per day, so the cost is trivial.
        """
        from datetime import timedelta

        from sqlalchemy import delete

        from app.models.editorial_highlights_history import (
            EditorialHighlightsHistory,
        )

        cutoff = target_date - timedelta(days=30)
        try:
            await session.execute(
                delete(EditorialHighlightsHistory).where(
                    EditorialHighlightsHistory.target_date < cutoff
                )
            )
            await session.commit()
        except Exception:
            # Non-fatal: if retention fails the batch can still run.
            logger.exception("editorial_highlights_history_prune_failed")
            await session.rollback()

    async def _get_active_users(self, session: AsyncSession) -> list[UUID]:
        """Récupère la liste des utilisateurs actifs (avec profil).

        Pour l'instant, tous les utilisateurs avec un profil sont considérés
        comme actifs. Dans le futur, on pourrait ajouter une logique de
        "dernière connexion" ou "utilisateur actif".
        """
        stmt = select(UserProfile.user_id).order_by(UserProfile.user_id)
        result = await session.execute(stmt)
        return list(result.scalars().all())

    async def _process_batch(
        self,
        user_ids: list[UUID],
        target_date: datetime.date,
        global_trending_context: GlobalTrendingContext | None = None,
        editorial_ctx_pour_vous=None,
        editorial_ctx_serein=None,
    ) -> None:
        """Traite un batch d'utilisateurs avec limitation de concurrence.

        Each user gets its own fresh SQLAlchemy session (opened inside
        `process_with_limit`) so that a failure on one user cannot poison
        the session shared by the rest of the batch. This fixes a class of
        silent batch failures where a single broken user rolled back the
        session mid-batch and every subsequent user hit
        "PendingRollbackError".

        Retry logic checks coverage for BOTH variants (pour_vous + serein)
        by counting `(user_id, is_serene)` pairs, not just `user_id`s, so
        a user with only the normal variant generated is still retried for
        the missing serein variant.
        """
        semaphore = asyncio.Semaphore(self.concurrency_limit)

        async def process_with_limit(user_id: UUID) -> None:
            # Open a fresh session per user so errors don't poison peers
            async with semaphore, async_session_maker() as user_session:
                try:
                    await self._generate_digest_for_user(
                        user_session,
                        user_id,
                        target_date,
                        global_trending_context,
                        editorial_ctx_pour_vous,
                        editorial_ctx_serein,
                    )
                    await user_session.commit()
                except Exception as e:
                    # Per-user failure is contained here; log and move on
                    await user_session.rollback()
                    logger.exception(
                        "digest_generation_user_session_failed",
                        user_id=str(user_id),
                        target_date=str(target_date),
                        error=str(e),
                    )
                    # Catastrophic user-level failure (e.g. profile load
                    # crashed before the variant loop ran). Record both
                    # variants as failed in a fresh session so rollback
                    # doesn't erase the observability row.
                    try:
                        async with async_session_maker() as state_session:
                            for is_ser in (False, True):
                                await state_mark_failed(
                                    state_session,
                                    user_id,
                                    target_date,
                                    is_ser,
                                    str(e),
                                )
                            await state_session.commit()
                    except Exception:
                        logger.exception(
                            "digest_generation_state_record_failed",
                            user_id=str(user_id),
                        )

        # Premier passage
        tasks = [process_with_limit(uid) for uid in user_ids]
        await asyncio.gather(*tasks, return_exceptions=True)

        async def _missing_pairs() -> list[tuple[UUID, bool]]:
            """Return (user_id, is_serene) pairs missing from daily_digest."""
            expected = {(uid, is_ser) for uid in user_ids for is_ser in (False, True)}
            async with async_session_maker() as ro_session:
                result = await ro_session.execute(
                    select(DailyDigest.user_id, DailyDigest.is_serene).where(
                        DailyDigest.target_date == target_date,
                        DailyDigest.user_id.in_(user_ids),
                    )
                )
                have = {(row.user_id, row.is_serene) for row in result}
            return sorted(expected - have)

        # Retry missing users (cover BOTH variants)
        for attempt in range(1, 3):
            missing = await _missing_pairs()
            if not missing:
                break

            # Dedupe user IDs — the per-user generator handles both variants
            missing_user_ids = sorted({uid for uid, _ in missing})
            backoff_seconds = 2**attempt  # 2s, 4s
            logger.info(
                "digest_generation_retry",
                attempt=attempt,
                missing_count=len(missing),
                missing_users=len(missing_user_ids),
                backoff_seconds=backoff_seconds,
            )
            await asyncio.sleep(backoff_seconds)

            retry_tasks = [process_with_limit(uid) for uid in missing_user_ids]
            await asyncio.gather(*retry_tasks, return_exceptions=True)

        # Final audit log
        final_missing = await _missing_pairs()
        if final_missing:
            logger.error(
                "digest_generation_retry_exhausted",
                permanently_failed=len(final_missing),
                pairs=[
                    {"user_id": str(uid), "is_serene": is_ser}
                    for uid, is_ser in final_missing
                ],
            )

    async def _generate_digest_for_user(
        self,
        session: AsyncSession,
        user_id: UUID,
        target_date: datetime.date,
        global_trending_context: GlobalTrendingContext | None = None,
        editorial_ctx_pour_vous=None,
        editorial_ctx_serein=None,
    ) -> None:
        """Génère les deux digests (normal + serein) pour un utilisateur.

        Args:
            session: Session SQLAlchemy (scoped to this user)
            user_id: ID de l'utilisateur
            target_date: Date du digest
            global_trending_context: Contexte trending pré-calculé
            editorial_ctx_pour_vous: Contexte éditorial pré-calculé (mode pour_vous)
            editorial_ctx_serein: Contexte éditorial pré-calculé (mode serein)
        """
        self.stats["processed"] += 1

        try:
            # Load user profile to get per-user daily article count
            user_profile = await session.scalar(
                select(UserProfile).where(UserProfile.user_id == user_id)
            )
            user_target = (
                user_profile.weekly_goal
                if user_profile and user_profile.weekly_goal
                else DiversityConstraints.TARGET_DIGEST_SIZE
            )

            for is_serene in [False, True]:
                # Mark this specific variant as in-progress. Wrapped in
                # try/except and a best-effort flush so that a state-write
                # failure can never crash the real work. Observability is
                # supposed to surface bugs, not cause them.
                try:
                    await state_mark_in_progress(
                        session, user_id, target_date, is_serene
                    )
                    await session.flush()
                except Exception:
                    logger.exception(
                        "digest_generation_state_mark_in_progress_crashed",
                        user_id=str(user_id),
                        is_serene=is_serene,
                    )

                try:
                    # Vérifier si un digest existe déjà pour cette variante
                    existing = await session.scalar(
                        select(DailyDigest).where(
                            DailyDigest.user_id == user_id,
                            DailyDigest.target_date == target_date,
                            DailyDigest.is_serene == is_serene,
                        )
                    )

                    # All users get editorial format — no per-user branching
                    expected_version = "editorial_v1"

                    stale_digest = None
                    if existing and existing.format_version != expected_version:
                        logger.info(
                            "digest_generation_stale_format_deferred",
                            user_id=str(user_id),
                            target_date=str(target_date),
                            is_serene=is_serene,
                            cached=existing.format_version,
                            expected=expected_version,
                        )
                        stale_digest = existing
                        existing = None

                    if existing:
                        logger.debug(
                            "digest_generation_skipped_exists",
                            user_id=str(user_id),
                            target_date=str(target_date),
                            is_serene=is_serene,
                        )
                        self.stats["skipped"] += 1
                        await state_mark_success(
                            session, user_id, target_date, is_serene
                        )
                        continue

                    digest_mode = "serein" if is_serene else "pour_vous"
                    editorial_ctx = (
                        editorial_ctx_serein if is_serene else editorial_ctx_pour_vous
                    )

                    # Load user's serein preferences (themes + topic exclusions)
                    from app.services.recommendation.filter_presets import (
                        load_serein_preferences,
                    )

                    _serein_prefs = await load_serein_preferences(session, user_id)
                    sensitive_themes: list[str] | None = _serein_prefs.sensitive_themes
                    excluded_topics = _serein_prefs.excluded_topics

                    # Sélectionner les articles via DigestSelector
                    # session_maker propagé → pipeline LLM utilisera des
                    # sessions courtes et commit()ra user_session avant LLM
                    # pour libérer la connexion au pool.
                    selector = DigestSelector(
                        session, session_maker=async_session_maker
                    )
                    digest_items = await selector.select_for_user(
                        user_id=user_id,
                        limit=user_target,
                        hours_lookback=self.hours_lookback,
                        mode=digest_mode,
                        global_trending_context=global_trending_context
                        if not is_serene
                        else None,
                        output_format="editorial",
                        editorial_global_ctx=editorial_ctx,
                        sensitive_themes=sensitive_themes,
                        excluded_topics=excluded_topics,
                    )

                    # Handle editorial pipeline result (Pydantic object, not a list)
                    if isinstance(digest_items, EditorialPipelineResult):
                        from app.services.digest_service import DigestService

                        svc = DigestService(session)
                        digest = await svc._create_digest_record_editorial(
                            user_id,
                            target_date,
                            digest_items,
                            mode=digest_mode,
                            is_serene=is_serene,
                        )
                        if digest:
                            # Delete stale (non-editorial) digest now that
                            # the new editorial_v1 is safely created.
                            if stale_digest:
                                await session.delete(stale_digest)
                                await session.flush()
                            self.stats["success"] += 1
                            await state_mark_success(
                                session, user_id, target_date, is_serene
                            )
                            logger.debug(
                                "digest_generation_editorial_success",
                                user_id=str(user_id),
                                target_date=str(target_date),
                                is_serene=is_serene,
                            )
                        else:
                            self.stats["failed"] += 1
                            await state_mark_failed(
                                session,
                                user_id,
                                target_date,
                                is_serene,
                                "editorial record creation returned None",
                            )
                        continue

                    if not digest_items:
                        logger.warning(
                            "digest_generation_empty",
                            user_id=str(user_id),
                            target_date=str(target_date),
                            is_serene=is_serene,
                        )
                        self.stats["failed"] += 1
                        await state_mark_failed(
                            session,
                            user_id,
                            target_date,
                            is_serene,
                            "selector returned empty digest",
                        )
                        continue

                    # Unexpected return type — editorial should always
                    # return EditorialPipelineResult or None/empty.
                    logger.error(
                        "digest_generation_unexpected_return_type",
                        user_id=str(user_id),
                        target_date=str(target_date),
                        is_serene=is_serene,
                        type=type(digest_items).__name__,
                    )
                    self.stats["failed"] += 1
                    await state_mark_failed(
                        session,
                        user_id,
                        target_date,
                        is_serene,
                        f"unexpected return type: {type(digest_items).__name__}",
                    )
                except Exception as variant_err:
                    # Record the variant error but keep going so the other
                    # variant still has a chance to generate.
                    logger.exception(
                        "digest_generation_variant_failed",
                        user_id=str(user_id),
                        target_date=str(target_date),
                        is_serene=is_serene,
                    )
                    self.stats["failed"] += 1
                    # Record the per-variant failure via a fresh session
                    # so this user's main session can continue with the
                    # other variant cleanly.
                    try:
                        async with async_session_maker() as variant_state_session:
                            await state_mark_failed(
                                variant_state_session,
                                user_id,
                                target_date,
                                is_serene,
                                str(variant_err),
                            )
                            await variant_state_session.commit()
                    except Exception:
                        logger.exception(
                            "digest_generation_variant_state_record_failed",
                            user_id=str(user_id),
                            is_serene=is_serene,
                        )

        except Exception as e:
            logger.error(
                "digest_generation_user_failed",
                user_id=str(user_id),
                target_date=str(target_date),
                error=str(e),
            )
            self.stats["failed"] += 1
            # Re-raise so the caller in _process_batch can record the
            # failure in a fresh session after rolling this one back.
            raise


# Fonction principale pour l'export


async def run_digest_generation(
    target_date: datetime.date | None = None,
    batch_size: int = 100,
    concurrency_limit: int = 10,
) -> dict[str, Any]:
    """Fonction principale pour exécuter la génération des digests.

    Cette fonction est le point d'entrée pour le job de génération.
    Elle peut être appelée:
    - Via un script CLI
    - Via un scheduler (APScheduler, Celery Beat)
    - Directement depuis le code

    Args:
        target_date: Date du digest (défaut: aujourd'hui)
        batch_size: Nombre d'utilisateurs par batch (défaut: 100)
        concurrency_limit: Limite de concurrence (défaut: 10)

    Returns:
        Statistiques d'exécution

    Example:
        >>> result = await run_digest_generation()
        >>> print(f"Generated {result['stats']['success']} digests")

        >>> # Pour une date spécifique
        >>> from datetime import date
        >>> result = await run_digest_generation(target_date=date(2024, 1, 15))
    """
    from app.services.generation_state import (
        mark_generation_finished,
        mark_generation_started,
    )

    job = DigestGenerationJob(
        batch_size=batch_size, concurrency_limit=concurrency_limit
    )

    mark_generation_started()

    # Obtenir une session depuis le contexte
    async with async_session_maker() as session:
        try:
            result = await job.run(session, target_date)
            await session.commit()
            return result
        except Exception:
            await session.rollback()
            raise
        finally:
            mark_generation_finished()


# Fonction pour génération manuelle d'un seul utilisateur


async def generate_digest_for_user(
    user_id: UUID, target_date: datetime.date | None = None, force: bool = False
) -> DailyDigest | None:
    """Génère le digest pour un utilisateur spécifique (mode on-demand).

    Cette fonction permet de générer un digest pour un utilisateur
    spécifique, par exemple pour du testing ou pour du lazy-loading.

    Args:
        user_id: ID de l'utilisateur
        target_date: Date du digest (défaut: aujourd'hui)
        force: Si True, régénère même si un digest existe (défaut: False)

    Returns:
        Le DailyDigest créé, ou None si erreur

    Example:
        >>> from uuid import UUID
        >>> digest = await generate_digest_for_user(
        ...     user_id=UUID("..."),
        ...     force=True
        ... )
    """
    if target_date is None:
        target_date = today_paris()

    async with async_session_maker() as session:
        try:
            # Vérifier l'existant
            if not force:
                existing = await session.scalar(
                    select(DailyDigest).where(
                        DailyDigest.user_id == user_id,
                        DailyDigest.target_date == target_date,
                    )
                )
                if existing:
                    logger.info(
                        "digest_on_demand_skipped_exists",
                        user_id=str(user_id),
                        target_date=str(target_date),
                    )
                    return existing

            # Load user's serein preferences (themes + topic exclusions)
            from app.services.recommendation.filter_presets import (
                load_serein_preferences,
            )

            _serein_prefs = await load_serein_preferences(session, user_id)
            sensitive_themes: list[str] | None = _serein_prefs.sensitive_themes
            excluded_topics = _serein_prefs.excluded_topics

            # Générer — session_maker pour que la pipeline LLM (si format
            # éditorial activé) ouvre des sessions courtes et n'agrippe pas
            # la session de regen. Cf. bug-infinite-load-requests.md (P1).
            selector = DigestSelector(session, session_maker=async_session_maker)
            digest_items = await selector.select_for_user(
                user_id=user_id,
                limit=DiversityConstraints.TARGET_DIGEST_SIZE,
                hours_lookback=48,
                sensitive_themes=sensitive_themes,
                excluded_topics=excluded_topics,
            )

            if not digest_items:
                logger.warning(
                    "digest_on_demand_empty",
                    user_id=str(user_id),
                    target_date=str(target_date),
                )
                return None

            # Construire les items
            items = []
            for item in digest_items:
                items.append(
                    {
                        "content_id": str(item.content.id),
                        "rank": item.rank,
                        "reason": item.reason,
                        "score": item.score,
                        "source_id": str(item.content.source_id)
                        if item.content.source_id
                        else None,
                        "title": item.content.title,
                        "published_at": item.content.published_at.isoformat()
                        if item.content.published_at
                        else None,
                    }
                )

            # Supprimer l'ancien si force=True
            if force:
                await session.execute(
                    select(DailyDigest).where(
                        DailyDigest.user_id == user_id,
                        DailyDigest.target_date == target_date,
                    )
                )

            # Créer le nouveau digest
            digest = DailyDigest(
                user_id=user_id,
                target_date=target_date,
                items=items,
                generated_at=datetime.datetime.utcnow(),
            )

            session.add(digest)
            await session.commit()

            logger.info(
                "digest_on_demand_success",
                user_id=str(user_id),
                target_date=str(target_date),
                article_count=len(items),
            )

            return digest

        except Exception as e:
            await session.rollback()
            logger.error(
                "digest_on_demand_failed",
                user_id=str(user_id),
                target_date=str(target_date),
                error=str(e),
            )
            return None
