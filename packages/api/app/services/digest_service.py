"""Service layer for digest operations (Epic 10).

Provides business logic for:
- Retrieving or generating today's digest
- Tracking user actions (read/save/not_interested)
- Recording digest completions and updating streaks
- Integration with Personalization system for 'not_interested' actions

Safe reuse patterns:
- Uses existing DigestSelector service (from 01-02)
- Uses existing Personalization service for mutes
- Uses existing StreakService for gamification updates
"""

import asyncio
import hashlib
import random
import time
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import structlog
import yaml
from sqlalchemy import and_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.models.enums import ContentStatus
from app.models.user import UserStreak
from app.models.user_personalization import UserPersonalization
from app.schemas.digest import (
    CoupDeCoeurResponse,
    DigestAction,
    DigestItem,
    DigestRecommendationReason,
    DigestResponse,
    DigestScoreBreakdown,
    DigestTopic,
    DigestTopicArticle,
    PepiteResponse,
    QuoteResponse,
)
from app.services.digest_selector import DigestSelector
from app.services.editorial.schemas import EditorialPipelineResult
from app.services.streak_service import StreakService
from app.services.topic_selector import ScoredArticle, TopicGroup
from app.utils.time import today_paris

logger = structlog.get_logger()


# In-memory rate limit for the stale-fallback background regen.
# Key: (user_id, target_date, is_serene). Value: monotonic timestamp of last spawn.
# Prevents spawning N parallel regenerations when the same user opens the app
# repeatedly while yesterday's fallback is being served.
_BG_REGEN_RATE_LIMIT: dict[tuple[UUID, date, bool], float] = {}
_BG_REGEN_COOLDOWN_S = 60.0  # 1 spawn per minute per (user, date, variant)

# Strong references to in-flight background regen tasks. asyncio only holds
# a WEAK reference to tasks spawned by create_task(), so without this set
# the GC can cancel the regeneration mid-execution — which would defeat the
# whole "stop serving stale content silently" fix. Tasks auto-remove
# themselves via add_done_callback.
_BG_REGEN_TASKS: set["asyncio.Task[None]"] = set()


def _schedule_background_regen(
    user_id: UUID,
    target_date: date,
    is_serene: bool,
) -> None:
    """Schedule a background regeneration of the digest for one user.

    Used by the yesterday-fallback path so that serving stale content also
    triggers the real generation. Each task opens its own AsyncSession so it
    survives the request session being closed.

    Rate-limited per (user, date, is_serene) to a single spawn per minute.
    The spawned task is pinned in `_BG_REGEN_TASKS` so the event loop's weak
    reference doesn't let it be garbage-collected mid-run.
    """
    import time as _time

    key = (user_id, target_date, is_serene)
    now_mono = _time.monotonic()
    last = _BG_REGEN_RATE_LIMIT.get(key)
    if last is not None and (now_mono - last) < _BG_REGEN_COOLDOWN_S:
        logger.info(
            "digest_background_regen_rate_limited",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
            elapsed_s=round(now_mono - last, 1),
        )
        return
    _BG_REGEN_RATE_LIMIT[key] = now_mono

    # Periodic GC: remove entries older than 2x cooldown to prevent unbounded growth
    if len(_BG_REGEN_RATE_LIMIT) > 1000:
        cutoff = now_mono - (2 * _BG_REGEN_COOLDOWN_S)
        for k in [k for k, v in _BG_REGEN_RATE_LIMIT.items() if v < cutoff]:
            _BG_REGEN_RATE_LIMIT.pop(k, None)

    async def _regen() -> None:
        # Local import to avoid circulars
        from app.database import async_session_maker
        from app.services.digest_generation_state_service import (
            mark_failed as _state_mark_failed,
        )
        from app.services.digest_generation_state_service import (
            mark_in_progress as _state_mark_in_progress,
        )
        from app.services.digest_generation_state_service import (
            mark_success as _state_mark_success,
        )
        from app.services.generation_state import is_generation_running

        # If the batch is currently running, don't pile on — it will catch this user.
        if is_generation_running():
            logger.info(
                "digest_background_regen_skipped_batch_running",
                user_id=str(user_id),
                target_date=str(target_date),
            )
            return

        try:
            async with async_session_maker() as bg_session:
                bg_svc = DigestService(bg_session)
                try:
                    # Check if a modern-format digest already exists.
                    # If so, skip regen — never destroy a good digest.
                    existing = await bg_svc._get_existing_digest(
                        user_id, target_date, is_serene=is_serene
                    )
                    if existing and existing.format_version in (
                        "editorial_v1",
                        "topics_v1",
                    ):
                        logger.info(
                            "digest_background_regen_skipped_good_format",
                            user_id=str(user_id),
                            target_date=str(target_date),
                            format_version=existing.format_version,
                        )
                        return

                    await _state_mark_in_progress(
                        bg_session, user_id, target_date, is_serene
                    )
                    # force_regenerate=True bypasses the yesterday fallback
                    # and goes straight to real generation.
                    await bg_svc.get_or_create_digest(
                        user_id=user_id,
                        target_date=target_date,
                        is_serene=is_serene,
                        force_regenerate=True,
                    )
                    await _state_mark_success(
                        bg_session, user_id, target_date, is_serene
                    )
                    await bg_session.commit()
                    logger.info(
                        "digest_background_regen_completed",
                        user_id=str(user_id),
                        target_date=str(target_date),
                        is_serene=is_serene,
                    )
                except Exception as e:
                    await bg_session.rollback()
                    # Record the failure in a fresh session so rollback
                    # doesn't wipe the observability row.
                    try:
                        async with async_session_maker() as err_session:
                            await _state_mark_failed(
                                err_session,
                                user_id,
                                target_date,
                                is_serene,
                                str(e),
                            )
                            await err_session.commit()
                    except Exception:
                        logger.exception(
                            "digest_background_regen_state_record_failed",
                            user_id=str(user_id),
                        )
                    raise
        except Exception:
            logger.exception(
                "digest_background_regen_failed",
                user_id=str(user_id),
                target_date=str(target_date),
                is_serene=is_serene,
            )

    try:
        task = asyncio.create_task(
            _regen(),
            name=f"digest_regen:{user_id}:{target_date}:{is_serene}",
        )
        # Pin the task so the event loop's weak reference can't let the GC
        # cancel it mid-run. The done-callback cleans up after completion.
        _BG_REGEN_TASKS.add(task)
        task.add_done_callback(_BG_REGEN_TASKS.discard)
        logger.info(
            "digest_background_regen_scheduled",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
        )
    except RuntimeError:
        # No running event loop (shouldn't happen in FastAPI request handling)
        logger.warning(
            "digest_background_regen_no_event_loop",
            user_id=str(user_id),
        )


def schedule_digest_regen(
    user_id: UUID,
    target_date: date,
    is_serene: bool,
) -> None:
    """Public wrapper around the background digest regen scheduler.

    Used by callers outside this module (e.g. the onboarding endpoint pre-warming
    a new user's digest, or the digest router when on-demand generation returns
    None). Preserves the rate-limit and batch-running-skip semantics of the
    private helper.
    """
    _schedule_background_regen(user_id, target_date, is_serene)


def schedule_initial_digest_generation(user_id: UUID) -> None:
    """Pre-warm both digest variants for a user who just completed onboarding.

    Invoked from a FastAPI BackgroundTask so it runs after the onboarding
    request has been committed — meaning the fresh UserSource / UserInterest /
    UserSubtopic rows are visible to the background session.

    Using the existing rate-limited scheduler means this is idempotent: if the
    user retries onboarding, we won't spawn duplicate generations.
    """
    target = today_paris()
    logger.info(
        "digest_pre_generation_scheduled_on_onboarding",
        user_id=str(user_id),
        target_date=str(target),
    )
    for is_serene in (False, True):
        _schedule_background_regen(user_id, target, is_serene)


def _count_digest_items(digest_items) -> int:
    """Count items in either EditorialPipelineResult or list."""
    if isinstance(digest_items, EditorialPipelineResult):
        return len(digest_items.subjects)
    return len(digest_items) if digest_items else 0


# --- Serein quotes -----------------------------------------------------------

from pathlib import Path as _Path

_QUOTES_PATH = _Path(__file__).resolve().parents[2] / "config" / "serein_quotes.yaml"
_QUOTES: list[dict] = []


def _load_quotes() -> list[dict]:
    global _QUOTES
    if not _QUOTES:
        try:
            with open(_QUOTES_PATH) as f:
                data = yaml.safe_load(f)
            _QUOTES = [
                q
                for q in (data.get("quotes", []) if data else [])
                if q.get("text") and q.get("author")
            ]
        except Exception:
            logger.warning("serein_quotes.yaml inaccessible — quotes désactivées")
            _QUOTES = []
    return _QUOTES


def _select_daily_quote(user_id: str, target_date: str) -> dict | None:
    """Deterministic daily quote: same user+date → same quote."""
    quotes = _load_quotes()
    if not quotes:
        return None
    seed = int(hashlib.sha256(f"{user_id}:{target_date}".encode()).hexdigest(), 16)
    rng = random.Random(seed)
    return rng.choice(quotes)


@dataclass
class EmergencyItem:
    """Dummy DigestItem wrapper for emergency fallback."""

    content: Content
    score: float = 0.5
    rank: int = 0
    reason: str = "Sélection de la rédaction"
    breakdown: list[DigestScoreBreakdown] | None = None


