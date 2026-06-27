"""Tests unitaires pour `good_news_classifier` (parsing + batch wiring).

Pas d'appel réseau : on stubbe `_call` pour vérifier le parsing et la
forme du payload.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.ml.good_news_classifier import (
    GoodNewsClassifier,
    _build_user_prompt,
    _parse_response,
)


class TestParseResponse:
    def test_array_of_dicts(self) -> None:
        raw = '[{"good_news": true}, {"good_news": false}, {"good_news": true}]'
        assert _parse_response(raw, expected_count=3) == [True, False, True]

    def test_array_of_bools(self) -> None:
        raw = "[true, false, true]"
        assert _parse_response(raw, expected_count=3) == [True, False, True]

    def test_padding_when_short(self) -> None:
        raw = '[{"good_news": true}]'
        assert _parse_response(raw, expected_count=3) == [True, None, None]

    def test_truncation_when_long(self) -> None:
        raw = '[{"good_news": true}, {"good_news": false}, {"good_news": true}]'
        assert _parse_response(raw, expected_count=2) == [True, False]

    def test_invalid_json(self) -> None:
        assert _parse_response("not json", expected_count=2) == [None, None]

    def test_non_bool_value(self) -> None:
        raw = '[{"good_news": "yes"}, {"good_news": 1}, {"good_news": null}]'
        assert _parse_response(raw, expected_count=3) == [None, None, None]

    def test_dict_root_falls_back_to_none(self) -> None:
        # Le modèle peut renvoyer un objet wrappé en JSON mode ; si la racine
        # n'est pas une liste, on renvoie une liste de None.
        raw = '{"results": [{"good_news": true}]}'
        assert _parse_response(raw, expected_count=1) == [None]


class TestBuildUserPrompt:
    def test_includes_indices_and_titles(self) -> None:
        prompt = _build_user_prompt(
            [
                {
                    "title": "Article un",
                    "description": "desc 1",
                    "source_name": "Le Monde",
                },
                {
                    "title": "Article deux",
                    "description": "desc 2",
                    "source_name": "Reporterre",
                },
            ]
        )
        assert "Article un" in prompt
        assert "Article deux" in prompt
        assert "[1]" in prompt
        assert "[2]" in prompt
        assert "Source: Le Monde" in prompt
        assert "Source: Reporterre" in prompt
        assert "exactement 2 éléments" in prompt

    def test_truncates_long_description(self) -> None:
        long_desc = "x" * 1000
        prompt = _build_user_prompt(
            [{"title": "T", "description": long_desc, "source_name": "S"}]
        )
        # 240 + ellipsis
        assert "..." in prompt
        assert "x" * 250 not in prompt

    def test_handles_empty_description(self) -> None:
        prompt = _build_user_prompt(
            [{"title": "Titre seul", "description": "", "source_name": "Le Monde"}]
        )
        assert "Titre seul" in prompt


class TestClassifierBatch:
    @pytest.mark.asyncio
    async def test_empty_input(self) -> None:
        classifier = GoodNewsClassifier()
        result = await classifier.classify_batch_async([])
        assert result == []

    @pytest.mark.asyncio
    async def test_unready_returns_none_list(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        classifier = GoodNewsClassifier()
        classifier._ready = False
        items = [{"title": "a"}, {"title": "b"}]
        result = await classifier.classify_batch_async(items)
        assert result == [None, None]

    @pytest.mark.asyncio
    async def test_uses_call_response(self, monkeypatch: pytest.MonkeyPatch) -> None:
        classifier = GoodNewsClassifier()
        classifier._ready = True

        async def fake_call(payload: dict, *, max_retries: int = 3) -> dict:
            assert payload["model"] == "mistral-large-latest"
            return {
                "choices": [
                    {
                        "message": {
                            "content": '[{"good_news": true}, {"good_news": false}]'
                        }
                    }
                ]
            }

        monkeypatch.setattr(classifier, "_call", fake_call)
        result = await classifier.classify_batch_async(
            [
                {"title": "A", "source_name": "Le Monde"},
                {"title": "B", "source_name": "Le Monde"},
            ]
        )
        assert result == [True, False]

    @pytest.mark.asyncio
    async def test_call_failure_returns_none_list(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        classifier = GoodNewsClassifier()
        classifier._ready = True

        async def fake_call(payload: dict, *, max_retries: int = 3) -> None:
            return None

        monkeypatch.setattr(classifier, "_call", fake_call)
        result = await classifier.classify_batch_async(
            [{"title": "A"}, {"title": "B"}, {"title": "C"}]
        )
        assert result == [None, None, None]


class TestCallTokenCapture:
    @pytest.mark.asyncio
    async def test_call_records_token_usage(self) -> None:
        """`_call` propage les tokens de `usage` Mistral à api_usage_events (LR-1)."""
        classifier = GoodNewsClassifier()
        classifier._ready = True

        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": "[]"}}],
            "usage": {"prompt_tokens": 800, "completion_tokens": 16},
        }
        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        classifier._client = mock_client

        with patch(
            "app.services.observability.usage_recorder.record_api_call",
            new_callable=AsyncMock,
        ) as rec:
            data = await classifier._call({"model": "mistral-large-latest"})

        assert data is not None
        rec.assert_awaited_once()
        kwargs = rec.await_args.kwargs
        assert kwargs["prompt_tokens"] == 800
        assert kwargs["completion_tokens"] == 16
        assert kwargs["status"] == "ok"
