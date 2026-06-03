"""Router /api/veille — CRUD config + feed temps-réel (Story 23.1)."""

from __future__ import annotations

import re
import unicodedata
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import sentry_sdk
import structlog
from cachetools import TTLCache
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import case, delete, or_, select
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
    VeilleResolveTopicRequest,
    VeilleResolveTopicResponse,
    VeilleSourceExample,
    VeilleSourceLite,
    VeilleSourceResponse,
    VeilleSourceSuggestion,
    VeilleSuggestAnglesRequest,
    VeilleSuggestAnglesResponse,
    VeilleSuggestSourcesRequest,
    VeilleSuggestSourcesResponse,
    VeilleTopicResponse,
    VeilleUnconnectedSource,
)
from app.services.ml.topic_enrichment_service import get_topic_enrichment_service
from app.services.rss_parser import RSSParser
from app.services.source_service import SourceService
from app.services.user_interests_service import ensure_veille_favorite
from app.services.veille.feed_filter import fetch_veille_feed, load_veille_filters
from app.services.veille.llm import get_angle_suggester, get_source_suggester

logger = structlog.get_logger()

router = APIRouter()

# Cache examples sources : in-process (suffit V1), à migrer Redis si scale
# horizontal — TTL 24 h aligné avec la fraîcheur attendue d'un aperçu.
_SOURCE_EXAMPLES_CACHE: TTLCache = TTLCache(maxsize=512, ttl=86400)
_SOURCE_EXAMPLES_LIMIT = 2
_SOURCE_EXAMPLES_LOOKBACK_DAYS = 30
_SOURCE_EXAMPLES_EXCERPT_MAX = 120


def _slugify_topic_id(raw: str) -> str:
    """Slug court compatible `VeilleTopicSelection.topic_id`."""
    normalized = unicodedata.normalize("NFKD", raw.strip().lower())
    ascii_only = "".join(c for c in normalized if not unicodedata.combining(c))
    cleaned = re.sub(r"[^a-z0-9\s-]", "", ascii_only)
    cleaned = re.sub(r"\s+", "-", cleaned)
    cleaned = re.sub(r"-+", "-", cleaned).strip("-")
    base = cleaned or "sujet"
    return f"custom-{base[:60]}"


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

    # Split mots-clés : globaux (veille_topic_id NULL) vs grappes d'angles.
    global_keywords = [kw for kw in keywords_rows if kw.veille_topic_id is None]
    keywords_by_topic: dict[UUID, list[str]] = {}
    for kw in keywords_rows:
        if kw.veille_topic_id is not None:
            keywords_by_topic.setdefault(kw.veille_topic_id, []).append(kw.keyword)

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
                keywords=keywords_by_topic.get(t.id, []),
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
            for kw in global_keywords
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
) -> tuple[UUID, bool]:
    """Renvoie `(source_id, created)`.

    `created=True` uniquement quand une nouvelle ligne `Source` niche vient
    d'être insérée (→ l'appelant doit enfiler un `sync_source` immédiat pour
    ingérer son contenu ; cf. plan veille V0, Problème 1).
    """
    if selection.source_id is not None:
        return selection.source_id, False
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
        return existing.id, False

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
    return new_source.id, True


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

    # Self-heal (Story 23.4) : répare les configs actives orphelines (config
    # active mais aucun VeilleFavoriteRef → section veille invisible dans la
    # Tournée). Idempotent, commit dédié, best-effort : ne bloque jamais le GET.
    try:
        await ensure_veille_favorite(db, user_uuid, cfg.id)
        await db.commit()
    except Exception:  # noqa: BLE001 — self-heal best-effort
        await db.rollback()
        logger.warning("veille.favorite_self_heal_failed", exc_info=True)

    return await _hydrate_response(db, cfg)


