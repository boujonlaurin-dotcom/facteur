"""Router pour `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour la carte hi-fi "L'Essentiel
du jour" du feed mobile.

Strictement read-only : pas de pipeline LLM au request time. Réutilise la
chaîne de fallback de `/api/digest` via `read_digest_or_fallback`.
"""

import time
from datetime import UTC, date, datetime
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, safe_async_session, safe_fail_open_rollback
from app.dependencies import get_current_user_id
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.essentiel_triage import EssentielTriageDecision
from app.schemas.essentiel import (
    DEFAULT_MORE_LIMIT,
    MAX_MORE_EXCLUDE_IDS,
    EssentielMoreResponse,
    EssentielResponse,
    TriageBatchRequest,
    TriageBatchResponse,
    TriageDecisionKind,
)
from app.services.content_service import ContentService
from app.services.digest_service import DigestService, read_digest_or_fallback
from app.services.essentiel_service import (
    ESSENTIEL_MIN_ARTICLES,
    build_essentiel_response_with_supplements,
    fetch_essentiel_more,
    fetch_user_essentiel_context,
)
from app.services.recommendation.carousel_catalog import (
    MAX_CAROUSEL_ITEMS,
    CarouselBuildContext,
    fetch_consumed_ids,
)
from app.services.recommendation.carousel_selection_service import (
    select_essentiel_carousel,
)
from app.utils.time import today_paris

logger = structlog.get_logger()

router = APIRouter()


def _preparing_response() -> JSONResponse:
    return JSONResponse(
        status_code=202,
        content={
            "status": "preparing",
            "message": "Votre essentiel est en cours de préparation...",
        },
    )


# Nombre min d'items du carrousel Essentiel APRÈS retrait des 5 articles déjà
# affichés dans la carte — en-deçà, on n'attache pas de carrousel (évite un
# scroller à 1 item).
_MIN_ESSENTIEL_CAROUSEL_ITEMS = 2


async def _mark_essentiel_carousel_shown(
    db: AsyncSession, user_uuid: UUID, content_ids: list[UUID]
) -> None:
    """Upsert `essentiel_last_shown_at = now()` pour les items effectivement
    injectés dans la pile (Story 33.5) — alimente le cooldown anti-répétition
    consommé par `carousel_selection_service.select_essentiel_carousel`. Même
    patron que l'upsert `last_impressed_at` de `POST /feed/refresh`
    (`app/routers/feed.py`). Pas de commit explicite : `get_db` commit la
    session en fin de requête ; en cas d'échec, `safe_fail_open_rollback`
    (appelant) annule ce statement avec le reste de l'enrichissement."""
    if not content_ids:
        return
    now = datetime.now(UTC)
    stmt = (
        insert(UserContentStatus)
        .values(
            [
                {
                    "user_id": user_uuid,
                    "content_id": content_id,
                    "status": ContentStatus.UNSEEN.value,
                    "essentiel_last_shown_at": now,
                    "created_at": now,
                    "updated_at": now,
                }
                for content_id in content_ids
            ]
        )
        .on_conflict_do_update(
            index_elements=["user_id", "content_id"],
            set_={"essentiel_last_shown_at": now, "updated_at": now},
        )
    )
    await db.execute(stmt)


async def _enrich_essentiel_carousel(
    db: AsyncSession,
    user_uuid: UUID,
    response: EssentielResponse,
    effective_date: date,
) -> EssentielResponse:
    """Attache le carrousel semi-éditorialisé du jour à la réponse Essentiel.

    Story 32.1 — mutualise la Phase B des carrousels de Flâner via le catalogue
    partagé. Le type mis en avant est choisi de façon déterministe (rotation
    date-seedée sur `(user, date_paris)`) ; Flâner retire ce même type le même
    jour → complémentarité cross-surface sans état DB.

    Fail-open : toute exception laisse `response` inchangée (le carrousel est une
    surface purement additive, il ne peut jamais casser le chargement de
    l'Essentiel). Skip hors édition du jour (rewind J-7 en lecture seule).
    """
    if effective_date != today_paris():
        return response

    try:
        consumed_ids = await fetch_consumed_ids(db, user_uuid)
        ctx = CarouselBuildContext(
            session=db,
            session_maker=safe_async_session,
            user_id=user_uuid,
            consumed_ids=consumed_ids,
        )
        # Construit paresseusement le SEUL carrousel du jour (rotation date-seedée),
        # sans bâtir les 3 types perdants → endpoint sensible à la latence.
        content = await select_essentiel_carousel(ctx, effective_date)
        if content is None:
            return response

        # Ne pas re-servir les 5 articles déjà affichés dans la carte Essentiel.
        shown_ids = {a.content_id for a in response.articles}
        content = content.excluding(shown_ids, MAX_CAROUSEL_ITEMS)
        if len(content.items) < _MIN_ESSENTIEL_CAROUSEL_ITEMS:
            return response

        # position=0 : slot dédié côté mobile, non pertinent pour l'Essentiel.
        response.carousel = content.to_carousel_info(0)
        await _mark_essentiel_carousel_shown(
            db, user_uuid, [item.id for item in content.items]
        )
    except Exception:
        logger.exception("essentiel_carousel_enrichment_failed")
        # Fail-open : rollback borné partagé (cf. `_enrich_community_carousel`).
        await safe_fail_open_rollback(db)

    return response


