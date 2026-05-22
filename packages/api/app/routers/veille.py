"""Router /api/veille — CRUD config + feed temps-réel (Story 23.1)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import sentry_sdk
import structlog
from cachetools import TTLCache
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.data.veille_presets import get_presets
from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import SourceType
from app.models.source import Source
from app.models.user_favorites import UserFavoriteInterest
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.schemas.veille import (
    VeilleAngleSuggestion,
    VeilleConfigResponse,
    VeilleConfigUpsert,
    VeilleFeedArticle,
    VeilleFeedResponse,
    VeilleKeywordResponse,
    VeillePresetResponse,
    VeilleSourceExample,
    VeilleSourceLite,
    VeilleSourceResponse,
    VeilleSourceSuggestion,
    VeilleSuggestAnglesRequest,
    VeilleSuggestAnglesResponse,
    VeilleSuggestSourcesRequest,
    VeilleSuggestSourcesResponse,
    VeilleTopicResponse,
)
from app.services.rss_parser import RSSParser
from app.services.source_service import SourceService
from app.services.user_interests_service import ensure_veille_favorite
from app.services.veille.feed_filter import fetch_veille_feed
from app.services.veille.llm import get_angle_suggester, get_source_suggester

logger = structlog.get_logger()

router = APIRouter()

# Cache examples sources : in-process (suffit V1), à migrer Redis si scale
# horizontal — TTL 24 h aligné avec la fraîcheur attendue d'un aperçu.
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
    """Charge topics + sources + keywords pour la réponse."""
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

    keywords_rows = (
        (
            await db.execute(
                select(VeilleKeyword)
                .where(VeilleKeyword.veille_config_id == cfg.id)
                .order_by(VeilleKeyword.position, VeilleKeyword.created_at)
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
        status=cfg.status,  # type: ignore[arg-type]
        created_at=cfg.created_at,
        updated_at=cfg.updated_at,
        purpose=cfg.purpose,
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
        keywords=[
            VeilleKeywordResponse(id=kw.id, keyword=kw.keyword, position=kw.position)
            for kw in keywords_rows
        ],
    )


def _source_theme_for(veille_theme_id: str) -> str:
    """Mappe le theme_id de la veille vers un theme valide pour la table `sources`.

    La contrainte `ck_source_theme_valid` autorise un set fini ; le thème "other"
    de la veille (Story 23.3, tuile "Autre" en mobile) est mappé vers "custom"
    qui existe déjà dans la contrainte. Pas de migration nécessaire.
    """
    return "custom" if veille_theme_id == "other" else veille_theme_id


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
        theme=_source_theme_for(theme_id),
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

    if cfg is None:
        cfg = VeilleConfig(
            id=uuid4(),
            user_id=user_uuid,
            theme_id=body.theme_id,
            theme_label=body.theme_label,
            status=VeilleStatus.ACTIVE.value,
            purpose=body.purpose,
            editorial_brief=body.editorial_brief,
            preset_id=body.preset_id,
        )
        db.add(cfg)
        await db.flush()
    else:
        cfg.theme_id = body.theme_id
        cfg.theme_label = body.theme_label
        cfg.purpose = body.purpose
        cfg.editorial_brief = body.editorial_brief
        cfg.preset_id = body.preset_id

    # Replace topics + sources + keywords atomically.
    await db.execute(delete(VeilleTopic).where(VeilleTopic.veille_config_id == cfg.id))
    await db.execute(
        delete(VeilleSource).where(VeilleSource.veille_config_id == cfg.id)
    )
    await db.execute(
        delete(VeilleKeyword).where(VeilleKeyword.veille_config_id == cfg.id)
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

    for idx, kw in enumerate(body.keywords):
        db.add(
            VeilleKeyword(
                veille_config_id=cfg.id,
                keyword=kw.keyword,
                position=idx,
            )
        )

    if not (body.topics or seen_source_ids or body.keywords):
        await db.rollback()
        raise HTTPException(
            status_code=422,
            detail="Sélectionne au moins un thème, une source ou un mot-clé.",
        )

    # La veille est un favori d'intérêt — on garantit sa présence dans
    # user_favorite_interests à chaque upsert (idempotent).
    await ensure_veille_favorite(db, user_uuid, cfg.id)

    await db.commit()
    await db.refresh(cfg)

    try:
        from app.services.posthog_client import get_posthog_client

        get_posthog_client().capture(
            user_id=user_uuid,
            event="veille_config_submitted",
            properties={
                "source_count": len(seen_source_ids),
                "topic_count": len(body.topics),
                "keyword_count": len(body.keywords),
                "theme_id": body.theme_id,
                "preset_id": body.preset_id,
            },
        )
    except Exception:  # noqa: BLE001 — métrique fire-and-forget
        logger.warning("veille.posthog_capture_failed", exc_info=True)

    return await _hydrate_response(db, cfg)


@router.delete("/config", status_code=204)
async def delete_config(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    user_uuid = UUID(current_user_id)
    cfg = await _get_active_config(db, user_uuid)
    if cfg is None:
        return None
    # Retire d'abord le favori, puis archive la config — même transaction,
    # garantit qu'aucun favori orphelin ne survit à un crash entre les deux.
    await db.execute(
        delete(UserFavoriteInterest).where(
            UserFavoriteInterest.user_id == user_uuid,
            UserFavoriteInterest.veille_config_id == cfg.id,
        )
    )
    cfg.status = VeilleStatus.ARCHIVED.value
    await db.commit()
    return None


# ─── Feed temps-réel ─────────────────────────────────────────────────────────


@router.get("/feed", response_model=VeilleFeedResponse)
async def get_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    serein: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie les articles matchant la veille active de l'utilisateur."""
    user_uuid = UUID(current_user_id)
    items_with_axes, has_more = await fetch_veille_feed(
        db,
        user_uuid,
        limit=limit,
        offset=offset,
        serein=serein,
    )
    return VeilleFeedResponse(
        items=[
            VeilleFeedArticle(
                id=content.id,
                title=content.title,
                url=content.url,
                description=content.description,
                published_at=content.published_at,
                source=VeilleSourceLite.model_validate(content.source),
                theme=content.theme,
                topics=list(content.topics or []),
                thumbnail_url=content.thumbnail_url,
                matched_on=axes,  # type: ignore[arg-type]
            )
            for content, axes in items_with_axes
        ],
        total=len(items_with_axes),
        limit=limit,
        offset=offset,
        has_more=has_more,
    )


