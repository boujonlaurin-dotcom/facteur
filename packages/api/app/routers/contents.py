import asyncio
import uuid
from datetime import UTC, datetime
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session_maker, get_db
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import ContentType
from app.schemas.collection import SaveContentRequest
from app.schemas.content import (
    ArticleFeedbackRequest,
    ContentDetailResponse,
    ContentStatusUpdate,
    HideContentRequest,
    NoteResponse,
    NoteUpsertRequest,
)
from app.services.collection_service import CollectionService
from app.services.content_extractor import ContentExtractor
from app.services.content_service import ContentService

logger = structlog.get_logger()

router = APIRouter()

# Round 3 fix (docs/bugs/bug-infinite-load-requests.md — F2.3) :
# trafilatura.extract peut prendre 10-15s par article. Sans borne, N
# ouvertures simultanées monopolisent N threads de l'executor par défaut
# + pressurisent le pool DB au retour (réouverture session pour persist).
# Cap à 3 extractions concurrentes globales : un user qui ouvre rapidement
# plusieurs articles ne déclenche pas une tempête parallèle qui sature
# l'executor ET le pool.
_EXTRACTION_SEMAPHORE = asyncio.Semaphore(3)


@router.get(
    "/{content_id}",
    status_code=status.HTTP_200_OK,
    response_model=ContentDetailResponse,
)
async def get_content_detail(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le détail d'un contenu.
    Enrichit le contenu on-demand via trafilatura si html_content manquant.
    """
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    content_data = await service.get_content_detail(content_id, user_uuid)
    if not content_data:
        raise HTTPException(status_code=404, detail="Contenu non trouvé")

    # On-demand enrichment: try to get full content for articles
    if content_data.get("content_type") == ContentType.ARTICLE:
        quality = content_data.get("content_quality")
        extractor = ContentExtractor(download_timeout=10)

        # Compute quality from existing content if not yet done
        if not quality and (
            content_data.get("html_content") or content_data.get("description")
        ):
            quality = extractor.compute_quality_for_existing(
                content_data.get("html_content"), content_data.get("description")
            )
            content_data["content_quality"] = quality

        # Try trafilatura if content is not full quality
        # AND no recent extraction attempt (cooldown 6h to prevent retry storms)
        attempted_at = content_data.get("extraction_attempted_at")
        cooldown_expired = (
            attempted_at is None
            or (datetime.now(UTC) - attempted_at).total_seconds() > 6 * 3600
        )

        if quality != "full" and cooldown_expired:
            # Round 2 fix (bug-infinite-load-requests.md item 3) : libère la
            # session `db` AVANT le `run_in_executor(trafilatura.extract)`
            # qui peut prendre 15 s. Sans ça la session reste idle-in-tx
            # pendant toute la durée du thread executor, et chaque ouverture
            # d'article matin (cold cache) monopolise une conn du pool pour
            # 15 s. Après extraction, on rouvre une session courte dédiée à
            # la persistance.
            try:
                await db.commit()
            except Exception:
                logger.warning("content_detail_precommit_failed", exc_info=True)

            try:
                # Bornage global (F2.3) : bloque si 3 extractions déjà en
                # cours pour éviter la saturation executor/pool.
                async with _EXTRACTION_SEMAPHORE:
                    result = await asyncio.wait_for(
                        asyncio.get_event_loop().run_in_executor(
                            None, extractor.extract, content_data["url"]
                        ),
                        timeout=15.0,
                    )

                # Persist enrichment via a short-lived session.
                async with async_session_maker() as write_session:
                    stmt = select(Content).where(Content.id == content_id)
                    db_content = await write_session.scalar(stmt)
                    if db_content:
                        db_content.extraction_attempted_at = datetime.now(UTC)
                        if result.html_content:
                            content_data["html_content"] = result.html_content
                            content_data["content_quality"] = result.content_quality
                            db_content.html_content = result.html_content
                            db_content.content_quality = result.content_quality
                            if (
                                result.reading_time_seconds
                                and not db_content.duration_seconds
                            ):
                                db_content.duration_seconds = (
                                    result.reading_time_seconds
                                )
                                content_data["duration_seconds"] = (
                                    result.reading_time_seconds
                                )
                        elif not db_content.content_quality:
                            db_content.content_quality = quality or "none"
                        await write_session.commit()

            except Exception:
                # Mark attempt even on failure to prevent retry storm.
                # Courte session dédiée — n'emprunte pas `db` qui est déjà
                # committée (connexion rendue au pool).
                try:
                    async with async_session_maker() as fallback_session:
                        stmt = select(Content).where(Content.id == content_id)
                        db_content = await fallback_session.scalar(stmt)
                        if db_content:
                            db_content.extraction_attempted_at = datetime.now(UTC)
                            if not db_content.content_quality:
                                db_content.content_quality = quality or "none"
                            await fallback_session.commit()
                except Exception:
                    pass  # Don't fail the request over persistence
                logger.exception(
                    "on_demand_enrichment_failed",
                    content_id=str(content_id),
                )

    return content_data


@router.post("/{content_id}/status", status_code=status.HTTP_200_OK)
async def update_content_status(
    content_id: UUID,
    update_data: ContentStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Met à jour le statut de consommation d'un contenu (Lu, Vu).

    Trigger:
    - Au scroll (SEEN)
    - Au retour de la WebView (CONSUMED + time_spent)
    """
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    updated_status = await service.update_content_status(
        user_id=user_uuid, content_id=content_id, update_data=update_data
    )

    await db.commit()
    return {"status": "ok", "current_status": updated_status.status}


@router.post("/{content_id}/save", status_code=status.HTTP_200_OK)
async def save_content(
    content_id: UUID,
    data: SaveContentRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Sauvegarde un contenu pour plus tard, optionnellement dans des collections."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.set_save_status(
        user_id=user_uuid, content_id=content_id, is_saved=True
    )

    # Optionally add to collections
    if data and data.collection_ids:
        collection_service = CollectionService(db)
        await collection_service.add_to_collections(
            user_uuid, content_id, data.collection_ids
        )

    await db.commit()
    return {"status": "ok", "is_saved": True}


@router.delete("/{content_id}/save", status_code=status.HTTP_200_OK)
async def unsave_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un contenu des sauvegardés."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.set_save_status(
        user_id=user_uuid, content_id=content_id, is_saved=False
    )

    await db.commit()
    return {"status": "ok", "is_saved": False}


