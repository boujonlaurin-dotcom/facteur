"""Budget LLM sur enrich/disambiguate (bug onboarding custom-topics-deferred-save).

Le chemin create/disambiguate borne l'appel Mistral avec `llm_timeout` : un LLM
lent doit retomber vite sur le fallback fuzzy au lieu de laisser le client
onboarding atteindre son `receiveTimeout` (30 s) → échec silencieux de sauvegarde.
"""

import asyncio

import pytest

from app.services.ml.topic_enrichment_service import (
    TopicEnrichmentResult,
    TopicEnrichmentService,
)


def _ready_service() -> TopicEnrichmentService:
    svc = TopicEnrichmentService()
    # Force le chemin LLM (indépendamment de la présence d'une vraie clé en CI).
    svc._ready = True
    return svc


@pytest.mark.asyncio
async def test_enrich_falls_back_fast_when_llm_hangs():
    svc = _ready_service()

    async def _hang(_name: str) -> TopicEnrichmentResult:
        await asyncio.sleep(5)  # LLM qui traîne au-delà du budget
        raise AssertionError("should have been cancelled by the budget")

    svc._enrich_via_llm = _hang  # type: ignore[assignment]

    result = await asyncio.wait_for(
        svc.enrich("Voiture électrique", llm_timeout=0.05), timeout=1.0
    )
    # Fallback fuzzy → toujours un slug valide, jamais une exception ni un hang.
    assert isinstance(result, TopicEnrichmentResult)
    assert result.slug_parent
    assert result.keywords


@pytest.mark.asyncio
async def test_enrich_uses_llm_result_when_it_answers_in_budget():
    svc = _ready_service()

    async def _fast(name: str) -> TopicEnrichmentResult:
        return TopicEnrichmentResult(
            slug_parent="tech",
            keywords=["gpt"],
            intent_description="Suivi de l'IA",
        )

    svc._enrich_via_llm = _fast  # type: ignore[assignment]

    result = await svc.enrich("GPT-5", llm_timeout=1.0)
    assert result.slug_parent == "tech"
    assert result.keywords == ["gpt"]


@pytest.mark.asyncio
async def test_disambiguate_falls_back_fast_when_llm_hangs():
    svc = _ready_service()

    async def _hang(_name: str, _theme):  # noqa: ANN001
        await asyncio.sleep(5)
        raise AssertionError("should have been cancelled by the budget")

    async def _fallback_enrich(name: str, *, llm_timeout=None) -> TopicEnrichmentResult:
        # La retombée disambiguate → enrich doit elle aussi être bornée.
        assert llm_timeout == 0.05
        return TopicEnrichmentResult(
            slug_parent="tech",
            keywords=[name.lower()],
            intent_description="",
        )

    svc._disambiguate_via_llm = _hang  # type: ignore[assignment]
    svc.enrich = _fallback_enrich  # type: ignore[assignment]

    candidates = await asyncio.wait_for(
        svc.disambiguate("Apple", theme="tech", llm_timeout=0.05), timeout=1.0
    )
    assert len(candidates) == 1
    assert candidates[0].slug_parent == "tech"
