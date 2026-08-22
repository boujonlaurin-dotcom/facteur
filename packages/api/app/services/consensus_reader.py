"""Analyse des angles 6C — service du Reader (Story 35.2, plan PR 2).

Trois responsabilités, toutes côté lecture/écriture à la demande :

1. **Résolution** ``content_id → coverage_analyses`` par jointure sur
   `coverage_analysis_articles` (index `ca01`). Le cache mémoire du pipeline
   meurt avec son instance et `digest_selector` en construit une neuve par
   requête : la relation est **déjà 1:N** en base. On borne par une fenêtre de
   fraîcheur (un article re-clusterisé dans un nouveau sujet ne doit pas servir
   les constats d'un événement précédent) et on tranche en Python —
   `state='available'` d'abord, puis la plus récente.
2. **Assemblage servi** : blocs ``consensus`` + ``display`` de
   ``GET /contents/{id}/perspectives``. L'attribution (≤ 2 logos par constat)
   est une décision **par utilisateur** prise ici à chaque requête — jamais
   écrite dans `_perspectives_cache` (partagé entre users) ni en base.
3. **Store partagé** : l'upsert de la ligne sujet + liens articles, utilisé par
   le pipeline (pré-génération) et par le write-through du
   ``POST /perspectives/analyze`` — une seule copie du SQL.
"""

from __future__ import annotations

import contextlib
from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import structlog
from cachetools import TTLCache
from sqlalchemy import and_, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.coverage_analysis import (
    CONSENSUS_STATE_AVAILABLE,
    CONSENSUS_STATE_PENDING,
    CONSENSUS_STATE_UNAVAILABLE,
    CoverageAnalysis,
    CoverageAnalysisArticle,
)
from app.models.enums import InterestState
from app.models.source import Source, UserSource
from app.services.editorial.consensus import (
    ConsensusPayload,
    build_corpus_index,
    compute_display_gates,
    empty_consensus_block,
    normalize_consensus,
    serve_consensus_block,
)
from app.services.perspective_service import (
    CONSENSUS_MODEL,
    CONSENSUS_PROMPT_VERSION,
    normalize_domain,
)

logger = structlog.get_logger(__name__)

# Call site du chemin paresseux dans `api_usage_events` : distinct de
# "editorial" (pré-génération pipeline) pour que le garde-fou quotidien et le
# suivi de coût ne comptent que les appels déclenchés par un tap Reader.
READER_CONSENSUS_CALL_SITE = "reader_consensus"

# « Suivies » au sens de l'attribution : l'axe déclaré par l'utilisateur.
_FOLLOWED_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)

# Domaines suivis par user — l'agrégation `user_sources` du choix des logos,
# demandée en cache par le plan (« pas de N+1 »). 5 min : suivre une source ne
# doit pas mettre une heure à réordonner les logos.
_followed_domains_cache: TTLCache = TTLCache(maxsize=1024, ttl=300)

# Notoriété globale domaine → (followers, is_curated). Une seule agrégation
# par heure et par process : le classement inter-médias bouge lentement.
_notoriety_cache: TTLCache = TTLCache(maxsize=1, ttl=3600)

_EPOCH = datetime.fromtimestamp(0, UTC)


def invalidate_caches() -> None:
    """Vide les caches d'attribution (tests)."""
    _followed_domains_cache.clear()
    _notoriety_cache.clear()


# --------------------------------------------------------------------------- #
# 1. Résolution content_id → analyse                                          #
# --------------------------------------------------------------------------- #


def pick_analysis_row(rows: list[CoverageAnalysis]) -> CoverageAnalysis | None:
    """Tranche le 1:N : une ligne `available` d'abord, puis la plus récente.

    Préférer `available` avant la date protège du scénario réel : la ligne du
    matin (pipeline, corpus complet) est bonne, un recompute on-demand plus
    tard sur un corpus voisin a échoué → la plus récente seule masquerait une
    analyse parfaitement servable.
    """
    if not rows:
        return None
    return max(
        rows,
        key=lambda row: (
            row.state == CONSENSUS_STATE_AVAILABLE,
            row.generated_at or _EPOCH,
        ),
    )


async def load_analysis_for_content(
    db: AsyncSession, content_id: UUID
) -> CoverageAnalysis | None:
    """La ligne `coverage_analyses` à servir pour cet article, ou None."""
    cutoff = datetime.now(UTC) - timedelta(
        hours=get_settings().consensus_reader_freshness_hours
    )
    stmt = (
        select(CoverageAnalysis)
        .join(
            CoverageAnalysisArticle,
            CoverageAnalysisArticle.coverage_analysis_id == CoverageAnalysis.id,
        )
        .where(
            CoverageAnalysisArticle.content_id == content_id,
            CoverageAnalysis.generated_at >= cutoff,
        )
    )
    rows = (await db.execute(stmt)).scalars().all()
    return pick_analysis_row(list(rows))


# --------------------------------------------------------------------------- #
# 2. Assemblage servi (attribution par user)                                  #
# --------------------------------------------------------------------------- #