@router.post("/{content_id}/like", status_code=status.HTTP_200_OK)
async def like_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un like sur un contenu. Auto-bookmark + ajout à 'Contenus likés'."""
    service = ContentService(db)
    collection_service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    await service.set_like_status(
        user_id=user_uuid,
        content_id=content_id,
        is_liked=True,
    )

    # Auto-bookmark
    await service.set_save_status(
        user_id=user_uuid,
        content_id=content_id,
        is_saved=True,
    )

    # Auto-add to liked collection
    liked_col = await collection_service.ensure_liked_collection(user_uuid)
    await collection_service.add_to_collection(user_uuid, liked_col.id, content_id)

    await db.commit()
    return {"status": "ok", "is_liked": True, "is_saved": True}


@router.delete("/{content_id}/like", status_code=status.HTTP_200_OK)
async def unlike_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire le like d'un contenu. Retire de 'Contenus likés' (article reste bookmarké)."""
    service = ContentService(db)
    collection_service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    await service.set_like_status(
        user_id=user_uuid,
        content_id=content_id,
        is_liked=False,
    )

    # Remove from liked collection (article stays saved)
    liked_col = await collection_service.ensure_liked_collection(user_uuid)
    await collection_service.remove_from_collection(user_uuid, liked_col.id, content_id)

    await db.commit()
    return {"status": "ok", "is_liked": False}


