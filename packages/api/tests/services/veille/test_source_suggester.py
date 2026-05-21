"""Tests pour SourceSuggester (Story 23.3) — pas de DB, pas de HTTP, mock LLM."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.veille.llm.source_suggester import SourceSuggester


def _mk_llm(*, ready: bool, response: dict | None) -> MagicMock:
    llm = MagicMock()
    llm.is_ready = ready
    llm.chat_json = AsyncMock(return_value=response)
    return llm


async def test_suggest_sources_happy_path():
    llm = _mk_llm(
        ready=True,
        response={
            "sources": [
                {
                    "name": "MACBA",
                    "url": "https://www.macba.cat",
                    "why": "Musée officiel.",
                    "relevance_score": 1.0,
                },
                {
                    "name": "CCCB",
                    "url": "https://www.cccb.org",
                    "why": "Centre culturel.",
                    "relevance_score": 0.9,
                },
            ]
        },
    )
    suggester = SourceSuggester(llm=llm)
    sources = await suggester.suggest_sources(
        theme_id="other",
        theme_label="Musées Barcelone",
        brief="Sorties expos",
        angles=["Expositions temporaires"],
        keywords=["expo", "macba"],
    )
    assert len(sources) == 2
    # Trié desc par relevance_score
    assert sources[0].relevance_score == 1.0
    assert sources[0].name == "MACBA"


async def test_suggest_sources_dedupe_by_domain():
    llm = _mk_llm(
        ready=True,
        response={
            "sources": [
                {
                    "name": "Le Monde Tech",
                    "url": "https://www.lemonde.fr/tech",
                    "why": "Section tech.",
                    "relevance_score": 0.6,
                },
                {
                    "name": "Le Monde",
                    "url": "https://lemonde.fr",
                    "why": "Quotidien.",
                    "relevance_score": 0.9,
                },
            ]
        },
    )
    suggester = SourceSuggester(llm=llm)
    sources = await suggester.suggest_sources(
        theme_id="tech", theme_label="Tech", brief="", angles=[], keywords=[]
    )
    # Garde la version avec le plus haut score
    assert len(sources) == 1
    assert sources[0].relevance_score == 0.9


async def test_suggest_sources_cache_hit():
    llm = _mk_llm(
        ready=True,
        response={
            "sources": [
                {
                    "name": "X",
                    "url": "https://x.com",
                    "why": None,
                    "relevance_score": 0.5,
                }
            ]
        },
    )
    suggester = SourceSuggester(llm=llm)
    await suggester.suggest_sources("tech", "Tech", "brief", ["a1"], ["k1"])
    await suggester.suggest_sources("tech", "Tech", "brief", ["a1"], ["k1"])
    assert llm.chat_json.call_count == 1


async def test_suggest_sources_cache_key_independent_of_angle_order():
    llm = _mk_llm(
        ready=True,
        response={
            "sources": [
                {
                    "name": "X",
                    "url": "https://x.com",
                    "why": None,
                    "relevance_score": 0.5,
                }
            ]
        },
    )
    suggester = SourceSuggester(llm=llm)
    await suggester.suggest_sources("tech", "Tech", "b", ["a1", "a2"], ["k1", "k2"])
    await suggester.suggest_sources("tech", "Tech", "b", ["a2", "a1"], ["k2", "k1"])
    assert llm.chat_json.call_count == 1


async def test_suggest_sources_empty_when_llm_not_ready():
    llm = _mk_llm(ready=False, response=None)
    suggester = SourceSuggester(llm=llm)
    sources = await suggester.suggest_sources("tech", "Tech", "", [], [])
    assert sources == []
    llm.chat_json.assert_not_called()


async def test_suggest_sources_empty_when_llm_returns_garbage():
    llm = _mk_llm(ready=True, response={"unexpected": "shape"})
    suggester = SourceSuggester(llm=llm)
    sources = await suggester.suggest_sources("tech", "Tech", "", [], [])
    assert sources == []


async def test_suggest_sources_skips_invalid_items():
    llm = _mk_llm(
        ready=True,
        response={
            "sources": [
                {"name": "OK", "url": "https://ok.com", "why": "good", "relevance_score": 0.8},
                {"name": "", "url": "https://bad.com", "why": None, "relevance_score": 0.5},
                {"name": "BadScore", "url": "https://bad2.com", "why": None, "relevance_score": 1.5},
            ]
        },
    )
    suggester = SourceSuggester(llm=llm)
    sources = await suggester.suggest_sources("tech", "Tech", "", [], [])
    assert len(sources) == 1
    assert sources[0].name == "OK"