class DigestService:
    """Service for digest retrieval, actions, and completion tracking.

    This service orchestrates between:
    - DigestSelector: For generating new digests
    - Personalization: For 'not_interested' mutes
    - StreakService: For completion gamification
    """

    def __init__(
        self,
        session: AsyncSession,
        session_maker: async_sessionmaker[AsyncSession] | None = None,
    ):
        # `session_maker` est propagé au DigestSelector/EditorialPipeline :
        # la pipeline LLM ouvre ses propres sessions courtes pour ses ops
        # DB, et DigestSelector close() la session avant d'appeler la
        # pipeline (libère la connexion au pool pendant 3-5 min de LLM).
        # Après la pipeline, la session est réutilisable : SQLAlchemy
        # auto-begin une nouvelle transaction avec une connexion fraîche.
        # Cf. docs/bugs/bug-infinite-load-requests.md (P1 — site B).
        self.session = session
        self.session_maker = session_maker
        self.selector = DigestSelector(session, session_maker=session_maker)
        self.streak_service = StreakService(session)

    async def get_or_create_digest(
        self,
        user_id: UUID,
        target_date: date | None = None,
        hours_lookback: int = 168,
        force_regenerate: bool = False,
        is_serene: bool = False,
    ) -> DigestResponse | None:
        """Retrieves or generates today's digest for a user.

        Flow:
        1. Ensure user profile exists (creates if missing)
        2. Check if digest already exists for user + date
        3. If exists and force_regenerate=False, return existing
        4. If force_regenerate=True, delete existing and regenerate
        5. Generate new digest using DigestSelector
        6. Store in database and return

        Args:
            user_id: UUID of the user
            target_date: Date for digest (defaults to today)
            hours_lookback: Hours to look back for content (default: 168h/7 days)
                Extended window ensures user's followed sources are prioritized
                even if articles are older.
            force_regenerate: If True, delete existing digest and regenerate

        Returns:
            DigestResponse with 7 items, or None if generation failed
        """
        start_time = time.time()

        if target_date is None:
            target_date = today_paris()

        logger.info(
            "digest_get_or_create", user_id=str(user_id), target_date=str(target_date)
        )

        # 0. Ensure user profile exists
        # This prevents 503 errors for new users who don't have a profile yet
        step_start = time.time()
        from app.services.user_service import UserService

        user_service = UserService(self.session)
        await user_service.get_or_create_profile(str(user_id))
        profile_time = time.time() - step_start
        logger.info(
            "digest_step_profile",
            user_id=str(user_id),
            duration_ms=round(profile_time * 1000, 2),
        )

        # 1. Check for existing digest
        step_start = time.time()
        existing_digest = await self._get_existing_digest(
            user_id, target_date, is_serene=is_serene
        )
        existing_time = time.time() - step_start

        # 1a. Check format_version mismatch — stale cache from pre-editorial era
        expected_format = await self._get_user_digest_format(user_id)
        expected_version = {
            "editorial": "editorial_v1",
            "topics": "topics_v1",
            "flat": "flat_v1",
        }.get(expected_format, "editorial_v1")

        # Defer deletion of stale-format digest until AFTER the new digest is
        # successfully generated. This avoids a hole where we delete a valid
        # (but wrong-format) record and then fail to generate a replacement,
        # leaving the user with no digest for today at all. If the generation
        # fails below, we return the stale record as a fallback instead of
        # nothing — consistency of "something to show" wins over strict format.
        stale_format_digest: DailyDigest | None = None
        if existing_digest and existing_digest.format_version != expected_version:
            logger.info(
                "digest_format_mismatch_deferring_delete",
                user_id=str(user_id),
                digest_id=str(existing_digest.id),
                cached=existing_digest.format_version,
                expected=expected_version,
            )
            stale_format_digest = existing_digest
            existing_digest = None

        if existing_digest:
            if force_regenerate:
                # Delete existing digest and regenerate
                logger.info(
                    "digest_force_regenerating",
                    user_id=str(user_id),
                    digest_id=str(existing_digest.id),
                    duration_ms=round(existing_time * 1000, 2),
                )
                await self.session.delete(existing_digest)
                await self.session.flush()
            else:
                logger.info(
                    "digest_found_existing",
                    user_id=str(user_id),
                    digest_id=str(existing_digest.id),
                    format_version=existing_digest.format_version,
                    duration_ms=round(existing_time * 1000, 2),
                )
                try:
                    return await self._build_digest_response(existing_digest, user_id)
                except Exception:
                    # Render failed. Previously we `raise`d for modern formats
                    # to avoid silently downgrading to flat_v1, but that turned
                    # any persistently-corrupted record into an all-day 503
                    # loop for the user (each request hits the same broken
                    # JSONB and fails). Instead: defer deletion via the same
                    # `stale_format_digest` machinery used for version
                    # mismatches and fall through to regeneration. The
                    # deferred-delete logic below (step 4) replaces the
                    # corrupted record only when a fresh one is ready. If
                    # regeneration also fails, the stale-format fallback path
                    # will serve the old record (or yesterday's) as a last
                    # resort — still better than 503 forever.
                    logger.exception(
                        "digest_existing_render_failed",
                        user_id=str(user_id),
                        digest_id=str(existing_digest.id),
                        format_version=existing_digest.format_version,
                    )
                    if existing_digest.format_version in (
                        "editorial_v1",
                        "topics_v1",
                    ):
                        # Defer deletion, fall through to regeneration.
                        stale_format_digest = existing_digest
                        existing_digest = None
                    else:
                        # flat_v1 is expendable — delete and regenerate
                        await self.session.delete(existing_digest)
                        await self.session.flush()
        # 1b. No digest for today — try serving yesterday's digest instantly
        # while triggering a real background regeneration so the next read
        # gets fresh content. Without the background trigger this fallback
        # is a dead-end: the user sees yesterday's digest all day even when
        # the batch never reran for them.
        if not force_regenerate:
            yesterday = target_date - timedelta(days=1)
            yesterday_digest = await self._get_existing_digest(
                user_id, yesterday, is_serene=is_serene
            )
            if yesterday_digest:
                # Schedule background regen (rate-limited to 1/min per user-day-variant)
                _schedule_background_regen(
                    user_id=user_id,
                    target_date=target_date,
                    is_serene=is_serene,
                )

                # Never serve a flat_v1 (legacy) digest as yesterday fallback —
                # skip to real generation instead.
                if yesterday_digest.format_version == "flat_v1":
                    logger.warning(
                        "digest_yesterday_flat_v1_skipped",
                        user_id=str(user_id),
                        yesterday_date=str(yesterday),
                    )
                else:
                    logger.warning(
                        "digest_serving_yesterday_while_regenerating",
                        user_id=str(user_id),
                        yesterday_date=str(yesterday),
                        format_version=yesterday_digest.format_version,
                        expected_version=expected_version,
                    )
                    try:
                        response = await self._build_digest_response(
                            yesterday_digest, user_id
                        )
                        response.is_stale_fallback = True
                        return response
                    except Exception:
                        logger.warning(
                            "digest_yesterday_fallback_render_failed",
                            user_id=str(user_id),
                            format_version=yesterday_digest.format_version,
                        )

        logger.info(
            "digest_no_existing",
            user_id=str(user_id),
            duration_ms=round(existing_time * 1000, 2),
        )

        # 2. Determine effective mode from is_serene toggle
        effective_mode = "serein" if is_serene else "pour_vous"

        # 2a. Load user's sensitive_themes for personalized serein filter
        import json as _json

        from app.models.user import UserPreference as _UPref

        _st_result = await self.session.execute(
            select(_UPref.preference_value).where(
                _UPref.user_id == user_id,
                _UPref.preference_key == "sensitive_themes",
            )
        )
        _st_raw = _st_result.scalar_one_or_none()
        try:
            sensitive_themes: list[str] | None = (
                _json.loads(_st_raw) if _st_raw else None
            )
        except (ValueError, TypeError):
            logger.warning("sensitive_themes malformed for user %s, ignoring", user_id)
            sensitive_themes = None

        # 2b. Reuse format already resolved above (step 1a)
        effective_format = expected_format

        # 3. Generate new digest using DigestSelector
        step_start = time.time()
        from app.models.user import UserProfile as _UP
        from app.services.digest_selector import DiversityConstraints

        _user_profile = await self.session.scalar(
            select(_UP).where(_UP.user_id == user_id)
        )
        # Clamp weekly_goal to sensible range (3-10) to avoid edge cases
        raw_goal = (
            _user_profile.weekly_goal
            if _user_profile and _user_profile.weekly_goal
            else DiversityConstraints.TARGET_DIGEST_SIZE
        )
        target_size = max(3, min(raw_goal, 10))
        logger.info(
            "digest_generating_new",
            user_id=str(user_id),
            hours_lookback=hours_lookback,
            mode=effective_mode,
            is_serene=is_serene,
            output_format=effective_format,
            target_size=target_size,
            raw_weekly_goal=raw_goal,
        )

        try:
            digest_items = await self.selector.select_for_user(
                user_id,
                limit=target_size,
                hours_lookback=hours_lookback,
                mode=effective_mode,
                output_format=effective_format,
                sensitive_themes=sensitive_themes,
            )
        except Exception:
            logger.exception(
                "digest_selector_crashed",
                user_id=str(user_id),
                output_format=effective_format,
            )
            digest_items = []

        selection_time = time.time() - step_start
        _item_count = _count_digest_items(digest_items)
        logger.info(
            "digest_step_selection",
            user_id=str(user_id),
            item_count=_item_count,
            duration_ms=round(selection_time * 1000, 2),
        )

        # Check result format
        is_editorial_format = isinstance(digest_items, EditorialPipelineResult)
        is_topics_format = (
            not is_editorial_format
            and digest_items
            and isinstance(digest_items[0], TopicGroup)
        )
        logger.info(
            "digest_format_check",
            user_id=str(user_id),
            is_editorial=is_editorial_format,
            is_topics=is_topics_format,
            item_type=type(digest_items).__name__
            if is_editorial_format
            else (type(digest_items[0]).__name__ if digest_items else "empty"),
        )

        # Guardrail: editorial result with 0 subjects → fall back to topics
        if is_editorial_format and not digest_items.subjects:
            logger.warning(
                "digest_editorial_empty_subjects_fallback",
                user_id=str(user_id),
                has_header=bool(digest_items.header_text),
                has_closure=bool(digest_items.closure_text),
            )
            digest_items = []
            is_editorial_format = False

        # Emergency Fallback: If standard selection returns nothing, grab from user's sources first
        # This prevents 503 errors when personalization is too restrictive or history is empty
        if not digest_items:
            step_start = time.time()
            logger.warning(
                "digest_generation_standard_failed_attempting_fallback",
                user_id=str(user_id),
            )
            emergency_items = await self._get_emergency_candidates(
                user_id=user_id,
                limit=target_size,
                is_serene=is_serene,
                sensitive_themes=sensitive_themes,
            )
            fallback_time = time.time() - step_start

            # Wrap emergency items in TopicGroups so the digest is stored
            # as topics_v1 — never produce flat_v1 legacy format.
            if emergency_items:
                followed_src_ids = {
                    ei.content.source_id
                    for ei in emergency_items
                    if getattr(ei, "reason", "") == "Source suivie"
                }
                topic_groups: list[TopicGroup] = []
                for item in emergency_items:
                    scored = ScoredArticle(
                        content=item.content,
                        score=item.score,
                        reason=item.reason,
                        breakdown=item.breakdown,
                        is_followed_source=item.content.source_id in followed_src_ids,
                    )
                    theme = item.content.source.theme if item.content.source else None
                    topic_groups.append(
                        TopicGroup(
                            topic_id=f"emergency_{item.rank}",
                            label=item.content.title or "Article",
                            articles=[scored],
                            topic_score=item.score,
                            reason=item.reason,
                            theme=theme,
                        )
                    )
                digest_items = topic_groups
                is_topics_format = True
                is_editorial_format = False
            else:
                digest_items = []

            logger.info(
                "digest_step_fallback",
                user_id=str(user_id),
                item_count=len(digest_items),
                wrapped_as_topics=bool(digest_items),
                duration_ms=round(fallback_time * 1000, 2),
            )

        if not digest_items:
            # If even emergency fallback fails, try to salvage by returning
            # the stale-format digest we deferred deleting above. Better a
            # wrong-format-but-renderable digest than nothing.
            logger.error("digest_generation_failed_total", user_id=str(user_id))
            if stale_format_digest is not None:
                logger.warning(
                    "digest_returning_stale_format_as_fallback",
                    user_id=str(user_id),
                    stale_format=stale_format_digest.format_version,
                )
                try:
                    response = await self._build_digest_response(
                        stale_format_digest, user_id
                    )
                    # Mark as stale so the mobile client auto-refetches, and
                    # fire a background regen so the next poll has fresh
                    # content. Without this the user is silently stuck on
                    # wrong-format content for the rest of the day.
                    response.is_stale_fallback = True
                    _schedule_background_regen(
                        user_id=user_id,
                        target_date=target_date,
                        is_serene=is_serene,
                    )
                    return response
                except Exception:
                    logger.exception(
                        "digest_stale_format_fallback_render_failed",
                        user_id=str(user_id),
                    )
            return None

        # 4. Now that we know we have items to store, drop the stale-format
        #    digest so the unique-constraint (user_id, target_date, is_serene)
        #    doesn't conflict with the new insert.
        if stale_format_digest is not None:
            await self.session.delete(stale_format_digest)
            await self.session.flush()
            stale_format_digest = None

        step_start = time.time()
        if is_editorial_format:
            digest = await self._create_digest_record_editorial(
                user_id,
                target_date,
                digest_items,
                mode=effective_mode,
                is_serene=is_serene,
            )
            if digest is None:
                logger.error("editorial_digest_storage_failed", user_id=str(user_id))
                return None
        elif is_topics_format:
            digest = await self._create_digest_record_topics(
                user_id,
                target_date,
                digest_items,
                mode=effective_mode,
                is_serene=is_serene,
            )
        else:
            digest = await self._create_digest_record(
                user_id,
                target_date,
                digest_items,
                mode=effective_mode,
                is_serene=is_serene,
            )
        store_time = time.time() - step_start

        total_time = time.time() - start_time
        logger.info(
            "digest_created",
            user_id=str(user_id),
            digest_id=str(digest.id),
            items_count=_count_digest_items(digest_items),
            store_duration_ms=round(store_time * 1000, 2),
            total_duration_ms=round(total_time * 1000, 2),
        )

        return await self._build_digest_response(digest, user_id)

    async def _get_emergency_candidates(
        self,
        user_id: UUID,
        limit: int = 5,
        is_serene: bool = False,
        sensitive_themes: list[str] | None = None,
    ) -> list[Any]:
        """Last resort: get most recent content from user's followed sources first.

        CRITICAL FIX: Now prioritizes user's followed sources instead of just curated content.
        Falls back to curated sources only if user has no followed sources.

        Applies diversity constraints (max 2 per source) and generates minimal
        breakdown data so the personalization sheet can display properly.
        """
        from collections import defaultdict

        from sqlalchemy.orm import selectinload

        from app.models.content import Content
        from app.models.source import Source
        from app.services.recommendation.filter_presets import apply_serein_filter

        MAX_PER_SOURCE = 2  # Same constraint as DigestSelector
        # Fetch more candidates than needed so we can apply diversity
        fetch_limit = limit * 5

        # Get user's followed sources
        from app.models.source import UserSource

        followed_result = await self.session.execute(
            select(UserSource.source_id).where(UserSource.user_id == user_id)
        )
        followed_source_ids = set(followed_result.scalars().all())

        # OPTIMIZATION: Limit query to last 7 days to avoid full table scan
        cutoff_date = datetime.now(UTC) - timedelta(days=7)

        all_contents: list = []

        # Try user's followed sources first
        if followed_source_ids:
            stmt = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    Content.source_id.in_(list(followed_source_ids)),
                    Content.published_at >= cutoff_date,
                )
                .order_by(Content.published_at.desc())
                .limit(fetch_limit)
            )
            if is_serene:
                stmt = apply_serein_filter(stmt, sensitive_themes=sensitive_themes)

            result = await self.session.execute(stmt)
            all_contents = list(result.scalars().all())

        # If not enough from user sources, add curated sources
        if len(all_contents) < fetch_limit:
            existing_ids = {c.id for c in all_contents}
            curated_query = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    Source.is_curated,
                    Content.published_at >= cutoff_date,
                )
                .order_by(Content.published_at.desc())
                .limit(fetch_limit - len(all_contents))
            )
            if existing_ids:
                curated_query = curated_query.where(
                    Content.id.notin_(list(existing_ids))
                )
            if is_serene:
                curated_query = apply_serein_filter(
                    curated_query, sensitive_themes=sensitive_themes
                )
            stmt = curated_query

            result = await self.session.execute(stmt)
            all_contents.extend(result.scalars().all())

        # LAST RESORT: If still not enough, query ANY active source with wider window (30 days)
        # This guarantees new users always get a digest even if curated sources have no recent content
        if len(all_contents) < limit:
            existing_ids = {c.id for c in all_contents}
            wider_cutoff = datetime.now(UTC) - timedelta(days=30)
            any_source_query = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    Source.is_active,
                    Content.published_at >= wider_cutoff,
                )
                .order_by(Content.published_at.desc())
                .limit(fetch_limit - len(all_contents))
            )
            if existing_ids:
                any_source_query = any_source_query.where(
                    Content.id.notin_(list(existing_ids))
                )
            if is_serene:
                any_source_query = apply_serein_filter(
                    any_source_query, sensitive_themes=sensitive_themes
                )

            result = await self.session.execute(any_source_query)
            all_contents.extend(result.scalars().all())

            if len(all_contents) > len(existing_ids):
                logger.info(
                    "digest_emergency_last_resort_used",
                    user_id=str(user_id),
                    added_count=len(all_contents) - len(existing_ids),
                )

        # Apply diversity constraint: max 2 articles per source
        selected: list = []
        source_counts: dict = defaultdict(int)

        for content in all_contents:
            if len(selected) >= limit:
                break

            source_id = content.source_id
            if source_counts[source_id] >= MAX_PER_SOURCE:
                continue

            # Generate a minimal breakdown for the personalization sheet
            breakdown_items = []

            # Recency info
            hours_old = (
                datetime.now(UTC)
                - content.published_at.replace(
                    tzinfo=UTC
                    if content.published_at.tzinfo is None
                    else content.published_at.tzinfo
                )
            ).total_seconds() / 3600
            if hours_old < 6:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Article très récent (< 6h)",
                        points=30.0,
                        is_positive=True,
                    )
                )
            elif hours_old < 24:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Article récent (< 24h)", points=25.0, is_positive=True
                    )
                )
            elif hours_old < 48:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Publié aujourd'hui", points=15.0, is_positive=True
                    )
                )
            elif hours_old < 72:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Publié hier", points=8.0, is_positive=True
                    )
                )

            # Source info
            if content.source_id in followed_source_ids:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Source de confiance", points=50.0, is_positive=True
                    )
                )
            elif content.source and content.source.is_curated:
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label="Source qualitative", points=10.0, is_positive=True
                    )
                )

            # Theme info
            if content.source and content.source.theme:
                theme_labels = {
                    "tech": "Tech",
                    "society": "Société",
                    "environment": "Environnement",
                    "economy": "Économie",
                    "politics": "Politique",
                    "culture": "Culture",
                    "science": "Sciences",
                    "international": "International",
                }
                theme_label = theme_labels.get(
                    content.source.theme, content.source.theme.capitalize()
                )
                breakdown_items.append(
                    DigestScoreBreakdown(
                        label=f"Thème : {theme_label}", points=20.0, is_positive=True
                    )
                )

            # Build reason — prefer theme info over generic label
            theme_labels = {
                "tech": "Tech & Innovation",
                "society": "Société",
                "environment": "Environnement",
                "economy": "Économie",
                "politics": "Politique",
                "culture": "Culture & Idées",
                "science": "Sciences",
                "international": "Géopolitique",
                "geopolitics": "Géopolitique",
            }
            if content.source and content.source.theme:
                label = theme_labels.get(
                    content.source.theme.lower(), content.source.theme.capitalize()
                )
                reason = f"Thème : {label}"
            elif content.source_id in followed_source_ids:
                reason = "Source suivie"
            else:
                reason = "Sélection de la rédaction"

            selected.append(
                EmergencyItem(
                    content=content,
                    score=sum(b.points for b in breakdown_items),
                    rank=len(selected) + 1,
                    reason=reason,
                    breakdown=breakdown_items,
                )
            )
            source_counts[source_id] += 1

        # Log diversity stats
        unique_sources = len({item.content.source_id for item in selected})
        logger.info(
            "digest_emergency_fallback_with_diversity",
            user_id=str(user_id),
            count=len(selected),
            unique_sources=unique_sources,
            source_distribution={str(k): v for k, v in source_counts.items()},
            had_followed_sources=bool(followed_source_ids),
        )

        return selected

    async def apply_action(
        self, digest_id: UUID, user_id: UUID, content_id: UUID, action: DigestAction
    ) -> dict[str, Any]:
        """Apply an action to a digest item.

        Actions:
        - READ: Mark article as consumed in UserContentStatus
        - SAVE: Save article to user's list
        - NOT_INTERESTED: Hide article and trigger personalization mute
        - UNDO: Reset all actions

        Args:
            digest_id: ID of the daily digest
            user_id: ID of the user
            content_id: ID of the content/article
            action: Action to apply

        Returns:
            Dict with success status and action details
        """
        logger.info(
            "digest_action_apply",
            user_id=str(user_id),
            digest_id=str(digest_id),
            content_id=str(content_id),
            action=action.value,
        )

        # Get or create UserContentStatus
        status = await self._get_or_create_content_status(user_id, content_id)

        if action == DigestAction.READ:
            status.status = ContentStatus.CONSUMED
            status.is_hidden = False
            # Increment regular streak via StreakService
            await self.streak_service.increment_consumption(str(user_id))
            # Feedback: reinforce theme + subtopic weights
            from app.services.content_service import ContentService
            from app.services.recommendation.scoring_config import ScoringWeights

            content_service = ContentService(self.session)
            await content_service._adjust_interest_weight(user_id, content_id, None)
            await content_service._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.READ_TOPIC_BOOST
            )

        elif action == DigestAction.SAVE:
            status.is_saved = True
            status.saved_at = datetime.utcnow()
            status.is_hidden = False
            # Reinforce subtopic weights on bookmark
            from app.services.content_service import ContentService

            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights

            await content_service._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.BOOKMARK_TOPIC_BOOST
            )

        elif action == DigestAction.LIKE:
            status.is_liked = True
            status.liked_at = datetime.utcnow()
            # Reinforce subtopic weights via ContentService
            from app.services.content_service import ContentService

            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights

            await content_service._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.LIKE_TOPIC_BOOST
            )

        elif action == DigestAction.UNLIKE:
            status.is_liked = False
            status.liked_at = None
            # Reverse subtopic weight adjustment
            from app.services.content_service import ContentService

            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights

            await content_service._adjust_subtopic_weights(
                user_id, content_id, -ScoringWeights.LIKE_TOPIC_BOOST
            )

        elif action == DigestAction.NOT_INTERESTED:
            status.is_hidden = True
            status.hidden_reason = "not_interested"
            # Trigger personalization mute
            await self._trigger_personalization_mute(user_id, content_id)

        elif action == DigestAction.UNDO:
            status.status = ContentStatus.UNSEEN
            status.is_saved = False
            status.is_liked = False
            status.is_hidden = False
            status.hidden_reason = None

        else:
            raise ValueError(f"Unknown action: {action}")

        await self.session.flush()

        return {
            "success": True,
            "content_id": content_id,
            "action": action,
            "applied_at": datetime.utcnow(),
        }

    async def complete_digest(
        self, digest_id: UUID, user_id: UUID, closure_time_seconds: int | None = None
    ) -> dict[str, Any]:
        """Record completion of a digest.

        - Creates DigestCompletion record
        - Updates closure streak via StreakService
        - Returns completion stats and streak info

        Args:
            digest_id: ID of the daily digest
            user_id: ID of the user
            closure_time_seconds: Time spent reading digest (optional)

        Returns:
            Dict with completion stats and updated streak
        """
        logger.info(
            "digest_complete",
            user_id=str(user_id),
            digest_id=str(digest_id),
            closure_time=closure_time_seconds,
        )

        # Get digest to determine target_date
        digest = await self.session.get(DailyDigest, digest_id)
        if not digest:
            raise ValueError(f"Digest not found: {digest_id}")

        # Get action stats from content statuses
        stats = await self._get_digest_action_stats(user_id, digest)

        # Create completion record
        completion = DigestCompletion(
            id=uuid4(),
            user_id=user_id,
            target_date=digest.target_date,
            completed_at=datetime.utcnow(),
            articles_read=stats["read"],
            articles_saved=stats["saved"],
            articles_dismissed=stats["dismissed"],
            closure_time_seconds=closure_time_seconds,
        )
        self.session.add(completion)

        # Update closure streak
        streak_update = await self._update_closure_streak(user_id)

        await self.session.flush()

        return {
            "success": True,
            "digest_id": digest_id,
            "completed_at": completion.completed_at,
            "articles_read": stats["read"],
            "articles_saved": stats["saved"],
            "articles_dismissed": stats["dismissed"],
            "closure_time_seconds": closure_time_seconds,
            "closure_streak": streak_update["current"],
            "streak_message": streak_update.get("message"),
        }

    async def _get_existing_digest(
        self, user_id: UUID, target_date: date, is_serene: bool = False
    ) -> DailyDigest | None:
        """Check if digest already exists for user + date + serene variant."""
        stmt = select(DailyDigest).where(
            and_(
                DailyDigest.user_id == user_id,
                DailyDigest.target_date == target_date,
                DailyDigest.is_serene == is_serene,
            )
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def _create_digest_record(
        self,
        user_id: UUID,
        target_date: date,
        digest_items: list[Any],  # List[DigestItem]
        mode: str | None = None,
        is_serene: bool = False,
    ) -> DailyDigest:
        """Create a new DailyDigest database record."""
        # Build items JSON array
        items_json = []
        for item in digest_items:
            item_data = {
                "content_id": str(item.content.id),
                "rank": item.rank,
                "reason": item.reason,
                "source_name": item.content.source.name
                if item.content.source
                else None,
                "score": float(item.score),
                "entities": item.content.entities or [],
            }

            # Store breakdown if available
            # Use getattr for safety: DigestItem (from selector) has .breakdown,
            # but EmergencyItem (fallback) may not always have it as a direct attribute
            breakdown = getattr(item, "breakdown", None)
            if breakdown:
                logger.info(
                    "storing_breakdown_for_digest_item",
                    content_id=str(item.content.id),
                    content_title=item.content.title[:50] if item.content.title else "",
                    breakdown_count=len(breakdown),
                    breakdown_labels=[b.label for b in breakdown[:3]],
                )
                item_data["breakdown"] = [
                    {"label": b.label, "points": b.points, "is_positive": b.is_positive}
                    for b in breakdown
                ]
            else:
                logger.warning(
                    "no_breakdown_available_for_digest_item",
                    content_id=str(item.content.id),
                    content_title=item.content.title[:50] if item.content.title else "",
                    item_type=type(item).__name__,
                )

            items_json.append(item_data)

        digest = DailyDigest(
            id=uuid4(),
            user_id=user_id,
            target_date=target_date,
            items=items_json,
            mode=mode or "pour_vous",
            is_serene=is_serene,
            format_version="flat_v1",
            generated_at=datetime.now(UTC),
        )

        try:
            self.session.add(digest)
            await self.session.flush()
        except IntegrityError:
            await self.session.rollback()
            logger.warning(
                "digest_insert_race_condition_flat",
                user_id=str(user_id),
                target_date=str(target_date),
                is_serene=is_serene,
            )
            existing = await self._get_existing_digest(
                user_id, target_date, is_serene=is_serene
            )
            if existing:
                return existing
            raise

        return digest

    async def _create_digest_record_topics(
        self,
        user_id: UUID,
        target_date: date,
        topic_groups: list[TopicGroup],
        mode: str | None = None,
        is_serene: bool = False,
    ) -> DailyDigest:
        """Create a new DailyDigest at topics_v1 format."""
        items_json = {
            "format": "topics_v1",
            "topics": [
                {
                    "topic_id": tg.topic_id,
                    "label": tg.label,
                    "rank": i + 1,
                    "reason": tg.reason,
                    "is_trending": tg.is_trending,
                    "is_une": tg.is_une,
                    "theme": tg.theme,
                    "topic_score": float(tg.topic_score),
                    "subjects": tg.subjects,
                    "articles": [
                        {
                            "content_id": str(a.content.id),
                            "rank": j + 1,
                            "reason": a.reason,
                            "source_name": a.content.source.name
                            if a.content.source
                            else None,
                            "score": float(a.score),
                            "is_followed_source": a.is_followed_source,
                            "breakdown": [
                                {
                                    "label": b.label,
                                    "points": b.points,
                                    "is_positive": b.is_positive,
                                }
                                for b in (a.breakdown or [])
                            ],
                        }
                        for j, a in enumerate(tg.articles)
                    ],
                }
                for i, tg in enumerate(topic_groups)
            ],
        }

        digest = DailyDigest(
            id=uuid4(),
            user_id=user_id,
            target_date=target_date,
            items=items_json,
            mode=mode or "pour_vous",
            is_serene=is_serene,
            format_version="topics_v1",
            generated_at=datetime.now(UTC),
        )

        try:
            self.session.add(digest)
            await self.session.flush()
        except IntegrityError:
            await self.session.rollback()
            logger.warning(
                "digest_insert_race_condition_topics",
                user_id=str(user_id),
                target_date=str(target_date),
                is_serene=is_serene,
            )
            existing = await self._get_existing_digest(
                user_id, target_date, is_serene=is_serene
            )
            if existing:
                return existing
            raise

        return digest

    async def _create_digest_record_editorial(
        self,
        user_id: UUID,
        target_date: date,
        result: EditorialPipelineResult,
        mode: str | None = None,
        is_serene: bool = False,
    ) -> DailyDigest | None:
        """Create a new DailyDigest in editorial_v1 format."""
        # Garde-fou: filter out subjects with no articles at all
        valid_subjects = [
            s for s in result.subjects if s.actu_article or s.deep_article
        ]
        if not valid_subjects:
            logger.error("editorial_digest.all_subjects_empty", user_id=str(user_id))
            return None
        result = result.model_copy(update={"subjects": valid_subjects})

        items_json = {
            "format_version": "editorial_v1",
            "header_text": result.header_text,
            "mode": mode or "pour_vous",
            "subjects": [
                {
                    "rank": s.rank,
                    "topic_id": s.topic_id,
                    "label": s.label,
                    "selection_reason": s.selection_reason,
                    "deep_angle": s.deep_angle,
                    "source_count": s.source_count,
                    "theme": s.theme,
                    "is_a_la_une": s.is_a_la_une,
                    "intro_text": s.intro_text,
                    "transition_text": s.transition_text,
                    "perspective_count": s.perspective_count,
                    "bias_distribution": s.bias_distribution,
                    "bias_highlights": s.bias_highlights,
                    "divergence_analysis": s.divergence_analysis,
                    "divergence_level": s.divergence_level,
                    "perspective_sources": s.perspective_sources,
                    "perspective_articles": s.perspective_articles,
                    "representative_content_id": (
                        str(s.representative_content_id)
                        if s.representative_content_id
                        else None
                    ),
                    "actu_article": {
                        "content_id": str(s.actu_article.content_id),
                        "title": s.actu_article.title,
                        "source_name": s.actu_article.source_name,
                        "source_id": str(s.actu_article.source_id),
                        "is_user_source": s.actu_article.is_user_source,
                        "badge": "actu",
                        "published_at": s.actu_article.published_at.isoformat(),
                    }
                    if s.actu_article
                    else None,
                    "extra_actu_articles": [
                        {
                            "content_id": str(a.content_id),
                            "title": a.title,
                            "source_name": a.source_name,
                            "source_id": str(a.source_id),
                            "is_user_source": a.is_user_source,
                            "badge": "actu",
                            "published_at": a.published_at.isoformat(),
                        }
                        for a in s.extra_actu_articles
                    ],
                    "deep_article": {
                        "content_id": str(s.deep_article.content_id),
                        "title": s.deep_article.title,
                        "source_name": s.deep_article.source_name,
                        "source_id": str(s.deep_article.source_id),
                        "badge": "pas_de_recul",
                        "match_reason": s.deep_article.match_reason,
                        "published_at": s.deep_article.published_at.isoformat(),
                    }
                    if s.deep_article
                    else None,
                }
                for s in result.subjects
            ],
            "pepite": {
                "content_id": str(result.pepite.content_id),
                "mini_editorial": result.pepite.mini_editorial,
                "badge": "pepite",
            }
            if result.pepite
            else None,
            "coup_de_coeur": {
                "content_id": str(result.coup_de_coeur.content_id),
                "title": result.coup_de_coeur.title,
                "source_name": result.coup_de_coeur.source_name,
                "save_count": result.coup_de_coeur.save_count,
                "badge": "coup_de_coeur",
            }
            if result.coup_de_coeur
            else None,
            "actu_decalee": {
                "content_id": str(result.actu_decalee.content_id),
                "mini_editorial": result.actu_decalee.mini_editorial,
                "badge": "actu_decalee",
            }
            if result.actu_decalee
            else None,
            "closure_text": result.closure_text,
            "cta_text": result.cta_text,
            "generated_at": datetime.utcnow().isoformat(),
            "metadata": result.metadata,
        }

        digest = DailyDigest(
            id=uuid4(),
            user_id=user_id,
            target_date=target_date,
            items=items_json,
            mode=mode or "pour_vous",
            is_serene=is_serene,
            format_version="editorial_v1",
            generated_at=datetime.now(UTC),
        )

        try:
            self.session.add(digest)
            await self.session.flush()
        except IntegrityError:
            await self.session.rollback()
            logger.warning(
                "digest_insert_race_condition_editorial",
                user_id=str(user_id),
                target_date=str(target_date),
                is_serene=is_serene,
            )
            existing = await self._get_existing_digest(
                user_id, target_date, is_serene=is_serene
            )
            if existing:
                return existing
            raise

        return digest

    def _determine_top_reason(self, breakdown: list[DigestScoreBreakdown]) -> str:
        """Extract the most significant positive reason for the label.

        Analyzes the breakdown to generate a user-friendly top-level reason.
        """
        if not breakdown:
            return "Sélectionné pour vous"

        positive = [b for b in breakdown if b.is_positive]
        if not positive:
            return "Sélectionné pour vous"

        # Sort by points descending
        positive.sort(key=lambda x: x.points, reverse=True)
        top = positive[0]

        # Format based on top reason type
        if "Thème" in top.label:
            theme = top.label.split(": ")[1] if ": " in top.label else ""
            return f"Vos intérêts : {theme}"
        elif "Source de confiance" in top.label:
            return "Source suivie"
        elif "Source personnalisée" in top.label:
            return "Ta source personnalisée"
        elif "Renforcé par vos j'aime" in top.label:
            topics = [
                parts[1]
                for b in positive
                if "Renforcé" in b.label
                for parts in [b.label.split(": ", 1)]
                if len(parts) > 1
            ][:2]
            return (
                f"Renforcé par vos j'aime : {', '.join(topics)}"
                if topics
                else "Renforcé par vos j'aime"
            )
        elif "Sous-thème" in top.label:
            topics = [
                parts[1]
                for b in positive
                if "Sous-thème" in b.label
                for parts in [b.label.split(": ", 1)]
                if len(parts) > 1
            ][:2]
            return (
                f"Vos centres d'intérêt : {', '.join(topics)}"
                if topics
                else "Vos centres d'intérêt"
            )
        else:
            return top.label

    async def _build_digest_response(
        self, digest: DailyDigest, user_id: UUID
    ) -> DigestResponse:
        """Build DigestResponse from database record with action states.

        Branches on format_version:
        - topics_v1: grouped topics + flat items fallback
        - flat_v1 / None: legacy flat list
        """
        if digest.format_version == "editorial_v1":
            return await self._build_editorial_response(digest, user_id)
        if digest.format_version == "topics_v1":
            return await self._build_topics_response(digest, user_id)

        # Legacy flat format
        # Extract all content IDs upfront
        content_ids = [UUID(item_data["content_id"]) for item_data in digest.items]

        # Batch query 1: Check for existing completion
        completion = await self.session.scalar(
            select(DigestCompletion).where(
                and_(
                    DigestCompletion.user_id == user_id,
                    DigestCompletion.target_date == digest.target_date,
                )
            )
        )

        # Batch query 2: Fetch ALL content with eager-loaded sources in one query
        content_stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id.in_(content_ids))
        )
        content_result = await self.session.execute(content_stmt)
        content_map = {c.id: c for c in content_result.scalars().all()}

        # Batch query 3: Fetch ALL action states in one query
        action_states_map = await self._get_batch_action_states(user_id, content_ids)

        logger.info(
            "digest_response_batch_loaded",
            digest_id=str(digest.id),
            content_found=len(content_map),
            content_expected=len(content_ids),
            action_states_found=len(action_states_map),
        )

        # Build items using pre-fetched data (no more per-item queries)
        items = []
        for item_data in digest.items:
            content_id = UUID(item_data["content_id"])
            content = content_map.get(content_id)

            if not content or not content.source:
                logger.warning(
                    "digest_content_or_source_not_found",
                    content_id=str(content_id),
                    digest_id=str(digest.id),
                    content_found=content is not None,
                    source_found=bool(content and content.source),
                )
                continue

            # Get action state from pre-fetched map
            action_state = action_states_map.get(
                content_id,
                {
                    "is_read": False,
                    "is_saved": False,
                    "is_liked": False,
                    "is_dismissed": False,
                },
            )

            # Rebuild breakdown from stored data if available
            breakdown_data = item_data.get("breakdown") or []
            if not breakdown_data:
                logger.debug(
                    "no_breakdown_data_in_stored_item",
                    content_id=str(content_id),
                    digest_id=str(digest.id),
                    item_rank=item_data.get("rank", 0),
                )
            breakdown = (
                [
                    DigestScoreBreakdown(
                        label=b.get("label", ""),
                        points=b.get("points", 0.0),
                        is_positive=b.get("is_positive", True),
                    )
                    for b in breakdown_data
                    if isinstance(b, dict) and b.get("label")
                ]
                if breakdown_data
                else []
            )

            # Build recommendation_reason if breakdown exists
            recommendation_reason = None
            if breakdown:
                recommendation_reason = DigestRecommendationReason(
                    label=self._determine_top_reason(breakdown),
                    score_total=sum(b.points for b in breakdown),
                    breakdown=breakdown,
                )

            # Build DigestItem
            items.append(
                DigestItem(
                    content_id=content_id,
                    title=content.title,
                    url=content.url,
                    thumbnail_url=content.thumbnail_url,
                    description=content.description or None,
                    html_content=content.html_content,
                    topics=content.topics or [],
                    entities=content.entities or [],
                    content_type=content.content_type,
                    duration_seconds=content.duration_seconds,
                    published_at=content.published_at,
                    source=content.source,  # SourceMini will be handled by from_attributes
                    rank=item_data["rank"],
                    reason=item_data["reason"],
                    recommendation_reason=recommendation_reason,
                    is_read=action_state["is_read"],
                    is_saved=action_state["is_saved"],
                    is_liked=action_state["is_liked"],
                    is_dismissed=action_state["is_dismissed"],
                )
            )

        from app.services.digest_selector import DiversityConstraints

        return DigestResponse(
            digest_id=digest.id,
            user_id=digest.user_id,
            target_date=digest.target_date,
            generated_at=digest.generated_at,
            mode=digest.mode or "pour_vous",
            is_serene=digest.is_serene,
            format_version=digest.format_version or "flat_v1",
            items=items,
            topics=[],
            completion_threshold=DiversityConstraints.COMPLETION_THRESHOLD,
            is_completed=completion is not None,
            completed_at=completion.completed_at if completion else None,
        )

    async def _build_editorial_response(
        self,
        digest: DailyDigest,
        user_id: UUID,
    ) -> DigestResponse:
        """Build DigestResponse from an editorial_v1 JSONB record.

        Maps editorial subjects to topics + flat items for backward compatibility
        with existing mobile clients.
        """
        items_data = digest.items if isinstance(digest.items, dict) else {}
        subjects_data = items_data.get("subjects", [])

        # Collect all content_ids (actu + deep + pepite + coup_de_coeur)
        all_content_ids: list[UUID] = []
        for subject in subjects_data:
            if subject.get("actu_article"):
                all_content_ids.append(UUID(subject["actu_article"]["content_id"]))
            for extra in subject.get("extra_actu_articles", []):
                all_content_ids.append(UUID(extra["content_id"]))
            if subject.get("deep_article"):
                all_content_ids.append(UUID(subject["deep_article"]["content_id"]))

        pepite_data = items_data.get("pepite")
        coup_de_coeur_data = items_data.get("coup_de_coeur")
        actu_decalee_data = items_data.get("actu_decalee")
        if pepite_data and pepite_data.get("content_id"):
            all_content_ids.append(UUID(pepite_data["content_id"]))
        if coup_de_coeur_data and coup_de_coeur_data.get("content_id"):
            all_content_ids.append(UUID(coup_de_coeur_data["content_id"]))
        if actu_decalee_data and actu_decalee_data.get("content_id"):
            all_content_ids.append(UUID(actu_decalee_data["content_id"]))

        # Batch queries
        completion = await self.session.scalar(
            select(DigestCompletion).where(
                and_(
                    DigestCompletion.user_id == user_id,
                    DigestCompletion.target_date == digest.target_date,
                )
            )
        )

        content_stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id.in_(all_content_ids))
        )
        content_result = await self.session.execute(content_stmt)
        content_map = {c.id: c for c in content_result.scalars().all()}

        action_states_map = await self._get_batch_action_states(
            user_id, all_content_ids
        )

        # Build topics (one topic per subject) + flat items
        response_topics: list[DigestTopic] = []
        flat_items: list[DigestItem] = []
        global_rank = 0

        for subject in subjects_data:
            topic_articles: list[DigestTopicArticle] = []

            # Build ordered article list: actu → extras → deep
            art_entries: list[tuple[str, dict]] = []
            if subject.get("actu_article"):
                art_entries.append(("actu_article", subject["actu_article"]))
            for extra in subject.get("extra_actu_articles", []):
                art_entries.append(("extra_actu_article", extra))
            if subject.get("deep_article"):
                art_entries.append(("deep_article", subject["deep_article"]))

            for art_idx, (art_key, art_data) in enumerate(art_entries):
                content_id = UUID(art_data["content_id"])
                content = content_map.get(content_id)
                if not content:
                    logger.warning(
                        "editorial_article_not_found",
                        content_id=str(content_id),
                        art_key=art_key,
                        topic_label=subject.get("label", ""),
                    )
                    continue
                if not content.source:
                    logger.warning(
                        "editorial_article_missing_source",
                        content_id=str(content_id),
                        art_key=art_key,
                        topic_label=subject.get("label", ""),
                    )
                    continue

                action_state = action_states_map.get(
                    content_id,
                    {
                        "is_read": False,
                        "is_saved": False,
                        "is_liked": False,
                        "is_dismissed": False,
                    },
                )

                reason = art_data.get("match_reason") or subject.get(
                    "selection_reason", ""
                )

                topic_article = DigestTopicArticle(
                    content_id=content_id,
                    title=content.title,
                    url=content.url,
                    thumbnail_url=content.thumbnail_url,
                    description=content.description or None,
                    html_content=content.html_content,
                    topics=content.topics or [],
                    entities=content.entities or [],
                    content_type=content.content_type,
                    duration_seconds=content.duration_seconds,
                    published_at=content.published_at,
                    is_paid=content.is_paid if hasattr(content, "is_paid") else False,
                    source=content.source,
                    rank=art_idx + 1,
                    reason=reason,
                    badge=art_data.get("badge"),
                    is_followed_source=art_data.get("is_user_source", False),
                    recommendation_reason=None,
                    is_read=action_state["is_read"],
                    is_saved=action_state["is_saved"],
                    is_liked=action_state["is_liked"],
                    is_dismissed=action_state["is_dismissed"],
                )
                topic_articles.append(topic_article)

                # Flat item for backward compat
                global_rank += 1
                flat_items.append(
                    DigestItem(
                        content_id=content_id,
                        title=content.title,
                        url=content.url,
                        thumbnail_url=content.thumbnail_url,
                        description=content.description or None,
                        html_content=content.html_content,
                        topics=content.topics or [],
                        content_type=content.content_type,
                        duration_seconds=content.duration_seconds,
                        published_at=content.published_at,
                        is_paid=content.is_paid
                        if hasattr(content, "is_paid")
                        else False,
                        source=content.source,
                        rank=global_rank,
                        reason=reason,
                        badge=art_data.get("badge"),
                        recommendation_reason=None,
                        is_read=action_state["is_read"],
                        is_saved=action_state["is_saved"],
                        is_liked=action_state["is_liked"],
                        is_dismissed=action_state["is_dismissed"],
                    )
                )

            if topic_articles:
                # Round 3 fix (Sentry PYTHON-R) : certains digests persistés
                # en DB avant le fix source contiennent un dict imbriqué au
                # lieu d'une string. Coerce défensivement au boundary pour ne
                # pas casser les digests historiques côté read.
                _divergence_raw = subject.get("divergence_analysis")
                if isinstance(_divergence_raw, dict):
                    import json as _json

                    _divergence_str = _json.dumps(_divergence_raw, ensure_ascii=False)
                elif _divergence_raw is not None and not isinstance(
                    _divergence_raw, str
                ):
                    _divergence_str = str(_divergence_raw)
                else:
                    _divergence_str = _divergence_raw
                response_topics.append(
                    DigestTopic(
                        topic_id=subject.get("topic_id", ""),
                        label=subject.get("label", ""),
                        rank=subject.get("rank", 0),
                        reason=subject.get("selection_reason", ""),
                        is_trending=subject.get("is_a_la_une", False),
                        is_une=subject.get("is_a_la_une", False),
                        source_count=subject.get("source_count", 0),
                        theme=subject.get("theme"),
                        topic_score=0.0,
                        # `deep_angle` is optional (null for people/faits-divers).
                        # `subject.get("deep_angle", "")` returns None when the
                        # key exists with value null, which breaks the
                        # DigestTopic.subjects: list[str] validation. Emit an
                        # empty list for null angles rather than [""].
                        subjects=(
                            [subject["deep_angle"]] if subject.get("deep_angle") else []
                        ),
                        articles=topic_articles,
                        intro_text=subject.get("intro_text"),
                        transition_text=subject.get("transition_text"),
                        perspective_count=subject.get("perspective_count", 0),
                        bias_distribution=subject.get("bias_distribution"),
                        bias_highlights=subject.get("bias_highlights"),
                        divergence_analysis=_divergence_str,
                        divergence_level=subject.get("divergence_level"),
                        perspective_sources=subject.get("perspective_sources"),
                        representative_content_id=subject.get(
                            "representative_content_id"
                        ),
                    )
                )
            else:
                logger.warning(
                    "editorial_topic_no_articles_skipped",
                    topic_id=subject.get("topic_id", ""),
                    label=subject.get("label", ""),
                )

        # Build pepite response
        default_action = {
            "is_read": False,
            "is_saved": False,
            "is_liked": False,
            "is_dismissed": False,
        }
        pepite_response = None
        if pepite_data and pepite_data.get("content_id"):
            pepite_cid = UUID(pepite_data["content_id"])
            pepite_content = content_map.get(pepite_cid)
            if not pepite_content:
                logger.warning(
                    "editorial_pepite_not_found",
                    content_id=str(pepite_cid),
                )
            elif not pepite_content.source:
                logger.warning(
                    "editorial_pepite_missing_source",
                    content_id=str(pepite_cid),
                )
            if pepite_content and pepite_content.source:
                pepite_action = action_states_map.get(pepite_cid, default_action)
                pepite_response = PepiteResponse(
                    content_id=pepite_cid,
                    mini_editorial=pepite_data.get("mini_editorial", ""),
                    title=pepite_content.title,
                    url=pepite_content.url,
                    thumbnail_url=pepite_content.thumbnail_url,
                    published_at=pepite_content.published_at,
                    source=pepite_content.source,
                    is_read=pepite_action["is_read"],
                    is_saved=pepite_action["is_saved"],
                    is_liked=pepite_action["is_liked"],
                    is_dismissed=pepite_action["is_dismissed"],
                )
                # Also add to flat items for backward compat
                global_rank += 1
                flat_items.append(
                    DigestItem(
                        content_id=pepite_cid,
                        title=pepite_content.title,
                        url=pepite_content.url,
                        thumbnail_url=pepite_content.thumbnail_url,
                        description=pepite_content.description or None,
                        html_content=pepite_content.html_content,
                        topics=pepite_content.topics or [],
                        content_type=pepite_content.content_type,
                        duration_seconds=pepite_content.duration_seconds,
                        published_at=pepite_content.published_at,
                        is_paid=pepite_content.is_paid
                        if hasattr(pepite_content, "is_paid")
                        else False,
                        source=pepite_content.source,
                        rank=global_rank,
                        reason=pepite_data.get("mini_editorial", "Pépite du jour"),
                        badge="pepite",
                        is_read=pepite_action["is_read"],
                        is_saved=pepite_action["is_saved"],
                        is_liked=pepite_action["is_liked"],
                        is_dismissed=pepite_action["is_dismissed"],
                    )
                )

        # Build coup de coeur response
        coup_de_coeur_response = None
        if coup_de_coeur_data and coup_de_coeur_data.get("content_id"):
            cdc_cid = UUID(coup_de_coeur_data["content_id"])
            cdc_content = content_map.get(cdc_cid)
            if not cdc_content:
                logger.warning(
                    "editorial_coup_de_coeur_not_found",
                    content_id=str(cdc_cid),
                )
            elif not cdc_content.source:
                logger.warning(
                    "editorial_coup_de_coeur_missing_source",
                    content_id=str(cdc_cid),
                )
            if cdc_content and cdc_content.source:
                cdc_action = action_states_map.get(cdc_cid, default_action)
                coup_de_coeur_response = CoupDeCoeurResponse(
                    content_id=cdc_cid,
                    title=cdc_content.title,
                    source_name=coup_de_coeur_data.get(
                        "source_name", cdc_content.source.name
                    ),
                    save_count=coup_de_coeur_data.get("save_count", 0),
                    url=cdc_content.url,
                    thumbnail_url=cdc_content.thumbnail_url,
                    published_at=cdc_content.published_at,
                    source=cdc_content.source,
                    is_read=cdc_action["is_read"],
                    is_saved=cdc_action["is_saved"],
                    is_liked=cdc_action["is_liked"],
                    is_dismissed=cdc_action["is_dismissed"],
                )
                # Also add to flat items for backward compat
                global_rank += 1
                flat_items.append(
                    DigestItem(
                        content_id=cdc_cid,
                        title=cdc_content.title,
                        url=cdc_content.url,
                        thumbnail_url=cdc_content.thumbnail_url,
                        description=cdc_content.description or None,
                        html_content=cdc_content.html_content,
                        topics=cdc_content.topics or [],
                        content_type=cdc_content.content_type,
                        duration_seconds=cdc_content.duration_seconds,
                        published_at=cdc_content.published_at,
                        is_paid=cdc_content.is_paid
                        if hasattr(cdc_content, "is_paid")
                        else False,
                        source=cdc_content.source,
                        rank=global_rank,
                        reason="Coup de cœur de la communauté",
                        badge="coup_de_coeur",
                        is_read=cdc_action["is_read"],
                        is_saved=cdc_action["is_saved"],
                        is_liked=cdc_action["is_liked"],
                        is_dismissed=cdc_action["is_dismissed"],
                    )
                )

        # Build actu décalée response (serein mode only)
        actu_decalee_response = None
        if actu_decalee_data and actu_decalee_data.get("content_id"):
            ad_cid = UUID(actu_decalee_data["content_id"])
            ad_content = content_map.get(ad_cid)
            if not ad_content:
                logger.warning(
                    "editorial_actu_decalee_not_found",
                    content_id=str(ad_cid),
                )
            elif not ad_content.source:
                logger.warning(
                    "editorial_actu_decalee_missing_source",
                    content_id=str(ad_cid),
                )
            if ad_content and ad_content.source:
                ad_action = action_states_map.get(ad_cid, default_action)
                actu_decalee_response = PepiteResponse(
                    content_id=ad_cid,
                    mini_editorial=actu_decalee_data.get("mini_editorial", ""),
                    badge="actu_decalee",
                    title=ad_content.title,
                    url=ad_content.url,
                    thumbnail_url=ad_content.thumbnail_url,
                    published_at=ad_content.published_at,
                    source=ad_content.source,
                    is_read=ad_action["is_read"],
                    is_saved=ad_action["is_saved"],
                    is_liked=ad_action["is_liked"],
                    is_dismissed=ad_action["is_dismissed"],
                )
                global_rank += 1
                flat_items.append(
                    DigestItem(
                        content_id=ad_cid,
                        title=ad_content.title,
                        url=ad_content.url,
                        thumbnail_url=ad_content.thumbnail_url,
                        description=ad_content.description or None,
                        html_content=ad_content.html_content,
                        topics=ad_content.topics or [],
                        content_type=ad_content.content_type,
                        duration_seconds=ad_content.duration_seconds,
                        published_at=ad_content.published_at,
                        is_paid=ad_content.is_paid
                        if hasattr(ad_content, "is_paid")
                        else False,
                        source=ad_content.source,
                        rank=global_rank,
                        reason=actu_decalee_data.get(
                            "mini_editorial", "L'actu décalée"
                        ),
                        badge="actu_decalee",
                        is_read=ad_action["is_read"],
                        is_saved=ad_action["is_saved"],
                        is_liked=ad_action["is_liked"],
                        is_dismissed=ad_action["is_dismissed"],
                    )
                )

        # Quote for serein digest only
        quote_response = None
        if digest.is_serene:
            q = _select_daily_quote(str(digest.user_id), str(digest.target_date))
            if q:
                quote_response = QuoteResponse(
                    text=q["text"],
                    author=q["author"],
                    source=q.get("source"),
                )

        return DigestResponse(
            digest_id=digest.id,
            user_id=digest.user_id,
            target_date=digest.target_date,
            generated_at=digest.generated_at,
            mode=digest.mode or "pour_vous",
            is_serene=digest.is_serene,
            format_version="editorial_v1",
            items=flat_items,
            topics=response_topics,
            completion_threshold=len(response_topics),
            is_completed=completion is not None,
            completed_at=completion.completed_at if completion else None,
            header_text=items_data.get("header_text"),
            closure_text=items_data.get("closure_text"),
            cta_text=items_data.get("cta_text"),
            pepite=pepite_response,
            coup_de_coeur=coup_de_coeur_response,
            actu_decalee=actu_decalee_response,
            quote=quote_response,
        )

    async def _build_topics_response(
        self,
        digest: DailyDigest,
        user_id: UUID,
    ) -> DigestResponse:
        """Build DigestResponse from a topics_v1 JSONB record.

        Produces both `topics` (new grouped format) and `items` (flat legacy)
        so that old mobile clients continue to work.
        """
        topics_data = (
            digest.items.get("topics", []) if isinstance(digest.items, dict) else []
        )

        # Collect all content_ids across all topics
        all_content_ids: list[UUID] = []
        for topic in topics_data:
            for article in topic.get("articles", []):
                all_content_ids.append(UUID(article["content_id"]))

        # Batch query: completion
        completion = await self.session.scalar(
            select(DigestCompletion).where(
                and_(
                    DigestCompletion.user_id == user_id,
                    DigestCompletion.target_date == digest.target_date,
                )
            )
        )

        # Batch query: content + sources
        content_stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id.in_(all_content_ids))
        )
        content_result = await self.session.execute(content_stmt)
        content_map = {c.id: c for c in content_result.scalars().all()}

        # Batch query: action states
        action_states_map = await self._get_batch_action_states(
            user_id, all_content_ids
        )

        # Build topics + flat items
        response_topics: list[DigestTopic] = []
        flat_items: list[DigestItem] = []
        global_rank = 0

        for topic_data in topics_data:
            topic_articles: list[DigestTopicArticle] = []

            for art_data in topic_data.get("articles", []):
                content_id = UUID(art_data["content_id"])
                content = content_map.get(content_id)
                if not content or not content.source:
                    continue

                action_state = action_states_map.get(
                    content_id,
                    {
                        "is_read": False,
                        "is_saved": False,
                        "is_liked": False,
                        "is_dismissed": False,
                    },
                )

                # Rebuild breakdown
                breakdown_raw = art_data.get("breakdown") or []
                breakdown = [
                    DigestScoreBreakdown(
                        label=b.get("label", ""),
                        points=b.get("points", 0.0),
                        is_positive=b.get("is_positive", True),
                    )
                    for b in breakdown_raw
                    if isinstance(b, dict) and b.get("label")
                ]

                recommendation_reason = None
                if breakdown:
                    recommendation_reason = DigestRecommendationReason(
                        label=self._determine_top_reason(breakdown),
                        score_total=sum(b.points for b in breakdown),
                        breakdown=breakdown,
                    )

                topic_article = DigestTopicArticle(
                    content_id=content_id,
                    title=content.title,
                    url=content.url,
                    thumbnail_url=content.thumbnail_url,
                    description=content.description or None,
                    html_content=content.html_content,
                    topics=content.topics or [],
                    entities=content.entities or [],
                    content_type=content.content_type,
                    duration_seconds=content.duration_seconds,
                    published_at=content.published_at,
                    is_paid=content.is_paid if hasattr(content, "is_paid") else False,
                    source=content.source,
                    rank=art_data.get("rank", 1),
                    reason=art_data.get("reason", ""),
                    is_followed_source=art_data.get("is_followed_source", False),
                    recommendation_reason=recommendation_reason,
                    is_read=action_state["is_read"],
                    is_saved=action_state["is_saved"],
                    is_liked=action_state["is_liked"],
                    is_dismissed=action_state["is_dismissed"],
                )
                topic_articles.append(topic_article)

                # Also build flat DigestItem for backward compat
                global_rank += 1
                flat_items.append(
                    DigestItem(
                        content_id=content_id,
                        title=content.title,
                        url=content.url,
                        thumbnail_url=content.thumbnail_url,
                        description=content.description or None,
                        html_content=content.html_content,
                        topics=content.topics or [],
                        content_type=content.content_type,
                        duration_seconds=content.duration_seconds,
                        published_at=content.published_at,
                        is_paid=content.is_paid
                        if hasattr(content, "is_paid")
                        else False,
                        source=content.source,
                        rank=global_rank,
                        reason=art_data.get("reason", ""),
                        recommendation_reason=recommendation_reason,
                        is_read=action_state["is_read"],
                        is_saved=action_state["is_saved"],
                        is_liked=action_state["is_liked"],
                        is_dismissed=action_state["is_dismissed"],
                    )
                )

            response_topics.append(
                DigestTopic(
                    topic_id=topic_data.get("topic_id", ""),
                    label=topic_data.get("label", ""),
                    rank=topic_data.get("rank", 0),
                    reason=topic_data.get("reason", ""),
                    is_trending=topic_data.get("is_trending", False),
                    is_une=topic_data.get("is_une", False),
                    theme=topic_data.get("theme"),
                    topic_score=topic_data.get("topic_score", 0.0),
                    subjects=topic_data.get("subjects", []),
                    articles=topic_articles,
                )
            )

        # Quote for serein digest only
        quote_response = None
        if digest.is_serene:
            q = _select_daily_quote(str(digest.user_id), str(digest.target_date))
            if q:
                quote_response = QuoteResponse(
                    text=q["text"],
                    author=q["author"],
                    source=q.get("source"),
                )

        return DigestResponse(
            digest_id=digest.id,
            user_id=digest.user_id,
            target_date=digest.target_date,
            generated_at=digest.generated_at,
            mode=digest.mode or "pour_vous",
            is_serene=digest.is_serene,
            format_version="topics_v1",
            items=flat_items,
            topics=response_topics,
            completion_threshold=len(response_topics),
            is_completed=completion is not None,
            completed_at=completion.completed_at if completion else None,
            quote=quote_response,
        )

    async def _get_item_action_state(
        self, user_id: UUID, content_id: UUID
    ) -> dict[str, bool]:
        """Get current action state for a digest item."""
        status = await self.session.scalar(
            select(UserContentStatus).where(
                and_(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.content_id == content_id,
                )
            )
        )

        if not status:
            return {
                "is_read": False,
                "is_saved": False,
                "is_liked": False,
                "is_dismissed": False,
            }

        return {
            "is_read": status.status == ContentStatus.CONSUMED,
            "is_saved": status.is_saved,
            "is_liked": status.is_liked,
            "is_dismissed": status.is_hidden,
        }

    async def _get_batch_action_states(
        self, user_id: UUID, content_ids: list[UUID]
    ) -> dict[UUID, dict[str, bool]]:
        """Batch-fetch action states for multiple content items in one query.

        Optimized replacement for calling _get_item_action_state per item.
        Reduces N queries to 1 query for the entire digest.
        """
        if not content_ids:
            return {}

        stmt = select(UserContentStatus).where(
            and_(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids),
            )
        )
        result = await self.session.execute(stmt)
        statuses = result.scalars().all()

        return {
            status.content_id: {
                "is_read": status.status == ContentStatus.CONSUMED,
                "is_saved": status.is_saved,
                "is_liked": status.is_liked,
                "is_dismissed": status.is_hidden,
            }
            for status in statuses
        }

    async def _get_or_create_content_status(
        self, user_id: UUID, content_id: UUID
    ) -> UserContentStatus:
        """Get existing or create new UserContentStatus."""
        status = await self.session.scalar(
            select(UserContentStatus).where(
                and_(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.content_id == content_id,
                )
            )
        )

        if not status:
            status = UserContentStatus(
                id=uuid4(),
                user_id=user_id,
                content_id=content_id,
                status=ContentStatus.UNSEEN,
            )
            self.session.add(status)
            await self.session.flush()

        return status

    async def _trigger_personalization_mute(self, user_id: UUID, content_id: UUID):
        """Trigger personalization mute for content's source/theme."""
        # Get content to find source and theme with eager loading
        stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id == content_id)
        )
        result = await self.session.execute(stmt)
        content = result.scalar_one_or_none()
        if not content or not content.source:
            return

        # Mute the source via upsert pattern (same as personalization router)
        from app.services.user_service import UserService

        user_service = UserService(self.session)

        # Ensure profile exists for FK constraint
        await user_service.get_or_create_profile(str(user_id))
        await self.session.flush()

        # Upsert into UserPersonalization
        from sqlalchemy import func, text

        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_id, muted_sources=[content.source_id])
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={
                    "muted_sources": func.coalesce(
                        UserPersonalization.muted_sources, text("'{}'::uuid[]")
                    ).op("||")([content.source_id]),
                    "updated_at": func.now(),
                },
            )
        )

        await self.session.execute(stmt)

        logger.info(
            "personalization_mute_triggered",
            user_id=str(user_id),
            content_id=str(content_id),
            source_id=str(content.source_id),
        )

    async def _get_digest_action_stats(
        self, user_id: UUID, digest: DailyDigest
    ) -> dict[str, int]:
        """Count actions taken on digest items."""
        # Handle both flat and topics_v1 formats
        if isinstance(digest.items, dict) and digest.items.get("format") == "topics_v1":
            content_ids = [
                UUID(a["content_id"])
                for t in digest.items["topics"]
                for a in t["articles"]
            ]
        else:
            content_ids = [UUID(item["content_id"]) for item in digest.items]

        # Get all statuses for these content items
        stmt = select(UserContentStatus).where(
            and_(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids),
            )
        )
        result = await self.session.execute(stmt)
        statuses = result.scalars().all()

        # Count actions
        read_count = sum(1 for s in statuses if s.status == ContentStatus.CONSUMED)
        saved_count = sum(1 for s in statuses if s.is_saved)
        dismissed_count = sum(1 for s in statuses if s.is_hidden)

        return {"read": read_count, "saved": saved_count, "dismissed": dismissed_count}

    async def _update_closure_streak(self, user_id: UUID) -> dict[str, Any]:
        """Update user's closure streak for digest completion."""
        # Get or create streak record
        streak = await self.session.scalar(
            select(UserStreak).where(UserStreak.user_id == user_id)
        )

        if not streak:
            streak = UserStreak(
                id=uuid4(),
                user_id=user_id,
                week_start=date.today() - timedelta(days=date.today().weekday()),
            )
            self.session.add(streak)
            await self.session.flush()

        today = date.today()

        # Update closure streak
        if streak.last_closure_date:
            days_since = (today - streak.last_closure_date).days

            if days_since == 0:
                # Already completed today - don't increment
                pass
            elif days_since == 1:
                # Consecutive day - increment
                streak.closure_streak += 1
            else:
                # Streak broken - reset to 1
                streak.closure_streak = 1
        else:
            # First completion
            streak.closure_streak = 1

        streak.last_closure_date = today

        # Update longest closure streak
        if streak.closure_streak > streak.longest_closure_streak:
            streak.longest_closure_streak = streak.closure_streak

        # Generate message
        message = None
        if streak.closure_streak == 1:
            message = "Premier digest complété !"
        elif streak.closure_streak == 7:
            message = "Série de 7 jours ! 🔥"
        elif streak.closure_streak == 30:
            message = "Série de 30 jours ! 🎉"
        elif streak.closure_streak > 1:
            message = f"Série de {streak.closure_streak} jours !"

        return {
            "current": streak.closure_streak,
            "longest": streak.longest_closure_streak,
            "message": message,
        }

    async def _get_user_serein_enabled(self, user_id: UUID) -> bool:
        """Lit la préférence serein_enabled depuis user_preferences."""
        from app.models.user import UserPreference, UserProfile

        result = await self.session.execute(
            select(UserPreference.preference_value)
            .join(UserProfile, UserPreference.user_id == UserProfile.user_id)
            .where(
                UserProfile.user_id == user_id,
                UserPreference.preference_key == "serein_enabled",
            )
        )
        value = result.scalar_one_or_none()
        return value == "true"

    async def _get_user_digest_format(self, user_id: UUID) -> str:
        """Returns the digest format for a user.

        Legacy note: previously read from user_preferences table, but the
        digest_format preference has been deprecated. All users now receive
        the same editorial format for consistency.
        """
        return "editorial"
