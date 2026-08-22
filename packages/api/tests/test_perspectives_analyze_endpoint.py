"""POST /contents/{id}/perspectives/analyze — chemin paresseux 6C (Story 35.2).

Deux promesses : la bascule sur `analyze_consensus` reste **compatible** (le
parc installé lit toujours `analysis` markdown), et le garde-fou de budget
quotidien coupe l'appel LLM sans casser la réponse ni empoisonner le cache.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.routers import contents as contents_router
from app.routers.contents import (
    _analysis_cache,
    _perspectives_cache,
    analyze_perspectives,
)

LLM_RESULT = {
    "analysis": "Le fait établi.\n\n→ **portée** : débat.",
    "divergence_level": "medium",
    "agreements": [
        {
            "text": "Un accord recevable, attribué au corpus.",
            "source_domains": ["alt.fr"],
        }
    ],
    "disagreements": [],
    "cta_agreement": {"text": "Accord court."},
}


def _content_mock():
    content = MagicMock()
    content.title = "Titre de l'article"
    content.description = "Description."
    content.source.name = "Media"
    content.source.url = "https://media.fr"
    content.source.bias_stance = None
    return content


def _db_mock(content):
    def _first_result(value):
        result = MagicMock()
        result.scalars.return_value.first.return_value = value
        return result

    db = AsyncMock()
    # 1er execute : lookup `perspective_analyses` (vide) ; 2e : le Content ;
    # les suivants : l'INSERT legacy.
    db.execute = AsyncMock(
        side_effect=[_first_result(None), _first_result(content), MagicMock()]
    )
    return db


def _seed_perspectives_cache(key: str) -> dict:
    body = {
        "perspectives": [
            {
                "title": "Alt",
                "source_name": "Alt",
                "source_domain": "alt.fr",
                "bias_stance": "left",
                "content_id": None,
            }
        ],
        "source_bias_stance": "center",
        "coverage_count": 2,
    }
    _perspectives_cache[key] = body
    return body


@pytest.fixture(autouse=True)
def _clean_caches():
    _analysis_cache.clear()
    _perspectives_cache.clear()
    yield
    _analysis_cache.clear()
    _perspectives_cache.clear()


@pytest.mark.asyncio
async def test_nominal_generation_keeps_legacy_contract_and_writes_through():
    content_id = uuid4()
    key = str(content_id)
    _seed_perspectives_cache(key)
    content = _content_mock()
    db = _db_mock(content)
    write_through = AsyncMock()
    service_cls = MagicMock()
    service_cls.return_value.analyze_consensus = AsyncMock(return_value=LLM_RESULT)

    with (
        patch.object(
            contents_router, "is_over_daily_cap", AsyncMock(return_value=False)
        ),
        patch("app.services.perspective_service.PerspectiveService", service_cls),
        patch.object(contents_router, "write_through_analysis", write_through),
    ):
        response = await analyze_perspectives(
            content_id=content_id, db=db, current_user_id=str(uuid4())
        )

    # Contrat legacy intact : le parc installé lit `analysis` markdown.
    assert response["analysis"] == LLM_RESULT["analysis"]
    assert response["divergence_level"] == "medium"
    assert response["cached"] is False
    # Le chemin paresseux est mesuré et plafonné seul : call site dédié.
    call_kwargs = service_cls.return_value.analyze_consensus.await_args.kwargs
    assert call_kwargs["call_site"] == "reader_consensus"
    # Write-through structuré vers `coverage_analyses`.
    write_through.assert_awaited_once()
    wt_kwargs = write_through.await_args.kwargs
    assert wt_kwargs["pivot_content_id"] == content_id
    assert wt_kwargs["coverage_count"] == 2
    assert wt_kwargs["pivot_domain"] == "media.fr"
    # La réponse est cachée, le cache perspectives invalidé (analysis fraîche).
    assert _analysis_cache[key] is response
    assert key not in _perspectives_cache


@pytest.mark.asyncio
async def test_daily_cap_short_circuits_the_llm_without_poisoning_caches():
    content_id = uuid4()
    key = str(content_id)
    _seed_perspectives_cache(key)
    content = _content_mock()
    db = _db_mock(content)
    service_cls = MagicMock()
    service_cls.return_value.analyze_consensus = AsyncMock()

    with (
        patch.object(
            contents_router, "is_over_daily_cap", AsyncMock(return_value=True)
        ),
        patch("app.services.perspective_service.PerspectiveService", service_cls),
    ):
        response = await analyze_perspectives(
            content_id=content_id, db=db, current_user_id=str(uuid4())
        )

    assert response["throttled"] is True
    assert response["analysis"] is None
    service_cls.return_value.analyze_consensus.assert_not_awaited()
    # Non caché : au prochain jour (ou TTL du COUNT), un tap regénère.
    assert key not in _analysis_cache


@pytest.mark.asyncio
async def test_write_through_failure_does_not_lose_the_paid_markdown():
    """Best-effort : un échec DB côté `coverage_analyses` ne prive pas
    l'utilisateur de l'analyse qu'il vient de payer."""
    content_id = uuid4()
    key = str(content_id)
    _seed_perspectives_cache(key)
    content = _content_mock()
    db = _db_mock(content)
    service_cls = MagicMock()
    service_cls.return_value.analyze_consensus = AsyncMock(return_value=LLM_RESULT)

    with (
        patch.object(
            contents_router, "is_over_daily_cap", AsyncMock(return_value=False)
        ),
        patch("app.services.perspective_service.PerspectiveService", service_cls),
        patch.object(
            contents_router,
            "write_through_analysis",
            AsyncMock(side_effect=RuntimeError("db down")),
        ),
    ):
        response = await analyze_perspectives(
            content_id=content_id, db=db, current_user_id=str(uuid4())
        )

    assert response["analysis"] == LLM_RESULT["analysis"]
    db.rollback.assert_awaited()


@pytest.mark.asyncio
async def test_get_cache_hit_serves_6c_blocks_without_mutating_shared_body():
    """GET /perspectives, chemin cache : les blocs `consensus`/`display` sont
    résolus par requête (par user) — le corps partagé du cache n'en garde
    aucune trace."""
    from app.services import consensus_reader

    content_id = uuid4()
    key = str(content_id)
    cached_body = _seed_perspectives_cache(key)
    cached_body["partial"] = False
    response = MagicMock()
    response.headers = {}

    with (
        patch.object(contents_router, "_attach_deep_from_store", AsyncMock()),
        patch.object(
            consensus_reader,
            "load_analysis_for_content",
            AsyncMock(return_value=None),
        ),
    ):
        served = await contents_router.get_perspectives(
            content_id=content_id,
            response=response,
            background_tasks=MagicMock(),
            db=AsyncMock(),
            current_user_id=str(uuid4()),
        )

    # 1 alternative < gate (2) : rien ne génèrera jamais → `unavailable`,
    # pas une promesse « en cours ». À 2 médias le design n'affiche de toute
    # façon pas de carte IA — mais le CTA et le carrousel restent.
    assert served["consensus"]["state"] == "unavailable"
    assert served["display"]["has_cta"] is True
    assert served["display"]["has_ai_card"] is False
    assert "consensus" not in _perspectives_cache[key]
    assert "display" not in _perspectives_cache[key]