async def get_followed_domains(db: AsyncSession, user_id: UUID) -> frozenset[str]:
    """Domaines (normalisés) des sources suivies par l'utilisateur."""
    cache_key = str(user_id)
    cached = _followed_domains_cache.get(cache_key)
    if cached is not None:
        return cached
    stmt = (
        select(Source.url)
        .join(UserSource, UserSource.source_id == Source.id)
        .where(
            UserSource.user_id == user_id,
            UserSource.state.in_(_FOLLOWED_STATES),
        )
    )
    urls = (await db.execute(stmt)).scalars().all()
    domains = frozenset(
        domain for domain in (normalize_domain(url) for url in urls) if domain
    )
    _followed_domains_cache[cache_key] = domains
    return domains


async def get_domain_notoriety(db: AsyncSession) -> dict[str, tuple[int, bool]]:
    """Notoriété par domaine : (nb de followers, `is_curated`).

    Le rang de repli de l'attribution quand l'utilisateur ne suit aucune des
    sources d'un constat. Dérivé de `count(user_sources)` — `source_tier` est
    explicitement écarté (E8 du plan : faux signal).
    """
    cached = _notoriety_cache.get("global")
    if cached is not None:
        return cached
    stmt = (
        select(Source.url, Source.is_curated, func.count(UserSource.id))
        .outerjoin(
            UserSource,
            and_(
                UserSource.source_id == Source.id,
                UserSource.state.in_(_FOLLOWED_STATES),
            ),
        )
        .where(Source.is_active.is_(True))
        .group_by(Source.id)
    )
    notoriety: dict[str, tuple[int, bool]] = {}
    for url, is_curated, followers in (await db.execute(stmt)).all():
        domain = normalize_domain(url)
        if not domain:
            continue
        candidate = (int(followers or 0), bool(is_curated))
        # Plusieurs sources peuvent partager un domaine (flux distincts d'un
        # même média) : on garde la plus notoire.
        if candidate > notoriety.get(domain, (-1, False)):
            notoriety[domain] = candidate
    _notoriety_cache["global"] = notoriety
    return notoriety


def _bias_by_domain_from_body(body: Mapping) -> dict[str, str]:
    """Biais par domaine, lu depuis le corpus **servi** (`perspectives[]`).

    C'est la même donnée que la barre de polarisation affichée : la règle des
    biais opposés doit raisonner sur ce que l'utilisateur voit, pas sur une
    résolution parallèle qui pourrait diverger.
    """
    bias: dict[str, str] = {}
    for perspective in body.get("perspectives") or []:
        if not isinstance(perspective, Mapping):
            continue
        domain = normalize_domain(
            perspective.get("source_domain") or perspective.get("url")
        )
        if domain and domain not in bias:
            bias[domain] = perspective.get("bias_stance") or "unknown"
    return bias


def _statement_domains(stored: Mapping) -> set[str]:
    domains: set[str] = set()
    for key in ("agreements", "disagreements"):
        items = stored.get(key)
        for item in items if isinstance(items, list) else []:
            if isinstance(item, Mapping):
                domains.update(
                    d for d in item.get("source_domains") or [] if isinstance(d, str)
                )
    return domains


def _derive_missing_state_block(body: Mapping) -> dict:
    """Pas de ligne fraîche : `pending` seulement si une analyse peut exister.

    Le seuil est le gate réel de génération (`divergence_llm_min_perspectives`,
    compté sur les alternatives servies) : « analyse en cours » ne doit jamais
    être une promesse que ni le pipeline ni le chemin paresseux ne tiendra.
    """
    alternatives = body.get("perspectives") or []
    gate = max(1, get_settings().divergence_llm_min_perspectives)
    state = (
        CONSENSUS_STATE_PENDING
        if len(alternatives) >= gate
        else CONSENSUS_STATE_UNAVAILABLE
    )
    return empty_consensus_block(state)


async def attach_consensus_blocks(
    db: AsyncSession,
    body: dict,
    *,
    content_id: UUID,
    user_id: UUID,
) -> dict:
    """Corps de réponse → **copie** enrichie des blocs `consensus` + `display`.

    Copie, pas mutation : `body` vit dans `_perspectives_cache`, partagé entre
    utilisateurs, et l'attribution est par-user. Best-effort intégral : le
    corpus et l'analyse sont deux dépendances qui tombent en panne séparément —
    une erreur ici dégrade vers un état dérivé du corpus, jamais vers un 500
    (même contrat que le store « Pas de recul »).
    """
    display = compute_display_gates(int(body.get("coverage_count") or 0))
    try:
        row = await load_analysis_for_content(db, content_id)
        if (
            row is not None
            and row.state == CONSENSUS_STATE_AVAILABLE
            and isinstance(row.consensus, dict)
        ):
            followed = await get_followed_domains(db, user_id)
            notoriety = await get_domain_notoriety(db)
            bias_by_domain = _bias_by_domain_from_body(body)
            # Un domaine de constat absent des alternatives servies est le
            # média en cours de lecture (exclu de la liste par construction) :
            # son biais est celui du pivot.
            pivot_bias = body.get("source_bias_stance") or "unknown"
            for domain in _statement_domains(row.consensus):
                bias_by_domain.setdefault(domain, pivot_bias)
            consensus = serve_consensus_block(
                row.consensus,
                generated_at=(
                    row.generated_at.isoformat() if row.generated_at else None
                ),
                followed=followed,
                notoriety=notoriety,
                bias_by_domain=bias_by_domain,
            )
        elif row is not None and row.state == CONSENSUS_STATE_UNAVAILABLE:
            # Échec définitif persisté (PR 1) : ne pas promettre « en cours ».
            consensus = empty_consensus_block(CONSENSUS_STATE_UNAVAILABLE)
        else:
            consensus = _derive_missing_state_block(body)
    except Exception as e:
        logger.warning(
            "consensus_attach_failed", content_id=str(content_id), error=str(e)
        )
        with contextlib.suppress(Exception):  # pragma: no cover - best-effort
            await db.rollback()
        consensus = _derive_missing_state_block(body)
    return {**body, "consensus": consensus, "display": display}


