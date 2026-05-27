"""Tests pour `LLMBiasAnnotationService` (PR 1 Phase 4 — LLM bias annotation).

Tests hermétiques : aucun appel API réel (mock `chat_json`).
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.llm_bias_annotation_service import (
    ALLOWED_WEIGHTS,
    DEFAULT_MODEL,
    EXCLUDE_CATEGORIES,
    LLM_VERSION,
    SCHEMA_DESCRIPTION,
    TARGET_CATEGORIES,
    LLMBiasAnnotationService,
    find_span,
)


SNAPSHOT_PATH = (
    Path(__file__).resolve().parents[1] / "snapshots" / "llm_system_prompt.txt"
)


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------


def test_constants_locked():
    """Verrouille les contrats publics du module (cf. plan.md)."""
    assert LLM_VERSION == "mistral-medium-latest-v2"
    assert DEFAULT_MODEL == "mistral-medium-latest"
    assert TARGET_CATEGORIES == {
        "editorial_angle",
        "fact",
        "multi_token_expression",
        "framing_noun",
        "foreign_lang",
    }
    assert EXCLUDE_CATEGORIES == {
        "pivot_entity",
        "neutral_verb",
        "entity_alias",
        "geographic_alias",
        "noise",
    }
    assert ALLOWED_WEIGHTS == {0.25, 0.5, 1.0}


# ---------------------------------------------------------------------------
# find_span (apostrophes typographiques + NBSP)
# ---------------------------------------------------------------------------


def test_find_span_direct():
    assert find_span("Trump écrase Massie", "écrase") == (6, 12)


def test_find_span_typographic_apostrophe():
    title = "L’étrange voyage de Marco Rubio"
    res = find_span(title, "L'étrange")
    assert res is not None
    s, e = res
    assert title[s:e] == "L’étrange"


def test_find_span_nbsp():
    title = "Bolloré\xa0: nouvelle polémique"
    res = find_span(title, "Bolloré : nouvelle polémique")
    assert res is not None
    s, e = res
    assert title[s:e] == "Bolloré\xa0: nouvelle polémique"


def test_find_span_not_found():
    assert find_span("Trump écrase Massie", "Macron") is None


def test_find_span_empty():
    assert find_span("title", "") is None


# ---------------------------------------------------------------------------
# Snapshot du prompt système (anti-dérive silencieuse)
# ---------------------------------------------------------------------------


def test_schema_description_matches_snapshot():
    """Anti-dérive : si le prompt change, le test échoue → décision explicite
    d'incrémenter `LLM_VERSION` + de regénérer le snapshot."""
    snapshot = SNAPSHOT_PATH.read_text(encoding="utf-8")
    assert SCHEMA_DESCRIPTION == snapshot, (
        "SCHEMA_DESCRIPTION a divergé du snapshot. "
        "Si le changement est volontaire : incrémente `LLM_VERSION` "
        "dans llm_bias_annotation_service.py puis regénère le snapshot."
    )


# ---------------------------------------------------------------------------
# build_system_prompt / build_user_prompt
# ---------------------------------------------------------------------------


def test_build_system_prompt_without_examples():
    svc = LLMBiasAnnotationService(client=_dummy_client())
    assert svc.build_system_prompt() == SCHEMA_DESCRIPTION


def test_build_system_prompt_with_examples():
    svc = LLMBiasAnnotationService(client=_dummy_client())
    prompt = svc.build_system_prompt(
        fewshot_examples=["### exemple 1 ...", "### exemple 2 ..."]
    )
    assert prompt.startswith(SCHEMA_DESCRIPTION)
    assert "Exemples calibrés par le PO" in prompt
    assert "### exemple 1" in prompt
    assert "### exemple 2" in prompt


def test_build_user_prompt_shape():
    prompt = LLMBiasAnnotationService.build_user_prompt(
        ref_title="Trump bat Massie",
        variant_title="Trump écrase Massie",
        bias_stance="left",
        peers=["Massie défait", "Le Kentucky vote"],
    )
    assert "Trump bat Massie" in prompt
    assert "Trump écrase Massie" in prompt
    assert "bias = left" in prompt
    assert "Massie défait" in prompt
    assert "Le Kentucky vote" in prompt


