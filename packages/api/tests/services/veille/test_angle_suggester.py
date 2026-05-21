"""Tests pour AngleSuggester (Story 23.3) — pas de DB, mock LLM."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.veille.llm.angle_suggester import (
    AngleSuggester,
    AngleSuggestion,
)


def _mk_llm(*, ready: bool, response: dict | None) -> MagicMock:
    llm = MagicMock()
    llm.is_ready = ready
    llm.chat_json = AsyncMock(return_value=response)
    return llm


async def test_suggest_angles_happy_path():
    llm = _mk_llm(
        ready=True,
        response={
            "angles": [
                {
                    "title": "Nouvelles expositions",
                    "keywords": ["exposition", "vernissage", "macba"],
                    "reason": "Cible les annonces.",
                },
                {
                    "title": "Artistes émergents",
                    "keywords": ["artiste émergent", "jeune création"],
                    "reason": None,
                },
            ]
        },
    )
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles(
        theme_id="other",
        theme_label="Musées Barcelone",
        brief="Suivre les sorties.",
    )
    assert len(angles) == 2
    assert angles[0].title == "Nouvelles expositions"
    assert angles[0].keywords == ["exposition", "vernissage", "macba"]
    assert angles[0].reason == "Cible les annonces."
    assert angles[1].reason is None


async def test_suggest_angles_cache_hit():
    llm = _mk_llm(
        ready=True,
        response={"angles": [{"title": "T", "keywords": ["k1"], "reason": None}]},
    )
    suggester = AngleSuggester(llm=llm)
    await suggester.suggest_angles("tech", "Tech", "brief")
    await suggester.suggest_angles("tech", "Tech", "brief")
    # 1 seul appel LLM malgré 2 appels suggest
    assert llm.chat_json.call_count == 1


async def test_suggest_angles_cache_key_normalises_brief():
    """Brief avec espaces/casse différents doit hit le même cache."""
    llm = _mk_llm(
        ready=True,
        response={"angles": [{"title": "T", "keywords": ["k1"], "reason": None}]},
    )
    suggester = AngleSuggester(llm=llm)
    await suggester.suggest_angles("tech", "Tech", "Mon Brief")
    await suggester.suggest_angles("tech", "Tech", "  mon brief  ")
    assert llm.chat_json.call_count == 1


async def test_suggest_angles_fallback_when_llm_not_ready():
    llm = _mk_llm(ready=False, response=None)
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Technologie", "")
    assert len(angles) >= 3
    assert all(isinstance(a, AngleSuggestion) for a in angles)
    assert all(len(a.keywords) >= 1 for a in angles)
    llm.chat_json.assert_not_called()


async def test_suggest_angles_fallback_when_llm_returns_garbage():
    llm = _mk_llm(ready=True, response={"unexpected": "shape"})
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Technologie", "")
    assert len(angles) >= 3


async def test_suggest_angles_fallback_when_llm_returns_none():
    llm = _mk_llm(ready=True, response=None)
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Tech", "")
    assert len(angles) >= 3


async def test_suggest_angles_keywords_lowercased_and_stripped():
    llm = _mk_llm(
        ready=True,
        response={
            "angles": [
                {
                    "title": "Test",
                    "keywords": ["  MAJUSCULES  ", "espaces internes ok", ""],
                    "reason": None,
                }
            ]
        },
    )
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Tech", "")
    assert angles[0].keywords == ["majuscules", "espaces internes ok"]
