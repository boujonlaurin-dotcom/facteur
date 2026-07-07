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
    # `reason` n'est plus généré ni parsé (perf) — toujours None même si le LLM
    # en renvoie un dans son payload.
    assert angles[0].reason is None
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


# ─── Filtre post-parse des mots-clés génériques (F) ──────────────────────────


async def test_parse_drops_generic_unigrams_keeps_multiword():
    """Un unigramme de discours (« stratégie », « europe ») est retiré ; une
    expression multi-mots (« conseil constitutionnel ») et un nom propre isolé
    (« macron ») sont conservés."""
    llm = _mk_llm(
        ready=True,
        response={
            "angles": [
                {
                    "title": "Vie institutionnelle",
                    "keywords": [
                        "stratégie",
                        "europe",
                        "conseil constitutionnel",
                        "macron",
                    ],
                }
            ]
        },
    )
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("politics", "Politique", "")
    assert len(angles) == 1
    assert angles[0].keywords == ["conseil constitutionnel", "macron"]


async def test_parse_drops_angle_emptied_by_filter():
    """Un angle dont TOUS les mots-clés sont génériques est écarté ; les autres
    angles survivent."""
    llm = _mk_llm(
        ready=True,
        response={
            "angles": [
                {"title": "Discours creux", "keywords": ["analyse", "enjeux", "débat"]},
                {
                    "title": "Sujet précis",
                    "keywords": ["intelligence artificielle générative", "mistral ai"],
                },
            ]
        },
    )
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Tech", "")
    assert len(angles) == 1
    assert angles[0].title == "Sujet précis"


async def test_parse_drops_stopword_unigram():
    """Un stopword FR isolé (« pour ») est retiré comme un générique."""
    llm = _mk_llm(
        ready=True,
        response={"angles": [{"title": "T", "keywords": ["pour", "coupe du monde"]}]},
    )
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("sport", "Sport", "")
    assert angles[0].keywords == ["coupe du monde"]


async def test_fallback_uses_multiword_keywords():
    """Les angles de repli sont ancrés sur le thème via des expressions
    multi-mots (survivent au floor durci + au filtre denylist)."""
    llm = _mk_llm(ready=False, response=None)
    suggester = AngleSuggester(llm=llm)
    angles = await suggester.suggest_angles("tech", "Tech", "")
    assert len(angles) >= 3
    # Chaque mot-clé de repli est multi-mots (contient une espace).
    assert all(" " in kw for a in angles for kw in a.keywords)
