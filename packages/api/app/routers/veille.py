"""Router /api/veille — CRUD config, suggestions LLM, livraisons.

Pool DB : 1 session par requête via `Depends(get_db)`. Les /suggestions
appellent le LLM mais restent bornées à la durée d'une requête utilisateur
(vs le scanner background, cf. `veille_generation_job` qui doit libérer la
session avant le LLM).
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

import httpx
import sentry_sdk
import structlog
from cachetools import TTLCache
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.data.veille_presets import get_presets
from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.jobs.veille_generation_job import run_veille_generation_for_config
from app.models.content import Content
from app.models.enums import SourceType
from app.models.source import Source
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleGenerationState,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.schemas.veille import (
    VeilleConfigPatch,
    VeilleConfigResponse,
    VeilleConfigUpsert,
    VeilleDeliveryListItem,
    VeilleDeliveryResponse,
    VeilleGenerateFirstResponse,
    VeilleGenerateRequest,
    VeillePresetResponse,
    VeilleSourceExample,
    VeilleSourceLite,
    VeilleSourceResponse,
    VeilleSourceSuggestion,
    VeilleSourceSuggestionsResponse,
    VeilleSuggestSourcesRequest,
    VeilleSuggestTopicsRequest,
    VeilleTopicResponse,
    VeilleTopicSuggestion,
)
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.rss_parser import RSSParser
from app.services.source_service import SourceService
from app.services.veille.digest_builder import VeilleDigestBuilder
from app.services.veille.scheduling import compute_next_scheduled_at
from app.services.veille.source_suggester import (
    SourceSuggester,
    get_source_suggester,
)
from app.services.veille.topic_suggester import (
    TopicSuggester,
    get_topic_suggester,
)
from app.utils.time import today_paris

logger = structlog.get_logger()

router = APIRouter()

# Cache examples sources : in-process (suffit V1), à migrer Redis si scale
# horizontal — cf. memory note. TTL 24 h aligné avec la fraîcheur attendue
# d'un aperçu de feed.
_SOURCE_EXAMPLES_CACHE: TTLCache = TTLCache(maxsize=512, ttl=86400)
_SOURCE_EXAMPLES_LIMIT = 2
_SOURCE_EXAMPLES_LOOKBACK_DAYS = 30
_SOURCE_EXAMPLES_EXCERPT_MAX = 120


# ─── Helpers ─────────────────────────────────────────────────────────────────


async def _get_active_config(db: AsyncSession, user_id: UUID) -> VeilleConfig | None:
    stmt = select(VeilleConfig).where(
        VeilleConfig.user_id == user_id,
        VeilleConfig.status == VeilleStatus.ACTIVE.value,
    )
    return (await db.execute(stmt)).scalars().first()


async def _hydrate_response(
    db: AsyncSession, cfg: VeilleConfig
) -> VeilleConfigResponse:
    """Charge topics + sources (avec hydratation Source) pour la réponse."""
    topics_rows = (
        (
            await db.execute(
                select(VeilleTopic)
                .where(VeilleTopic.veille_config_id == cfg.id)
                .order_by(VeilleTopic.position, VeilleTopic.created_at)
            )
        )
        .scalars()
        .all()
    )

    sources_rows = (
        (
            await db.execute(
                select(VeilleSource)
                .where(VeilleSource.veille_config_id == cfg.id)
                .order_by(VeilleSource.position, VeilleSource.created_at)
            )
        )
        .scalars()
        .all()
    )

    source_ids = [vs.source_id for vs in sources_rows]
    sources_by_id: dict[UUID, Source] = {}
    if source_ids:
        for src in (
            (await db.execute(select(Source).where(Source.id.in_(source_ids))))
            .scalars()
            .all()
        ):
            sources_by_id[src.id] = src

    return VeilleConfigResponse(
        id=cfg.id,
        user_id=cfg.user_id,
        theme_id=cfg.theme_id,
        theme_label=cfg.theme_label,
        frequency=cfg.frequency,  # type: ignore[arg-type]
        day_of_week=cfg.day_of_week,
        delivery_hour=cfg.delivery_hour,
        timezone=cfg.timezone,
        status=cfg.status,  # type: ignore[arg-type]
        last_delivered_at=cfg.last_delivered_at,
        next_scheduled_at=cfg.next_scheduled_at,
        created_at=cfg.created_at,
        updated_at=cfg.updated_at,
        purpose=cfg.purpose,
        purpose_other=cfg.purpose_other,
        editorial_brief=cfg.editorial_brief,
        preset_id=cfg.preset_id,
        topics=[
            VeilleTopicResponse(
                id=t.id,
                topic_id=t.topic_id,
                label=t.label,
                kind=t.kind,  # type: ignore[arg-type]
                reason=t.reason,
                position=t.position,
            )
            for t in topics_rows
        ],
        sources=[
            VeilleSourceResponse(
                id=vs.id,
                source=VeilleSourceLite.model_validate(sources_by_id[vs.source_id]),
                kind=vs.kind,  # type: ignore[arg-type]
                why=vs.why,
                position=vs.position,
            )
            for vs in sources_rows
            if vs.source_id in sources_by_id
        ],
    )


async def _resolve_source_id(
    db: AsyncSession,
    selection,
    theme_id: str,
) -> UUID:
    """Renvoie un source_id existant ou ingère le candidat niche."""
    if selection.source_id is not None:
        return selection.source_id
    if selection.niche_candidate is None:
        raise HTTPException(
            status_code=400,
            detail="source_selection: source_id ou niche_candidate requis.",
        )

    cand = selection.niche_candidate
    source_service = SourceService(db)
    detected = await source_service.detect_source(cand.url)

    existing = (
        (await db.execute(select(Source).where(Source.feed_url == detected.feed_url)))
        .scalars()
        .first()
    )
    if existing is not None:
        return existing.id

    try:
        source_type = SourceType(detected.detected_type)
    except ValueError:
        source_type = SourceType.ARTICLE

    new_source = Source(
        id=uuid4(),
        name=cand.name or detected.name,
        url=cand.url,
        feed_url=detected.feed_url,
        type=source_type,
        theme=theme_id,
        description=detected.description,
        logo_url=detected.logo_url,
        is_curated=False,
        is_active=True,
    )
    db.add(new_source)
    await db.flush()
    logger.info(
        "veille.source_ingested",
        source_id=str(new_source.id),
        feed_url=new_source.feed_url,
    )
    return new_source.id


# ─── Endpoints config ────────────────────────────────────────────────────────


@router.get("/config", response_model=VeilleConfigResponse)
async def get_config(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        raise HTTPException(
            status_code=404, detail="Aucune veille active pour cet utilisateur."
        )
    return await _hydrate_response(db, cfg)


@router.post("/config", response_model=VeilleConfigResponse)
async def upsert_config(
    body: VeilleConfigUpsert,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)

    cfg = await _get_active_config(db, user_uuid)
    now = datetime.now(UTC)

    if cfg is None:
        cfg = VeilleConfig(
            id=uuid4(),
            user_id=user_uuid,
            theme_id=body.theme_id,
            theme_label=body.theme_label,
            frequency=body.frequency,
            day_of_week=body.day_of_week,
            delivery_hour=body.delivery_hour,
            timezone=body.timezone,
            status=VeilleStatus.ACTIVE.value,
            purpose=body.purpose,
            purpose_other=body.purpose_other,
            editorial_brief=body.editorial_brief,
            preset_id=body.preset_id,
        )
        db.add(cfg)
        await db.flush()
    else:
        cfg.theme_id = body.theme_id
        cfg.theme_label = body.theme_label
        cfg.frequency = body.frequency
        cfg.day_of_week = body.day_of_week
        cfg.delivery_hour = body.delivery_hour
        cfg.timezone = body.timezone
        cfg.purpose = body.purpose
        cfg.purpose_other = body.purpose_other
        cfg.editorial_brief = body.editorial_brief
        cfg.preset_id = body.preset_id

    # Replace topics + sources atomically.
    await db.execute(delete(VeilleTopic).where(VeilleTopic.veille_config_id == cfg.id))
    await db.execute(
        delete(VeilleSource).where(VeilleSource.veille_config_id == cfg.id)
    )

    for idx, t in enumerate(body.topics):
        db.add(
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id=t.topic_id,
                label=t.label,
                kind=t.kind,
                reason=t.reason,
                position=idx,
            )
        )

    seen_source_ids: set[UUID] = set()
    for idx, sel in enumerate(body.source_selections):
        source_id = await _resolve_source_id(db, sel, body.theme_id)
        if source_id in seen_source_ids:
            continue
        seen_source_ids.add(source_id)
        db.add(
            VeilleSource(
                veille_config_id=cfg.id,
                source_id=source_id,
                kind=sel.kind,
                why=sel.why,
                position=idx,
            )
        )

    cfg.next_scheduled_at = compute_next_scheduled_at(
        frequency=cfg.frequency,
        day_of_week=cfg.day_of_week,
        delivery_hour=cfg.delivery_hour,
        timezone=cfg.timezone,
        last_delivered_at=cfg.last_delivered_at,
        now=now,
    )

    await db.commit()
    await db.refresh(cfg)
    return await _hydrate_response(db, cfg)


@router.patch("/config", response_model=VeilleConfigResponse)
async def patch_config(
    patch: VeilleConfigPatch,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        raise HTTPException(
            status_code=404, detail="Aucune veille active pour cet utilisateur."
        )

    updates = patch.model_dump(exclude_unset=True)
    if not updates:
        return await _hydrate_response(db, cfg)

    schedule_dirty = bool(
        {"frequency", "day_of_week", "delivery_hour", "timezone"} & updates.keys()
    )

    for field, value in updates.items():
        setattr(cfg, field, value)

    if schedule_dirty:
        cfg.next_scheduled_at = compute_next_scheduled_at(
            frequency=cfg.frequency,
            day_of_week=cfg.day_of_week,
            delivery_hour=cfg.delivery_hour,
            timezone=cfg.timezone,
            last_delivered_at=cfg.last_delivered_at,
            now=datetime.now(UTC),
        )

    await db.commit()
    await db.refresh(cfg)
    return await _hydrate_response(db, cfg)


@router.delete("/config", status_code=204)
async def delete_config(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        # Idempotent : pas d'erreur si déjà supprimé.
        return None
    cfg.status = VeilleStatus.ARCHIVED.value
    await db.commit()
    return None


# ─── Endpoints presets ───────────────────────────────────────────────────────


@router.get("/presets", response_model=list[VeillePresetResponse])
async def list_presets(db: AsyncSession = Depends(get_db)):
    """Liste les pré-sets V1 affichés en bas du Step 1 (« Inspirations »).

    Pas d'auth : la liste est publique (utilisée pendant l'onboarding).
    Les sources curées sont résolues au runtime depuis la table `sources`.
    """
    out: list[VeillePresetResponse] = []
    for preset in get_presets():
        srcs = (
            (
                await db.execute(
                    select(Source)
                    .where(
                        Source.theme == preset["theme_id"],
                        Source.is_curated.is_(True),
                        Source.is_active.is_(True),
                    )
                    .order_by(Source.name)
                    .limit(6)
                )
            )
            .scalars()
            .all()
        )
        out.append(
            VeillePresetResponse(
                slug=preset["slug"],
                label=preset["label"],
                accroche=preset["accroche"],
                theme_id=preset["theme_id"],
                theme_label=preset["theme_label"],
                topics=preset["topics"],
                purposes=preset["purposes"],
                editorial_brief=preset["editorial_brief"],
                sources=[VeilleSourceLite.model_validate(s) for s in srcs],
            )
        )
    return out


# ─── Endpoints suggestions ───────────────────────────────────────────────────


@router.post(
    "/suggestions/topics",
    response_model=list[VeilleTopicSuggestion],
)
async def suggest_topics(
    req: VeilleSuggestTopicsRequest,
    suggester: TopicSuggester = Depends(get_topic_suggester),
    current_user_id: str = Depends(get_current_user_id),
):
    UUID(current_user_id)  # validate JWT subject
    items = await suggester.suggest_topics(
        theme_id=req.theme_id,
        theme_label=req.theme_label,
        selected_topic_ids=req.selected_topic_ids,
        excluded_topic_ids=req.exclude_topic_ids,
        purpose=req.purpose,
        purpose_other=req.purpose_other,
        editorial_brief=req.editorial_brief,
    )
    return [
        VeilleTopicSuggestion(topic_id=it.topic_id, label=it.label, reason=it.reason)
        for it in items
    ]


@router.post(
    "/suggestions/sources",
    response_model=VeilleSourceSuggestionsResponse,
)
async def suggest_sources(
    req: VeilleSuggestSourcesRequest,
    db: AsyncSession = Depends(get_db),
    suggester: SourceSuggester = Depends(get_source_suggester),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    try:
        result = await suggester.suggest_sources(
            session=db,
            user_id=user_uuid,
            theme_id=req.theme_id,
            topic_labels=req.topic_labels,
            excluded_source_ids=req.exclude_source_ids,
            purpose=req.purpose,
            purpose_other=req.purpose_other,
            editorial_brief=req.editorial_brief,
        )
        await db.commit()  # persiste les éventuelles ingestions niche
    except SQLAlchemyError as exc:
        await db.rollback()
        sentry_sdk.capture_exception(exc)
        logger.error("veille.suggest_sources_db_error", error=str(exc))
        raise HTTPException(
            status_code=503,
            detail="Service temporairement indisponible.",
        ) from exc
    except (httpx.TimeoutException, httpx.HTTPError) as exc:
        sentry_sdk.capture_exception(exc)
        logger.error("veille.suggest_sources_llm_error", error=str(exc))
        raise HTTPException(
            status_code=503,
            detail="Suggestions LLM indisponibles.",
        ) from exc

    return VeilleSourceSuggestionsResponse(
        followed=[
            VeilleSourceSuggestion(
                source_id=it.source_id,
                name=it.name,
                url=it.url,
                feed_url=it.feed_url,
                theme=it.theme,
                why=it.why,
            )
            for it in result.followed
        ],
        niche=[
            VeilleSourceSuggestion(
                source_id=it.source_id,
                name=it.name,
                url=it.url,
                feed_url=it.feed_url,
                theme=it.theme,
                why=it.why,
            )
            for it in result.niche
        ],
    )


# ─── Endpoints deliveries ────────────────────────────────────────────────────


@router.get("/deliveries", response_model=list[VeilleDeliveryListItem])
async def list_deliveries(
    limit: int = Query(20, ge=1, le=100),
    before: datetime | None = None,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        return []

    stmt = (
        select(VeilleDelivery)
        .where(VeilleDelivery.veille_config_id == cfg.id)
        .order_by(VeilleDelivery.target_date.desc())
        .limit(limit)
    )
    if before is not None:
        stmt = stmt.where(VeilleDelivery.created_at < before)

    rows = (await db.execute(stmt)).scalars().all()
    return [
        VeilleDeliveryListItem(
            id=r.id,
            veille_config_id=r.veille_config_id,
            target_date=r.target_date,
            generation_state=r.generation_state,  # type: ignore[arg-type]
            item_count=len(r.items or []),
            generated_at=r.generated_at,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.get("/deliveries/{delivery_id}", response_model=VeilleDeliveryResponse)
async def get_delivery(
    delivery_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    delivery = (
        (
            await db.execute(
                select(VeilleDelivery).where(VeilleDelivery.id == delivery_id)
            )
        )
        .scalars()
        .first()
    )
    if delivery is None:
        raise HTTPException(404, "Livraison introuvable.")

    cfg = (
        (
            await db.execute(
                select(VeilleConfig).where(VeilleConfig.id == delivery.veille_config_id)
            )
        )
        .scalars()
        .first()
    )
    if cfg is None or cfg.user_id != user_uuid:
        raise HTTPException(404, "Livraison introuvable.")

    return VeilleDeliveryResponse.model_validate(delivery)


@router.post("/deliveries/generate", response_model=VeilleDeliveryResponse)
async def force_generate(
    req: VeilleGenerateRequest,
    current_user_id: str = Depends(get_current_user_id),
):
    """Admin/debug : force la génération de la livraison du jour.

    Désactivé en production sauf si la config explicite l'autorise.
    """
    settings = get_settings()
    if settings.environment == "production":
        raise HTTPException(
            status_code=403,
            detail="Endpoint debug désactivé en production.",
        )

    user_uuid = UUID(current_user_id)
    # Pas de Depends(get_db) — sinon la session resterait checked-out
    # pendant tout l'appel LLM (3-5 s), annulant le bénéfice Option C.
    async with safe_async_session() as s:
        cfg = await _get_active_config(s, user_uuid)
    if cfg is None:
        raise HTTPException(status_code=404, detail="Aucune veille active à générer.")

    target = req.target_date or today_paris()

    llm = EditorialLLMClient()
    try:
        builder = VeilleDigestBuilder(llm=llm, session_maker=safe_async_session)
        delivery = await run_veille_generation_for_config(
            cfg.id,
            target_date=target,
            session_maker=safe_async_session,
            builder=builder,
        )
    finally:
        await llm.close()

    return VeilleDeliveryResponse.model_validate(delivery)


# ─── First delivery (génération immédiate post-onboarding) ───────────────────


_FIRST_DELIVERY_RETRY_DELAY_SECONDS = 60


async def _mark_delivery_failed(
    delivery_id: UUID,
    exc: BaseException,
    *,
    log_event: str,
    extra_log: dict,
) -> None:
    """UPDATE veille_deliveries → FAILED + sentry capture (idempotent best-effort).

    Best-effort : si l'UPDATE lui-même échoue (pool dead, DB down) on log
    sans re-raise pour ne pas masquer l'exception métier. Le cleanup script
    périodique (hors scope, issue #cleanup-stuck-rows) servira de filet.
    """
    error_class = type(exc).__name__
    error_msg = f"{error_class}: {str(exc)[:480]}"
    try:
        async with safe_async_session() as s:
            delivery = (
                await s.execute(
                    select(VeilleDelivery).where(VeilleDelivery.id == delivery_id)
                )
            ).scalar_one_or_none()
            if delivery is None:
                logger.error(
                    "veille.delivery_failed_row_missing",
                    delivery_id=str(delivery_id),
                    **extra_log,
                )
                return
            delivery.generation_state = VeilleGenerationState.FAILED.value
            delivery.last_error = error_msg
            delivery.finished_at = datetime.now(UTC)
            delivery.attempts = (delivery.attempts or 0) + 1
            await s.commit()
    except Exception as commit_exc:  # noqa: BLE001 — best-effort
        logger.error(
            "veille.delivery_failed_persist_error",
            delivery_id=str(delivery_id),
            error=str(commit_exc),
            **extra_log,
        )

    sentry_sdk.capture_exception(exc)
    logger.error(
        log_event,
        delivery_id=str(delivery_id),
        error_class=error_class,
        error_msg=str(exc)[:480],
        **extra_log,
    )


async def _run_first_delivery_with_retry(
    config_id: UUID,
    target_date: date,
    delivery_id: UUID,
) -> None:
    """BackgroundTask : retry 1× T+60s puis FAILED + sentry si 2e échec.

    Appelé après le 202 du POST /generate-first. La row VeilleDelivery a déjà
    été créée en PENDING par le handler ; `run_veille_generation_for_config`
    fait son propre UPSERT et la passe à RUNNING puis SUCCEEDED.

    Si la 1re tentative échoue (typiquement EDBHANDLEREXITED transitoire),
    on attend 60 s et on retente une seule fois. La 2e ouverture de session
    via `safe_async_session` repart sur une connexion saine.
    """
    llm = EditorialLLMClient()
    try:
        for attempt in (1, 2):
            try:
                builder = VeilleDigestBuilder(llm=llm, session_maker=safe_async_session)
                await run_veille_generation_for_config(
                    config_id,
                    target_date=target_date,
                    session_maker=safe_async_session,
                    builder=builder,
                )
                return
            except Exception as exc:  # noqa: BLE001 — terminal handler ci-dessous
                if attempt == 1:
                    logger.warning(
                        "veille.first_delivery_failed_will_retry",
                        config_id=str(config_id),
                        delivery_id=str(delivery_id),
                        error=str(exc),
                    )
                    await asyncio.sleep(_FIRST_DELIVERY_RETRY_DELAY_SECONDS)
                    continue
                await _mark_delivery_failed(
                    delivery_id,
                    exc,
                    log_event="veille.first_delivery_failed_terminal",
                    extra_log={
                        "config_id": str(config_id),
                        "attempts": attempt,
                    },
                )
                return
    finally:
        await llm.close()


@router.post(
    "/deliveries/generate-first",
    status_code=202,
    response_model=VeilleGenerateFirstResponse,
)
async def generate_first_delivery(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Lance la génération immédiate du premier digest après l'onboarding.

    Crée une row VeilleDelivery en PENDING tout de suite pour que le mobile
    puisse poll GET /deliveries/{id} pendant que le BackgroundTask tourne.
    Refuse si une livraison existe déjà pour cette config (anti-doublon).
    """
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        raise HTTPException(status_code=404, detail="Aucune veille active.")

    existing = (
        await db.execute(
            select(VeilleDelivery.id)
            .where(VeilleDelivery.veille_config_id == cfg.id)
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=403, detail="Première livraison déjà générée.")

    target = today_paris()
    delivery_id = uuid4()
    db.add(
        VeilleDelivery(
            id=delivery_id,
            veille_config_id=cfg.id,
            target_date=target,
            generation_state=VeilleGenerationState.PENDING.value,
        )
    )
    await db.commit()

    background_tasks.add_task(
        _run_first_delivery_with_retry,
        config_id=cfg.id,
        target_date=target,
        delivery_id=delivery_id,
    )
    return VeilleGenerateFirstResponse(
        delivery_id=delivery_id,
        estimated_seconds=60,
    )


# ─── Source examples (preview Step 3) ────────────────────────────────────────


async def _fetch_source_examples(
    db: AsyncSession, source_id: UUID
) -> list[VeilleSourceExample]:
    """Renvoie jusqu'à 2 exemples récents d'une source. Cache TTL 24 h.

    1. Tente le catalogue local `contents` (filtré 30 j) — chemin nominal.
    2. Si vide, fallback RSS via `RSSParser.parse(feed_url)` pour les sources
       fraîchement ingérées (niche).
    3. Cache la réponse 24 h en mémoire (cf. limites scaling : à migrer Redis
       si N workers > 2).
    """
    cache_key = str(source_id)
    if cache_key in _SOURCE_EXAMPLES_CACHE:
        return _SOURCE_EXAMPLES_CACHE[cache_key]

    cutoff = datetime.now(UTC) - timedelta(days=_SOURCE_EXAMPLES_LOOKBACK_DAYS)
    contents = (
        (
            await db.execute(
                select(Content)
                .where(
                    Content.source_id == source_id,
                    Content.published_at >= cutoff,
                )
                .order_by(Content.published_at.desc())
                .limit(_SOURCE_EXAMPLES_LIMIT)
            )
        )
        .scalars()
        .all()
    )
    if contents:
        examples = [
            VeilleSourceExample(
                title=c.title,
                url=c.url,
                published_at=c.published_at,
                excerpt=(c.description or "")[:_SOURCE_EXAMPLES_EXCERPT_MAX],
            )
            for c in contents
        ]
        _SOURCE_EXAMPLES_CACHE[cache_key] = examples
        return examples

    # Fallback RSS pour sources niche fraîchement ingérées (pas encore
    # crawlées par le scanner).
    source = (
        (await db.execute(select(Source).where(Source.id == source_id)))
        .scalars()
        .first()
    )
    if source is None or not source.feed_url:
        _SOURCE_EXAMPLES_CACHE[cache_key] = []
        return []

    parser = RSSParser()
    try:
        feed = await parser.parse(source.feed_url)
    except Exception as exc:
        logger.info(
            "veille.source_examples_rss_failed",
            source_id=str(source_id),
            feed_url=source.feed_url,
            error=str(exc),
        )
        _SOURCE_EXAMPLES_CACHE[cache_key] = []
        return []
    finally:
        await parser.close()

    # feedparser renvoie un FeedParserDict (attr-access) ; les tests mock un
    # dict standard. On couvre les deux formes.
    entries = (
        getattr(feed, "entries", None)
        or (feed.get("entries") if isinstance(feed, dict) else None)
        or []
    )
    examples = []
    for entry in entries[:_SOURCE_EXAMPLES_LIMIT]:
        title = entry.get("title") or ""
        link = entry.get("link") or ""
        if not title or not link:
            continue
        published_at: datetime | None = None
        published_parsed = entry.get("published_parsed")
        if published_parsed:
            try:
                published_at = datetime(*published_parsed[:6], tzinfo=UTC)
            except (TypeError, ValueError):
                published_at = None
        excerpt = (entry.get("summary") or "")[:_SOURCE_EXAMPLES_EXCERPT_MAX]
        examples.append(
            VeilleSourceExample(
                title=title,
                url=link,
                published_at=published_at,
                excerpt=excerpt,
            )
        )
    _SOURCE_EXAMPLES_CACHE[cache_key] = examples
    return examples


@router.get(
    "/sources/{source_id}/examples",
    response_model=list[VeilleSourceExample],
)
async def get_source_examples(
    source_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie un aperçu (≤2 articles) pour rassurer l'utilisateur au Step 3."""
    UUID(current_user_id)  # validate JWT subject
    return await _fetch_source_examples(db, source_id)