def test_build_user_prompt_without_peers():
    prompt = LLMBiasAnnotationService.build_user_prompt(
        ref_title="ref",
        variant_title="variant",
        bias_stance="center",
    )
    assert "Autres titres du cluster" not in prompt


# ---------------------------------------------------------------------------
# validate_response — happy path
# ---------------------------------------------------------------------------


TITLE = "Trump écrase Massie : la mainmise sur le parti"


def test_validate_nominal():
    payload = {
        "target_spans": [
            {
                "text": "écrase",
                "category": "editorial_angle",
                "weight": 1.0,
                "justification": "Verbe chargé qui éditorialise la défaite.",
            },
            {
                "text": "mainmise",
                "category": "framing_noun",
                "weight": 1.0,
                "justification": "Choix nominal partisan.",
            },
        ],
        "exclude_spans": [
            {"text": "Trump", "category": "pivot_entity"},
            {"text": "Massie", "category": "pivot_entity"},
        ],
        "notes": "ok",
        "confidence": 0.8,
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert len(cleaned["target_spans"]) == 2
    assert len(cleaned["exclude_spans"]) == 2
    assert cleaned["target_spans"][0]["text"] == "écrase"
    assert cleaned["target_spans"][0]["start"] == TITLE.index("écrase")
    assert cleaned["target_spans"][0]["justification"].startswith("Verbe chargé")
    assert cleaned["confidence"] == 0.8


def test_validate_accepts_empty_spans():
    cleaned = LLMBiasAnnotationService.validate_response(
        {"target_spans": [], "exclude_spans": [], "notes": ""}, TITLE
    )
    assert cleaned is not None
    assert cleaned["target_spans"] == []
    assert cleaned["exclude_spans"] == []


def test_validate_justification_missing_yields_none():
    payload = {
        "target_spans": [
            {"text": "écrase", "category": "editorial_angle", "weight": 1.0}
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert cleaned["target_spans"][0]["justification"] is None


def test_validate_typographic_apostrophe_round_trips():
    title = "L’étrange retour"
    payload = {
        "target_spans": [
            {
                "text": "L'étrange",  # apostrophe ASCII
                "category": "editorial_angle",
                "weight": 0.5,
            }
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, title)
    assert cleaned is not None
    span = cleaned["target_spans"][0]
    assert title[span["start"] : span["end"]] == "L’étrange"


# ---------------------------------------------------------------------------
# validate_response — drop-and-log graceful degradation
# ---------------------------------------------------------------------------


def test_validate_drops_unknown_target_category_keeps_valid_ones():
    payload = {
        "target_spans": [
            {"text": "écrase", "category": "editorial_angle", "weight": 1.0},
            {"text": "mainmise", "category": "wat", "weight": 1.0},  # bad
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert len(cleaned["target_spans"]) == 1
    assert cleaned["target_spans"][0]["text"] == "écrase"


def test_validate_drops_bad_weight():
    payload = {
        "target_spans": [
            {"text": "écrase", "category": "editorial_angle", "weight": 0.7}
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert cleaned["target_spans"] == []


def test_validate_drops_span_text_not_in_title():
    payload = {
        "target_spans": [
            {"text": "Macron", "category": "editorial_angle", "weight": 1.0}
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert cleaned["target_spans"] == []


def test_validate_drops_unknown_exclude_category():
    payload = {
        "target_spans": [],
        "exclude_spans": [{"text": "Trump", "category": "alien"}],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert cleaned["exclude_spans"] == []


def test_validate_drops_non_dict_span_entries():
    payload = {
        "target_spans": [
            "string-instead-of-dict",
            {"text": "écrase", "category": "editorial_angle", "weight": 1.0},
        ],
        "exclude_spans": [],
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert len(cleaned["target_spans"]) == 1


# ---------------------------------------------------------------------------
# validate_response — racine invalide → None
# ---------------------------------------------------------------------------


def test_validate_non_dict_root_returns_none():
    assert LLMBiasAnnotationService.validate_response([], TITLE) is None
    assert LLMBiasAnnotationService.validate_response("nope", TITLE) is None
    assert LLMBiasAnnotationService.validate_response(None, TITLE) is None


def test_validate_target_spans_not_a_list_returns_none():
    assert (
        LLMBiasAnnotationService.validate_response(
            {"target_spans": "oops", "exclude_spans": []}, TITLE
        )
        is None
    )


def test_validate_exclude_spans_not_a_list_returns_none():
    assert (
        LLMBiasAnnotationService.validate_response(
            {"target_spans": [], "exclude_spans": "oops"}, TITLE
        )
        is None
    )


def test_validate_confidence_unparseable_becomes_none():
    payload = {
        "target_spans": [],
        "exclude_spans": [],
        "confidence": "high",
    }
    cleaned = LLMBiasAnnotationService.validate_response(payload, TITLE)
    assert cleaned is not None
    assert cleaned["confidence"] is None


# ---------------------------------------------------------------------------
# annotate_variant — async + mocks
# ---------------------------------------------------------------------------


def _dummy_client() -> MagicMock:
    client = MagicMock()
    client.is_ready = True
    client.chat_json = AsyncMock(return_value=None)
    client.close = AsyncMock()
    return client


@pytest.mark.asyncio
async def test_annotate_variant_calls_chat_json_with_v2_schema():
    client = _dummy_client()
    client.chat_json.return_value = {
        "target_spans": [
            {
                "text": "écrase",
                "category": "editorial_angle",
                "weight": 1.0,
                "justification": "verbe chargé",
            }
        ],
        "exclude_spans": [],
        "notes": "",
        "confidence": 0.9,
    }
    svc = LLMBiasAnnotationService(client=client)

    result = await svc.annotate_variant(
        ref_title="Trump bat Massie",
        variant_title=TITLE,
        bias_stance="left",
        peers=["autre titre"],
    )

    client.chat_json.assert_awaited_once()
    call_kwargs = client.chat_json.await_args.kwargs
    assert call_kwargs["model"] == DEFAULT_MODEL
    assert call_kwargs["temperature"] == 0.1
    assert "bias = left" in call_kwargs["user_message"]
    assert "Trump bat Massie" in call_kwargs["user_message"]
    assert call_kwargs["system"].startswith(SCHEMA_DESCRIPTION[:80])

    assert result is not None
    assert len(result["target_spans"]) == 1
    assert result["target_spans"][0]["start"] == TITLE.index("écrase")


@pytest.mark.asyncio
async def test_annotate_variant_returns_none_when_client_returns_none():
    client = _dummy_client()
    client.chat_json.return_value = None
    svc = LLMBiasAnnotationService(client=client)
    result = await svc.annotate_variant(
        ref_title="r", variant_title="v", bias_stance="center"
    )
    assert result is None


@pytest.mark.asyncio
async def test_annotate_variant_returns_none_on_bad_root_payload():
    client = _dummy_client()
    client.chat_json.return_value = ["not", "a", "dict"]
    svc = LLMBiasAnnotationService(client=client)
    result = await svc.annotate_variant(
        ref_title="r", variant_title="v", bias_stance="center"
    )
    assert result is None


@pytest.mark.asyncio
async def test_annotate_variant_drops_hallucinated_spans_but_returns_dict():
    """Si le LLM hallucine un span (`text` introuvable), on droppe ce span
    seul et on renvoie quand même un dict avec les autres spans valides —
    pas de crash. Cf. plan.md cas limite « LLM hallucine start/end »."""
    client = _dummy_client()
    client.chat_json.return_value = {
        "target_spans": [
            {
                "text": "écrase",
                "category": "editorial_angle",
                "weight": 1.0,
            },
            {
                "text": "phantom",
                "category": "editorial_angle",
                "weight": 1.0,
            },
        ],
        "exclude_spans": [],
        "notes": "",
        "confidence": 0.5,
    }
    svc = LLMBiasAnnotationService(client=client)
    result = await svc.annotate_variant(
        ref_title="r", variant_title=TITLE, bias_stance="left"
    )
    assert result is not None
    texts = [s["text"] for s in result["target_spans"]]
    assert texts == ["écrase"]


@pytest.mark.asyncio
async def test_service_close_propagates():
    client = _dummy_client()
    svc = LLMBiasAnnotationService(client=client)
    await svc.close()
    client.close.assert_awaited_once()