@router.get("", response_model=EssentielResponse)
async def get_essentiel(
    target_date: date | None = Query(
        None, description="Date for essentiel (default: today)"
    ),
    serein: bool | None = Query(
        None,
        description=(
            "Force le mode serein (true/false). Absent ⇒ lecture de la "
            "préférence DB. Permet au client de demander le bon mode sans "
            "dépendre de la persistance de la préférence au moment du refetch."
        ),
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne les 5 articles transversaux du jour pour l'utilisateur courant.

    Source de vérité : la `DigestResponse` calculée par la cron nocturne
    (variante `pour_vous`). Projection cross-topic via `build_essentiel_response`.

    Renvoie 202 ``preparing`` si la chaîne de fallback du digest est épuisée.
    """
    user_uuid = UUID(current_user_id)
    effective_date = target_date or today_paris()
    start = time.monotonic()

    service = DigestService(db)
    # Override explicite par le client (symétrie avec `?serein=` du feed) ;
    # fallback DB conservé pour rétrocompat des clients qui ne l'envoient pas.
    serein_enabled = (
        serein
        if serein is not None
        else await service.get_user_serein_enabled(user_uuid)
    )
    digest = await read_digest_or_fallback(
        db, user_uuid, effective_date, is_serene=serein_enabled
    )
    if digest is None:
        return _preparing_response()

    # Re-rank user-aware : charge les sources suivies + topics suivis pour
    # promouvoir les articles qui matchent les prefs de l'utilisateur.
    # Pas de pipeline LLM, juste 2 SELECTs courts indexés sur `user_id`.
    user_context = await fetch_user_essentiel_context(db, user_uuid)
    response = await build_essentiel_response_with_supplements(
        db,
        user_uuid,
        digest,
        user_context=user_context,
        is_serene=serein_enabled,
    )

    # Plancher de qualité : on n'expose jamais une carte Essentiel pauvre
    # (1-2 articles). Si la complétion depuis les sources suivies n'a pas
    # atteint 3 articles, on signale au client que l'essentiel se prépare.
    if len(response.articles) < ESSENTIEL_MIN_ARTICLES:
        return _preparing_response()

    # Carrousel semi-éditorialisé du jour (Story 32.1) — mutualisé avec Flâner.
    # Additif et fail-open : n'altère jamais les 5 articles ni le code de statut.
    response = await _enrich_essentiel_carousel(db, user_uuid, response, effective_date)

    logger.info(
        "essentiel_retrieved",
        user_id=current_user_id,
        elapsed_ms=round((time.monotonic() - start) * 1000, 1),
        articles_count=len(response.articles),
        is_stale_fallback=response.is_stale_fallback,
        serein_enabled=serein_enabled,
        followed_sources_count=len(user_context.followed_source_ids),
        topic_weights_count=len(user_context.topic_weights),
    )
    return response


@router.get("/more", response_model=EssentielMoreResponse)
async def get_essentiel_more(
    limit: int = Query(
        DEFAULT_MORE_LIMIT,
        ge=1,
        le=10,
        description=(
            "Nb d'articles inédits demandés. 2 par défaut (« Deux de plus ») ; "
            "le prefetch de la pile de tri (Story 33.4) demande des lots de 5."
        ),
    ),
    exclude: str | None = Query(
        None,
        description=(
            "content_id déjà portés par le client (slate ∪ décidés ∪ pool "
            f"local), séparés par des virgules. Cap {MAX_MORE_EXCLUDE_IDS}."
        ),
    ),
    serein: bool | None = Query(
        None, description="Force le mode serein (cf. `GET /api/essentiel`)."
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Sert « Plus d'articles ? » quand la réserve locale du client est vide.

    Story 33.3 — le CTA de fin de tri ne disparaît plus quand le carrousel du
    jour n'a plus rien à injecter : il vient chercher ici deux recommandations
    Essentiel inédites.

    Strictement read-only, aucune écriture, aucun pipeline LLM : réutilise le
    pool live du blend « Essentiel vivant » (`fetch_essentiel_more`).

    Une liste **vide** est une réponse 200 normale — pool épuisé, ou
    utilisateur sans source suivie ni thème apprécié. Le client garde son CTA
    visible et affiche un retour sobre ; un 202/404 le pousserait à traiter ça
    comme une panne.
    """
    user_uuid = UUID(current_user_id)

    exclude_ids: set[UUID] = set()
    if exclude:
        for raw in exclude.split(",")[:MAX_MORE_EXCLUDE_IDS]:
            raw = raw.strip()
            if not raw:
                continue
            try:
                exclude_ids.add(UUID(raw))
            except ValueError:
                # Un id illisible ne peut de toute façon matcher aucun contenu :
                # on le laisse tomber plutôt que de refuser tout le lot.
                logger.warning("essentiel_more_bad_exclude_id", raw=raw)

    service = DigestService(db)
    serein_enabled = (
        serein
        if serein is not None
        else await service.get_user_serein_enabled(user_uuid)
    )
    user_context = await fetch_user_essentiel_context(db, user_uuid)
    articles = await fetch_essentiel_more(
        db,
        user_uuid,
        user_context,
        is_serene=serein_enabled,
        exclude_ids=exclude_ids,
        limit=limit,
    )

    logger.info(
        "essentiel_more_served",
        user_id=current_user_id,
        requested=limit,
        excluded=len(exclude_ids),
        served=len(articles),
    )
    return EssentielMoreResponse(articles=articles)


@router.post("/triage", response_model=TriageBatchResponse)
async def record_essentiel_triage(
    payload: TriageBatchRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Enregistre un batch de décisions de tri du slate Essentiel (Story 33.1).

    **Collecte seule.** Cet endpoint n'ajoute aucun terme au moteur de reco : ni
    `_adjust_subtopic_weights`, ni `_adjust_entity_affinity`, ni
    `_trigger_personalization_mute`. En particulier `decision=pass` n'est **pas**
    branché sur `not_interested`, qui muterait la source entière et sans
    expiration — un média entier tu pour un seul papier.

    Seule exception, actée par le PO : `decision=later` déclenche en plus le save
    existant, parce que c'est exactement ce que fait déjà le bouton signet de la
    carte. Sans ça le produit aurait deux « mettre de côté » aux effets
    différents. Le `BOOKMARK_TOPIC_BOOST` qui en découle est un poids qui existe
    déjà ; le tri n'en crée aucun.

    Idempotent : upsert sur `(user_id, content_id, digest_date)`, l'utilisateur
    peut revenir sur un choix (« Trier à nouveau »).
    """
    user_uuid = UUID(current_user_id)

    # Un rang ne peut pas dépasser la taille du slate qu'il indexe : sinon le
    # dénominateur de la jauge est faux et le bug passe inaperçu des mois.
    for item in payload.decisions:
        if item.rank is not None and item.rank > payload.slate_size:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"rank {item.rank} incohérent avec slate_size {payload.slate_size}"
                ),
            )

    # Dédup intra-batch, dernière décision gagnante : Postgres refuse qu'un même
    # ON CONFLICT DO UPDATE touche deux fois la même ligne dans un seul INSERT.
    by_content = {item.content_id: item for item in payload.decisions}

    # Filtre sur les contenus réellement existants — un `content_id` périmé
    # (article purgé entre le tri hors-ligne et le flush) ferait échouer tout le
    # batch sur la FK, et donc perdre les décisions valides qui l'accompagnent.
    known_ids = set(
        (
            await db.scalars(
                select(Content.id).where(Content.id.in_(list(by_content.keys())))
            )
        ).all()
    )
    items = [item for cid, item in by_content.items() if cid in known_ids]
    if not items:
        return TriageBatchResponse(recorded=0, saved_for_later=0)

    rows = [
        {
            "user_id": user_uuid,
            "content_id": item.content_id,
            "digest_date": payload.digest_date,
            "decision": item.decision.value,
            "rank": item.rank,
            "slate_size": payload.slate_size,
            "decided_via": item.decided_via.value if item.decided_via else None,
            "latency_ms": item.latency_ms,
        }
        for item in items
    ]

    stmt = insert(EssentielTriageDecision).values(rows)
    stmt = stmt.on_conflict_do_update(
        constraint="uq_essentiel_triage_user_content_date",
        set_={
            "decision": stmt.excluded.decision,
            "rank": stmt.excluded.rank,
            "slate_size": stmt.excluded.slate_size,
            "decided_via": stmt.excluded.decided_via,
            "latency_ms": stmt.excluded.latency_ms,
            "updated_at": func.now(),
        },
    )
    await db.execute(stmt)

    # `later` = « mettre de côté », strictement le bouton signet de la carte.
    later_ids = [
        item.content_id for item in items if item.decision == TriageDecisionKind.LATER
    ]
    if later_ids:
        content_service = ContentService(db)
        for content_id in later_ids:
            await content_service.set_save_status(user_uuid, content_id, True)

    await db.commit()

    logger.info(
        "essentiel_triage_recorded",
        user_id=current_user_id,
        digest_date=str(payload.digest_date),
        slate_size=payload.slate_size,
        recorded=len(rows),
        skipped_unknown=len(by_content) - len(items),
        saved_for_later=len(later_ids),
    )
    return TriageBatchResponse(recorded=len(rows), saved_for_later=len(later_ids))