@router.post("/{content_id}/hide", status_code=status.HTTP_200_OK)
async def hide_content(
    content_id: UUID,
    request: HideContentRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Masque un contenu (pas intéressé). Body optionnel: swipe-left sans raison = {}."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    reason = request.reason if request else None

    await service.set_hide_status(
        user_id=user_uuid, content_id=content_id, is_hidden=True, reason=reason
    )

    await db.commit()
    return {"status": "ok", "is_hidden": True, "reason": reason}


@router.delete("/{content_id}/hide", status_code=status.HTTP_200_OK)
async def unhide_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Annule le masquage d'un contenu (undo swipe-dismiss)."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.unset_hide_status(user_id=user_uuid, content_id=content_id)

    await db.commit()
    return {"status": "ok", "is_hidden": False}


@router.post("/{content_id}/report-not-serene", status_code=status.HTTP_200_OK)
async def report_not_serene(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Signale un article affiché en mode Serein comme anxiogène.

    Upsert idempotent. Dès le premier signalement, l'article est
    reclassifié is_serene=False pour tous les utilisateurs.
    """
    from sqlalchemy.dialects.postgresql import insert

    from app.models.serene_report import SereneReport

    user_uuid = UUID(current_user_id)

    try:
        stmt = (
            insert(SereneReport)
            .values(
                id=uuid.uuid4(),
                content_id=content_id,
                user_id=user_uuid,
            )
            .on_conflict_do_nothing(
                index_elements=["user_id", "content_id"],
            )
        )
        await db.execute(stmt)

        # Flip is_serene immediately (threshold = 1)
        content = await db.get(Content, content_id)
        if content and content.is_serene is not False:
            content.is_serene = False
            logger.info(
                "serene_report_reclassified",
                content_id=str(content_id),
                user_id=current_user_id,
            )

        await db.commit()
    except Exception:
        await db.rollback()
        logger.exception(
            "serene_report_failed",
            content_id=str(content_id),
            user_id=current_user_id,
        )
        raise HTTPException(status_code=500, detail="Failed to record serene report")

    return {"status": "ok"}


@router.post("/{content_id}/impress", status_code=status.HTTP_200_OK)
async def impress_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Marque un article comme 'déjà vu' — malus permanent fort (-120 pts)."""
    from datetime import UTC, datetime

    from sqlalchemy.dialects.postgresql import insert

    from app.models.content import UserContentStatus
    from app.models.enums import ContentStatus

    user_uuid = UUID(current_user_id)
    now = datetime.now(UTC)

    stmt = (
        insert(UserContentStatus)
        .values(
            user_id=user_uuid,
            content_id=content_id,
            status=ContentStatus.UNSEEN.value,
            manually_impressed=True,
            last_impressed_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "content_id"],
            set_={
                "manually_impressed": True,
                "last_impressed_at": now,
                "updated_at": now,
            },
        )
    )
    await db.execute(stmt)
    await db.commit()
    return {"status": "ok", "manually_impressed": True}


@router.put(
    "/{content_id}/note", status_code=status.HTTP_200_OK, response_model=NoteResponse
)
async def upsert_note(
    content_id: UUID,
    request: NoteUpsertRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Crée ou met à jour une note sur un article. Auto-sauvegarde l'article."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    try:
        result = await service.upsert_note(
            user_id=user_uuid,
            content_id=content_id,
            note_text=request.note_text,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    await db.commit()
    return NoteResponse(
        note_text=result.note_text,
        note_updated_at=result.note_updated_at,
        is_saved=result.is_saved,
    )


@router.delete("/{content_id}/note", status_code=status.HTTP_200_OK)
async def delete_note(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Supprime la note d'un article. L'article reste sauvegardé."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    result = await service.delete_note(user_id=user_uuid, content_id=content_id)
    if not result:
        raise HTTPException(status_code=404, detail="Status not found")

    await db.commit()
    return {"status": "ok"}


@router.post("/{content_id}/feedback", status_code=status.HTTP_200_OK)
async def submit_article_feedback(
    content_id: UUID,
    request: ArticleFeedbackRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Enregistre un feedback utilisateur (pouce haut/bas) sur un article.

    Upsert idempotent (1 feedback par user × article).
    Ajuste les poids subtopics : +0.15 (positive) / -0.15 (negative).
    """
    from datetime import date as date_type

    from sqlalchemy.dialects.postgresql import insert

    from app.models.article_feedback import ArticleFeedback
    from app.services.recommendation.scoring_config import ScoringWeights

    user_uuid = UUID(current_user_id)

    # Parse digest_date if provided
    parsed_date = None
    if request.digest_date:
        import contextlib

        with contextlib.suppress(ValueError):
            parsed_date = date_type.fromisoformat(request.digest_date)

    try:
        stmt = (
            insert(ArticleFeedback)
            .values(
                id=uuid.uuid4(),
                user_id=user_uuid,
                content_id=content_id,
                sentiment=request.sentiment,
                reasons=request.reasons or None,
                comment=request.comment,
                digest_date=parsed_date,
            )
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_={
                    "sentiment": request.sentiment,
                    "reasons": request.reasons or None,
                    "comment": request.comment,
                    "digest_date": parsed_date,
                },
            )
        )
        await db.execute(stmt)

        # Adjust subtopic weights based on sentiment
        service = ContentService(db)
        delta = (
            ScoringWeights.LIKE_TOPIC_BOOST
            if request.sentiment == "positive"
            else ScoringWeights.DISMISS_TOPIC_PENALTY
        )
        await service._adjust_subtopic_weights(user_uuid, content_id, delta)

        await db.commit()

        logger.info(
            "article_feedback_recorded",
            content_id=str(content_id),
            user_id=current_user_id,
            sentiment=request.sentiment,
            reasons=request.reasons,
        )
    except Exception:
        await db.rollback()
        logger.exception(
            "article_feedback_failed",
            content_id=str(content_id),
            user_id=current_user_id,
        )
        raise HTTPException(status_code=500, detail="Failed to record feedback")

    return {"status": "ok", "sentiment": request.sentiment}


from cachetools import TTLCache

# In-memory cache for analysis responses (TTL 2h, max 256 entries)
_analysis_cache: TTLCache = TTLCache(maxsize=256, ttl=7200)

# In-memory cache for perspectives responses (TTL 2h, max 256 entries)
_perspectives_cache: TTLCache = TTLCache(maxsize=256, ttl=7200)


async def _load_cluster_articles_for_representative(
    db: AsyncSession,
    content_id: UUID,
    user_id: UUID,
) -> list:
    """Load the editorial-subject carousel articles containing ``content_id``.

    Mirrors the cluster-based perspectives computation in
    ``editorial/pipeline.py`` so the /perspectives endpoint returns a count
    consistent with the digest's ``perspective_count`` header. Returns the
    list of Content objects (ordered by published_at desc) for the subject
    the content_id belongs to, or an empty list if:
      - the user has no recent editorial_v1 digest;
      - the content_id is not part of any subject (standalone feed article).

    Only carousel articles (actu + extras) are returned — ``deep_article``
    is the "Pas de recul" article, not part of the sources list.
    """
    import structlog
    from sqlalchemy import desc, select
    from sqlalchemy.orm import selectinload

    from app.models.content import Content
    from app.models.daily_digest import DailyDigest

    logger = structlog.get_logger(__name__)

    # Recent editorial digest for this user (last 48h covers generation
    # windows + caching lag).
    stmt = (
        select(DailyDigest)
        .where(
            DailyDigest.user_id == user_id,
            DailyDigest.format_version == "editorial_v1",
        )
        .order_by(desc(DailyDigest.generated_at))
        .limit(4)  # up to 2 per day * 2 days (normal + serene)
    )
    result = await db.execute(stmt)
    digests = list(result.scalars().all())
    if not digests:
        return []

    target_str = str(content_id)
    match_ids: set[str] = set()
    for digest in digests:
        items = digest.items if isinstance(digest.items, dict) else {}
        for subject in items.get("subjects", []):
            actu = subject.get("actu_article")
            extras = subject.get("extra_actu_articles", []) or []
            subject_ids: set[str] = set()
            if actu and actu.get("content_id"):
                subject_ids.add(actu["content_id"])
            for extra in extras:
                if extra.get("content_id"):
                    subject_ids.add(extra["content_id"])
            rep = subject.get("representative_content_id")
            if rep:
                subject_ids.add(rep)
            # The subject owns this content_id either because it's its
            # representative, or because it's one of the carousel articles.
            if target_str in subject_ids:
                # Skip representative from the perspective pool if it's not
                # also in actu/extras — keep only what the user actually
                # sees in the carousel, so the cluster reflects the visible
                # coverage.
                match_ids = {
                    i
                    for i in subject_ids
                    if i == (actu.get("content_id") if actu else None)
                    or any(i == e.get("content_id") for e in extras)
                }
                break
        if match_ids:
            break

    if not match_ids:
        return []

    try:
        uuids = [UUID(i) for i in match_ids]
    except (ValueError, TypeError):
        logger.warning(
            "perspectives_cluster_invalid_uuid",
            content_id=str(content_id),
        )
        return []

    content_stmt = (
        select(Content)
        .options(selectinload(Content.source))
        .where(Content.id.in_(uuids))
        .order_by(desc(Content.published_at))
    )
    content_result = await db.execute(content_stmt)
    return list(content_result.scalars().all())


async def _load_stored_perspectives_for_representative(
    db: AsyncSession,
    content_id: UUID,
    user_id: UUID,
) -> tuple[list[dict], dict[str, int]] | None:
    """Return the perspective_articles list the pipeline persisted on the
    digest subject containing ``content_id``, plus its bias_distribution.

    Why this path exists: the editorial pipeline runs Google News once at
    digest generation time and merges with the cluster sources. If the
    /perspectives endpoint re-runs Google News at call time (hours later),
    it gets a different result set — so the CTA logos (built from the
    persisted ``perspective_sources``) drift away from the bottom-sheet
    list (live API). Reading from the same JSONB snapshot eliminates the
    divergence by construction.

    Returns ``None`` if the content_id is not part of any recent
    editorial_v1 digest (standalone feed article) — caller should fall
    back to live computation.
    """
    from sqlalchemy import desc, select

    from app.models.daily_digest import DailyDigest

    stmt = (
        select(DailyDigest)
        .where(
            DailyDigest.user_id == user_id,
            DailyDigest.format_version == "editorial_v1",
        )
        .order_by(desc(DailyDigest.generated_at))
        .limit(4)
    )
    result = await db.execute(stmt)
    digests = list(result.scalars().all())
    if not digests:
        return None

    target_str = str(content_id)
    for digest in digests:
        items = digest.items if isinstance(digest.items, dict) else {}
        for subject in items.get("subjects", []):
            actu = subject.get("actu_article")
            extras = subject.get("extra_actu_articles", []) or []
            ids = {subject.get("representative_content_id")}
            if actu and actu.get("content_id"):
                ids.add(actu["content_id"])
            for extra in extras:
                if extra.get("content_id"):
                    ids.add(extra["content_id"])
            if target_str in ids:
                stored = subject.get("perspective_articles")
                bias = subject.get("bias_distribution") or {}
                if stored is not None:
                    return list(stored), dict(bias)
                # Subject found but no stored snapshot (legacy digest pre-fix
                # or pipeline bug) → caller falls back to live compute.
                return None
    return None


@router.get("/{content_id}/perspectives", status_code=status.HTTP_200_OK)
async def get_perspectives(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère des perspectives alternatives sur un contenu via Google News.
    Recherche live basée sur les mots-clés du titre, avec cache in-memory (2h TTL).
    """
    import structlog
    from sqlalchemy import select
    from sqlalchemy.orm import joinedload

    from app.models.content import Content
    from app.services.perspective_service import PerspectiveService, _parse_entity_names

    logger = structlog.get_logger(__name__)

    cache_key = str(content_id)

    # Check cache (TTLCache handles expiration automatically)
    cached_response = _perspectives_cache.get(cache_key)
    if cached_response is not None:
        logger.info("perspectives_cache_hit", content_id=cache_key)
        return cached_response

    logger.info(
        "perspectives_endpoint_start",
        content_id=cache_key,
        user_id=current_user_id,
    )

    # Get the content with its source (for bias + domain exclusion)
    result = await db.execute(
        select(Content)
        .options(joinedload(Content.source))
        .where(Content.id == content_id)
    )
    content = result.scalars().first()

    if not content:
        logger.warning(
            "perspectives_content_not_found",
            content_id=cache_key,
        )
        raise HTTPException(status_code=404, detail="Content not found")

    logger.info(
        "perspectives_content_found",
        content_id=cache_key,
        title=content.title[:50] if content.title else "N/A",
    )

    # Extract the source domain for exclusion and bias
    source_domain = None
    source_bias_stance = "unknown"
    if content.source:
        from urllib.parse import urlparse

        from app.services.perspective_service import DOMAIN_BIAS_MAP

        try:
            parsed = urlparse(content.source.url)
            source_domain = parsed.netloc
            if source_domain and source_domain.startswith("www."):
                source_domain = source_domain[4:]
        except Exception:
            pass
        if content.source.bias_stance:
            source_bias_stance = (
                content.source.bias_stance.value
                if hasattr(content.source.bias_stance, "value")
                else str(content.source.bias_stance)
            )
        # Fallback to DOMAIN_BIAS_MAP if DB bias is unknown
        if source_bias_stance == "unknown" and source_domain:
            source_bias_stance = DOMAIN_BIAS_MAP.get(source_domain, "unknown")

    # Hybrid perspectives search: DB entities → Google News entities → fallback keywords
    service = PerspectiveService(db=db)

    # Fast path — return the snapshot the editorial pipeline persisted on
    # the digest subject containing this content_id. This guarantees the
    # bottom-sheet list matches the CTA preview logos (both derived from
    # the same JSONB blob) instead of running a fresh Google News query
    # that drifts from the digest-time results.
    try:
        stored = await _load_stored_perspectives_for_representative(
            db=db,
            content_id=content_id,
            user_id=UUID(current_user_id),
        )
    except Exception as e:
        stored = None
        logger.warning(
            "perspectives_stored_lookup_failed",
            content_id=cache_key,
            error=str(e),
        )

    if stored is not None:
        stored_perspectives, stored_bias = stored
        bias_groups = len([v for v in stored_bias.values() if v > 0])
        count = len(stored_perspectives)
        has_entities = bool(
            _parse_entity_names(content.entities, types={"PERSON", "ORG"})
        )
        if has_entities and count >= 5 and bias_groups >= 3:
            comparison_quality = "high"
        elif count >= 3 and bias_groups >= 2:
            comparison_quality = "medium"
        else:
            comparison_quality = "low"

        from app.models.perspective_analysis import PerspectiveAnalysis as _PA

        analysis_result = await db.execute(
            select(_PA).where(_PA.content_id == content_id)
        )
        cached_row = analysis_result.scalars().first()
        cached_analysis = cached_row.analysis_text if cached_row else None

        response = {
            "content_id": cache_key,
            # Empty keywords: the snapshot was built without re-running the
            # Google News query path. Mobile uses keywords only as a hint
            # for the analyse/refresh flow — the empty list degrades cleanly.
            "keywords": [],
            "source_bias_stance": source_bias_stance,
            "perspectives": stored_perspectives,
            "bias_distribution": stored_bias,
            "comparison_quality": comparison_quality,
            "analysis": cached_analysis,
            "analysis_cached": cached_analysis is not None,
        }
        _perspectives_cache[cache_key] = response
        logger.info(
            "perspectives_endpoint_stored_snapshot",
            content_id=cache_key,
            count=count,
        )
        return response

    # Live path (non-digest content_id, or stored snapshot missing).
    # Mirrors the editorial pipeline: include cluster's own sources so the
    # count converges back to the digest header on the next regeneration.
    cluster_perspectives: list = []
    cluster_domains: set[str] = set()
    try:
        cluster_contents = await _load_cluster_articles_for_representative(
            db=db,
            content_id=content_id,
            user_id=UUID(current_user_id),
        )
        if cluster_contents:
            cluster_perspectives = await service.build_cluster_perspectives(
                cluster_contents
            )
            cluster_domains = {
                p.source_domain for p in cluster_perspectives if p.source_domain
            }
    except Exception as e:
        logger.warning(
            "perspectives_cluster_lookup_failed",
            content_id=cache_key,
            error=str(e),
        )

    gnews_perspectives, keywords = await service.get_perspectives_hybrid(
        content=content,
        exclude_domain=source_domain,
    )

    # Keep only Google News entries whose domain isn't already covered by
    # the cluster — no double-counting.
    new_gnews = [
        p
        for p in gnews_perspectives
        if p.source_domain and p.source_domain not in cluster_domains
    ]

    # Single source of truth for the 3 UI counters — mirror pipeline.py.
    merged = cluster_perspectives + new_gnews
    perspectives = [p for p in merged if p.bias_stance != "unknown"]

    logger.info(
        "perspectives_composition",
        content_id=cache_key,
        cluster_sources=len(cluster_perspectives),
        gnews_added=len(new_gnews),
        known_bias=len(perspectives),
    )

    # Calculate bias distribution (without "unknown")
    bias_distribution = {
        "left": 0,
        "center-left": 0,
        "center": 0,
        "center-right": 0,
        "right": 0,
    }
    for p in perspectives:
        if p.bias_stance in bias_distribution:
            bias_distribution[p.bias_stance] += 1

    # Compute comparison quality from pipeline signals
    bias_groups = len([v for v in bias_distribution.values() if v > 0])
    has_entities = bool(_parse_entity_names(content.entities, types={"PERSON", "ORG"}))
    count = len(perspectives)

    if has_entities and count >= 5 and bias_groups >= 3:
        comparison_quality = "high"
    elif count >= 3 and bias_groups >= 2:
        comparison_quality = "medium"
    else:
        comparison_quality = "low"

    logger.info(
        "perspectives_endpoint_success",
        content_id=cache_key,
        perspectives_count=len(perspectives),
        keywords=keywords,
    )

    # Check if a cached Mistral analysis exists in DB
    from app.models.perspective_analysis import PerspectiveAnalysis

    cached_analysis = None
    analysis_result = await db.execute(
        select(PerspectiveAnalysis).where(PerspectiveAnalysis.content_id == content_id)
    )
    cached_row = analysis_result.scalars().first()
    if cached_row:
        cached_analysis = cached_row.analysis_text

    response = {
        "content_id": cache_key,
        "keywords": keywords,
        "source_bias_stance": source_bias_stance,
        "perspectives": [
            {
                "title": p.title,
                "url": p.url,
                "source_name": p.source_name,
                "source_domain": p.source_domain,
                "bias_stance": p.bias_stance,
                "published_at": p.published_at,
                "description": p.description,
            }
            for p in perspectives
        ],
        "bias_distribution": bias_distribution,
        "comparison_quality": comparison_quality,
        "analysis": cached_analysis,
        "analysis_cached": cached_analysis is not None,
    }

    # Store in cache (TTLCache handles expiration automatically)
    _perspectives_cache[cache_key] = response

    return response


@router.post("/{content_id}/perspectives/analyze", status_code=status.HTTP_200_OK)
async def analyze_perspectives(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Analyse LLM des divergences éditoriales entre perspectives.
    Persiste en DB pour réutilisation inter-utilisateurs.
    Cache in-memory L1 (2h TTL) pour éviter des hits DB répétés.
    """
    from app.models.perspective_analysis import PerspectiveAnalysis
    from app.services.perspective_service import PerspectiveService

    cache_key = str(content_id)

    # L1: Check in-memory cache
    cached_response = _analysis_cache.get(cache_key)
    if cached_response is not None:
        return cached_response

    # L2: Check DB for persisted analysis
    existing = await db.execute(
        select(PerspectiveAnalysis).where(PerspectiveAnalysis.content_id == content_id)
    )
    cached_row = existing.scalars().first()
    if cached_row:
        response = {
            "content_id": cache_key,
            "analysis": cached_row.analysis_text,
            "divergence_level": None,
            "cached": True,
        }
        _analysis_cache[cache_key] = response
        return response

    # No cache — generate via Mistral
    perspectives_data = _perspectives_cache.get(cache_key)

    if perspectives_data is None:
        perspectives_data = await get_perspectives(
            content_id=content_id, db=db, current_user_id=current_user_id
        )

    perspectives_list = perspectives_data.get("perspectives", [])
    if not perspectives_list:
        response = {
            "content_id": cache_key,
            "analysis": None,
            "divergence_level": None,
            "cached": False,
        }
        _analysis_cache[cache_key] = response
        return response

    # Get article info from content
    from sqlalchemy.orm import joinedload

    result = await db.execute(
        select(Content)
        .options(joinedload(Content.source))
        .where(Content.id == content_id)
    )
    content = result.scalars().first()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    source_name = content.source.name if content.source else "Unknown"
    source_bias = perspectives_data.get("source_bias_stance", "unknown")

    service = PerspectiveService(db=db)
    analysis = await service.analyze_divergences(
        article_title=content.title,
        source_name=source_name,
        source_bias=source_bias,
        perspectives=perspectives_list,
        article_description=content.description,
    )

    # Extract fields from dict returned by analyze_divergences()
    analysis_text = analysis.get("analysis") if analysis else None
    divergence_level = analysis.get("divergence_level") if analysis else None

    # Persist to DB for future users (ON CONFLICT DO NOTHING for concurrent requests)
    if analysis_text:
        from sqlalchemy.dialects.postgresql import insert as pg_insert

        stmt = (
            pg_insert(PerspectiveAnalysis)
            .values(content_id=content_id, analysis_text=analysis_text)
            .on_conflict_do_nothing(constraint="uq_perspective_analyses_content_id")
        )
        try:
            await db.execute(stmt)
            await db.commit()
        except Exception as e:
            logger.error("perspective_analysis_persist_error", error=str(e))
            await db.rollback()

    response = {
        "content_id": cache_key,
        "analysis": analysis_text,
        "divergence_level": divergence_level,
        "cached": False,
    }
    _analysis_cache[cache_key] = response

    # Invalidate perspectives cache so next get_perspectives includes the analysis
    _perspectives_cache.pop(cache_key, None)

    return response