@router.post("/config", response_model=VeilleConfigResponse)
async def upsert_config(
    body: VeilleConfigUpsert,
    background_tasks: BackgroundTasks,
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

    topic_rows = [
        VeilleTopic(
            veille_config_id=cfg.id,
            topic_id=t.topic_id,
            label=t.label,
            kind=t.kind,
            reason=t.reason,
            position=idx,
        )
        for idx, t in enumerate(body.topics)
    ]
    for topic in topic_rows:
        db.add(topic)
    # Un seul flush matérialise tous les topic.id, puis on rattache les grappes.
    if topic_rows:
        await db.flush()
    for topic, t in zip(topic_rows, body.topics, strict=True):
        for kpos, kw in enumerate(t.keywords):
            db.add(
                VeilleKeyword(
                    veille_config_id=cfg.id,
                    veille_topic_id=topic.id,
                    keyword=kw,
                    position=kpos,
                )
            )

    seen_source_ids: set[UUID] = set()
    # Sources niche nouvellement créées → sync immédiat après commit (Problème 1).
    created_source_ids: list[UUID] = []
    # Sources niche dont le flux RSS est introuvable → remontées au mobile.
    unconnected: list[VeilleUnconnectedSource] = []
    for idx, sel in enumerate(body.source_selections):
        try:
            source_id, created = await _resolve_source_id(db, sel, body.theme_id)
        except ValueError as exc:
            # Source niche dont le flux RSS est introuvable au moment du save :
            # on l'ignore au lieu de faire échouer tout l'enregistrement (PYTHON-51).
            # detect_source lève ce ValueError AVANT toute écriture DB → on peut
            # `continue` sans corrompre la session. On remonte l'échec au mobile
            # via `unconnected_sources` pour proposer une CTA de recherche.
            url = getattr(sel.niche_candidate, "url", None)
            logger.warning(
                "veille.niche_source_skipped",
                url=url,
                error=str(exc),
            )
            if url:
                unconnected.append(
                    VeilleUnconnectedSource(
                        url=url,
                        reason="Aucun flux RSS détecté à cette adresse.",
                    )
                )
            continue
        if source_id in seen_source_ids:
            continue
        seen_source_ids.add(source_id)
        if created:
            created_source_ids.append(source_id)
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

    # Sync immédiat des sources niche fraîchement créées : sans ça leur table
    # `contents` reste vide jusqu'au prochain cycle récurrent (« source associée
    # mais aucun article »). Même pattern que POST /api/sources/custom.
    if created_source_ids:
        from app.workers.rss_sync import sync_source

        for sid in created_source_ids:
            background_tasks.add_task(sync_source, str(sid))

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

    response = await _hydrate_response(db, cfg)
    response.unconnected_sources = unconnected
    return response


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
                    .limit(12)
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
    db: AsyncSession,
    source_id: UUID,
    keywords: list[str] | None = None,
) -> list[VeilleSourceExample]:
    """Renvoie jusqu'à 2 exemples récents d'une source. Cache TTL 24 h.

    Si `keywords` (issus de la config en cours) sont fournis, on **préfère**
    les articles de la source qui matchent l'un d'eux (title/description) —
    les exemples illustrent alors vraiment ce que la veille remontera, plutôt
    que les 2 derniers articles bruts.
    """
    norm_keywords = sorted({k.lower().strip() for k in (keywords or []) if k.strip()})
    cache_key = f"{source_id}|{'|'.join(norm_keywords)}"
    if cache_key in _SOURCE_EXAMPLES_CACHE:
        return _SOURCE_EXAMPLES_CACHE[cache_key]

    cutoff = datetime.now(UTC) - timedelta(days=_SOURCE_EXAMPLES_LOOKBACK_DAYS)
    base_query = select(Content).where(
        Content.source_id == source_id,
        Content.published_at >= cutoff,
    )
    if norm_keywords:
        match_expr = or_(
            *[
                Content.title.ilike(f"%{kw}%") | Content.description.ilike(f"%{kw}%")
                for kw in norm_keywords
            ]
        )
        # Boost les articles matchant un mot-clé, puis tri par récence.
        base_query = base_query.order_by(
            case((match_expr, 1), else_=0).desc(),
            Content.published_at.desc(),
        )
    else:
        base_query = base_query.order_by(Content.published_at.desc())

    contents = (
        (await db.execute(base_query.limit(_SOURCE_EXAMPLES_LIMIT))).scalars().all()
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
    """Renvoie un aperçu (≤2 articles) pour rassurer l'utilisateur au Step 3.

    Si l'utilisateur a déjà une veille active, on préfère les articles de la
    source qui matchent ses mots-clés (globaux + grappes d'angles).
    """
    user_uuid = UUID(current_user_id)
    keywords: list[str] = []
    cfg = await _get_active_config(db, user_uuid)
    if cfg is not None:
        filters = await load_veille_filters(db, cfg)
        keywords = filters.all_keywords
    return await _fetch_source_examples(db, source_id, keywords=keywords)


# ─── Suggesters LLM (Story 23.3) ─────────────────────────────────────────────


@router.post("/resolve/topic", response_model=VeilleResolveTopicResponse)
async def resolve_topic(
    body: VeilleResolveTopicRequest,
    current_user_id: str = Depends(get_current_user_id),
):
    """Enrichit un sujet libre pour le flow Veille, sans écrire d'intérêt global."""
    UUID(current_user_id)
    service = get_topic_enrichment_service()
    try:
        result = await service.enrich(body.topic)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    label = result.canonical_name or body.topic.strip()
    return VeilleResolveTopicResponse(
        label=label,
        topic_id=_slugify_topic_id(label),
        keywords=result.keywords[:10],
        description=result.intent_description,
        metadata={
            "slug_parent": result.slug_parent,
            "entity_type": result.entity_type,
            "canonical_name": result.canonical_name,
            "theme_id": body.theme_id,
            "theme_label": body.theme_label,
        },
    )


@router.post("/suggest/angles", response_model=VeilleSuggestAnglesResponse)
async def suggest_angles(
    body: VeilleSuggestAnglesRequest,
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie 8-12 angles + mots-clés explicites pour un thème + brief.

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