# --------------------------------------------------------------------------- #
# 3. Store partagé pipeline / write-through                                   #
# --------------------------------------------------------------------------- #


async def upsert_coverage_analysis(
    session: AsyncSession,
    *,
    subject_key: str,
    payload: ConsensusPayload,
    corpus_domains: list[str],
    coverage_count: int,
) -> UUID:
    """Upsert de la ligne sujet (idempotent par `subject_key`). Retourne l'id."""
    stmt = pg_insert(CoverageAnalysis).values(
        id=uuid4(),
        subject_key=subject_key,
        consensus=payload.model_dump(mode="json"),
        qualifier=payload.qualifier,
        state=payload.state,
        model_version=f"{CONSENSUS_MODEL}/{CONSENSUS_PROMPT_VERSION}",
        corpus_domains=corpus_domains,
        coverage_count=coverage_count,
        generated_at=datetime.now(UTC),
    )
    # `excluded` = la ligne qu'on tentait d'insérer (même motif que
    # `_upsert_deep_recommendations`) : les valeurs ne sont écrites qu'une
    # fois, le conflit ne fait que les réutiliser.
    stmt = stmt.on_conflict_do_update(
        index_elements=[CoverageAnalysis.subject_key],
        set_={
            "consensus": stmt.excluded.consensus,
            "qualifier": stmt.excluded.qualifier,
            "state": stmt.excluded.state,
            "model_version": stmt.excluded.model_version,
            "corpus_domains": stmt.excluded.corpus_domains,
            "coverage_count": stmt.excluded.coverage_count,
            "generated_at": stmt.excluded.generated_at,
        },
    ).returning(CoverageAnalysis.id)
    return (await session.execute(stmt)).scalar_one()


async def insert_analysis_links(
    session: AsyncSession, analysis_id: UUID, content_ids: list[UUID]
) -> None:
    """Liens sujet ↔ articles, idempotents (PK composite, DO NOTHING)."""
    if not content_ids:
        return
    await session.execute(
        pg_insert(CoverageAnalysisArticle)
        .values(
            [
                {"coverage_analysis_id": analysis_id, "content_id": content_id}
                for content_id in content_ids
            ]
        )
        .on_conflict_do_nothing(
            index_elements=[
                CoverageAnalysisArticle.coverage_analysis_id,
                CoverageAnalysisArticle.content_id,
            ]
        )
    )


async def write_through_analysis(
    session: AsyncSession,
    *,
    raw_result: dict,
    pivot_content_id: UUID,
    pivot_domain: str | None,
    pivot_bias: str,
    perspectives: list[dict],
    coverage_count: int,
) -> ConsensusPayload:
    """Chemin paresseux : normalise et persiste la sortie LLM d'un POST analyze.

    Le corpus inclut le pivot (un constat peut être porté par le média qu'on
    lit) ; les liens ne couvrent que les articles connus de `contents` — les
    résultats Google News n'ont pas de `content_id`, c'est attendu. Le
    `subject_key` reprend la signature de composition du pipeline : re-poster
    le même jeu d'articles réécrit la ligne au lieu d'en empiler une seconde.
    L'appelant gère commit/rollback.
    """
    from app.services.title_annotation_service import TitleAnnotationService

    pivot = {"source_domain": pivot_domain or "", "bias_stance": pivot_bias}
    corpus_domains, bias_by_domain = build_corpus_index([pivot, *perspectives])
    payload = normalize_consensus(raw_result, corpus_domains, bias_by_domain)

    content_ids: list[UUID] = [pivot_content_id]
    for perspective in perspectives:
        raw_id = (
            perspective.get("content_id") if isinstance(perspective, Mapping) else None
        )
        if not raw_id:
            continue
        try:
            parsed = UUID(str(raw_id))
        except (ValueError, TypeError):
            continue
        if parsed not in content_ids:
            content_ids.append(parsed)

    analysis_id = await upsert_coverage_analysis(
        session,
        subject_key=TitleAnnotationService.compute_cluster_signature(content_ids),
        payload=payload,
        corpus_domains=corpus_domains,
        coverage_count=coverage_count,
    )
    await insert_analysis_links(session, analysis_id, content_ids)
    return payload