# ─── Presets ─────────────────────────────────────────────────────────────────


@router.get("/presets", response_model=list[VeillePresetResponse])
async def list_presets(db: AsyncSession = Depends(get_db)):
    """Liste les pré-sets V1 affichés en bas du Step 1 (« Inspirations »)."""
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


# ─── Source examples (preview Step 3) ────────────────────────────────────────


async def _fetch_source_examples(
    db: AsyncSession, source_id: UUID
) -> list[VeilleSourceExample]:
    """Renvoie jusqu'à 2 exemples récents d'une source. Cache TTL 24 h."""
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
    UUID(current_user_id)
    return await _fetch_source_examples(db, source_id)


# ─── Suggesters LLM (Story 23.3) ─────────────────────────────────────────────


@router.post("/suggest/angles", response_model=VeilleSuggestAnglesResponse)
async def suggest_angles(
    body: VeilleSuggestAnglesRequest,
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie 5-8 angles + mots-clés explicites pour un thème + brief.

    Appel synchrone Mistral (~10-15s), cache TTL 24h sur (theme + brief).
    Mobile affiche un HaloLoader pendant l'appel.
    """
    UUID(current_user_id)
    suggester = get_angle_suggester()
    angles = await suggester.suggest_angles(
        theme_id=body.theme_id,
        theme_label=body.theme_label,
        brief=body.brief,
    )
    return VeilleSuggestAnglesResponse(
        angles=[
            VeilleAngleSuggestion(
                title=a.title,
                keywords=a.keywords,
                reason=a.reason,
            )
            for a in angles
        ]
    )


@router.post("/suggest/sources", response_model=VeilleSuggestSourcesResponse)
async def suggest_sources(
    body: VeilleSuggestSourcesRequest,
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie 5-10 sources rankées pour un thème + angles + mots-clés + brief.

    Appel synchrone Mistral (~10-15s), cache TTL 24h. Si LLM KO, renvoie une
    liste vide — mobile bascule sur le mode advanced URL.
    """
    UUID(current_user_id)
    suggester = get_source_suggester()
    sources = await suggester.suggest_sources(
        theme_id=body.theme_id,
        theme_label=body.theme_label,
        brief=body.brief,
        angles=body.angles,
        keywords=body.keywords,
    )
    return VeilleSuggestSourcesResponse(
        sources=[
            VeilleSourceSuggestion(
                name=s.name,
                url=s.url,
                why=s.why,
                relevance_score=s.relevance_score,
            )
            for s in sources
        ]
    )


# ─── Shim 410 Gone (clients mobile non mis à jour) ───────────────────────────
#
# Les endpoints de suggestions LLM et de deliveries sont retirés (Story 23.1).
# Les versions mobile pré-23.1 peuvent encore les appeler ; on renvoie 410 Gone
# avec un message clair plutôt qu'un 404 silencieux. Drop définitif en PR-4
# après bump de la version min mobile (cf. R5 story 23.1).


def _gone(reason: str = "Endpoint retiré — mettez à jour l'application.") -> None:
    sentry_sdk.capture_message(
        "veille.legacy_endpoint_called",
        level="info",
        extras={"reason": reason},
    )
    raise HTTPException(status_code=410, detail=reason)


@router.post("/suggestions/topics", status_code=410)
async def suggest_topics_gone() -> None:
    _gone("Les suggestions de topics LLM ont été retirées.")


@router.post("/suggestions/sources", status_code=410)
async def suggest_sources_gone() -> None:
    _gone("Les suggestions de sources LLM ont été retirées.")


@router.get("/deliveries", status_code=410)
async def list_deliveries_gone() -> None:
    _gone("Les livraisons asynchrones ont été remplacées par /api/veille/feed.")


@router.get("/deliveries/{delivery_id}", status_code=410)
async def get_delivery_gone(delivery_id: UUID) -> None:
    _gone("Les livraisons asynchrones ont été remplacées par /api/veille/feed.")


@router.post("/deliveries/generate", status_code=410)
async def force_generate_gone() -> None:
    _gone("La génération asynchrone a été retirée.")


@router.post("/deliveries/generate-first", status_code=410)
async def generate_first_delivery_gone() -> None:
    _gone("La génération asynchrone a été retirée.")
