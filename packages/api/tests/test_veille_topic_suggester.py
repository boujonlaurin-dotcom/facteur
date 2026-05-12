"""Tests pour TopicSuggester (Story 18.1).

LLM mocké via `AsyncMock` sur `EditorialLLMClient.chat_json`.
Couvre : succès LLM, parsing strict, fallback déterministe, cache TTL.
"""

from unittest.mock import AsyncMock

from app.services.veille.topic_suggester import (
    TopicSuggester,
    _fallback_topics,
)


def _llm_response(topics: list[dict]) -> dict:
    return {"topics": topics}


class TestSuggestTopics:
    async def test_llm_success(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {
                        "topic_id": "evaluations",
                        "label": "Évaluations",
                        "reason": "Suit les réformes",
                    },
                    {
                        "topic_id": "neuroscience",
                        "label": "Neurosciences",
                        "reason": None,
                    },
                    {
                        "topic_id": "dys",
                        "label": "Dys (TDA/H)",
                        "reason": "Très demandé",
                    },
                    {
                        "topic_id": "numerique",
                        "label": "Numérique éducatif",
                        "reason": None,
                    },
                    {
                        "topic_id": "lecture",
                        "label": "Lecture",
                        "reason": None,
                    },
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=["t-eval"],
        )

        assert len(result) == 5
        assert result[0].topic_id == "evaluations"
        assert result[2].label == "Dys (TDA/H)"
        assert llm.chat_json.await_count == 1

    async def test_fallback_when_llm_not_ready(self):
        llm = AsyncMock()
        llm.is_ready = False
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=[],
        )

        assert result == _fallback_topics("Éducation")
        # No LLM call.
        assert llm.chat_json.await_count == 0

    async def test_fallback_on_llm_returning_none(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value=None)
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=[],
        )

        assert result == _fallback_topics("Éducation")

    async def test_fallback_on_invalid_payload(self):
        llm = AsyncMock()
        llm.is_ready = True
        # Pas de clé "topics".
        llm.chat_json = AsyncMock(return_value={"oops": []})
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=[],
        )

        assert result == _fallback_topics("Éducation")

    async def test_fallback_on_wrong_count(self):
        llm = AsyncMock()
        llm.is_ready = True
        # 3 topics au lieu de 5 → fallback.
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": "a", "label": "A", "reason": None},
                    {"topic_id": "b", "label": "B", "reason": None},
                    {"topic_id": "c", "label": "C", "reason": None},
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=[],
        )

        assert result == _fallback_topics("Éducation")

    async def test_fallback_on_validation_error(self):
        llm = AsyncMock()
        llm.is_ready = True
        # topic_id vide invalide selon le schéma Pydantic (min_length=1).
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": "", "label": "X", "reason": None},
                    {"topic_id": "a", "label": "A", "reason": None},
                    {"topic_id": "b", "label": "B", "reason": None},
                    {"topic_id": "c", "label": "C", "reason": None},
                    {"topic_id": "d", "label": "D", "reason": None},
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        result = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=[],
        )

        assert result == _fallback_topics("Éducation")


class TestPurposeAndBriefInjection:
    async def test_purpose_and_brief_appear_in_user_message(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": f"t{i}", "label": f"T{i}", "reason": None}
                    for i in range(5)
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        await suggester.suggest_topics(
            theme_id="tech",
            theme_label="Tech",
            selected_topic_ids=[],
            purpose="preparer_projet",
            editorial_brief="Plutôt analyses long format",
        )

        assert llm.chat_json.await_count == 1
        user_msg = llm.chat_json.call_args.kwargs["user_message"]
        # Label fr humain (pas le slug brut).
        assert "Préparer un projet / une décision" in user_msg
        assert "Brief éditorial : Plutôt analyses long format" in user_msg

    async def test_purpose_other_appears_in_user_message(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": f"t{i}", "label": f"T{i}", "reason": None}
                    for i in range(5)
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        await suggester.suggest_topics(
            theme_id="tech",
            theme_label="Tech",
            selected_topic_ids=[],
            purpose="autre",
            purpose_other="préparer un livre",
            editorial_brief=None,
        )

        user_msg = llm.chat_json.call_args.kwargs["user_message"]
        assert "Autre (préparer un livre)" in user_msg
        assert "Brief éditorial : (aucun)" in user_msg

    async def test_no_purpose_renders_non_precise(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": f"t{i}", "label": f"T{i}", "reason": None}
                    for i in range(5)
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        await suggester.suggest_topics(
            theme_id="tech",
            theme_label="Tech",
            selected_topic_ids=[],
        )

        user_msg = llm.chat_json.call_args.kwargs["user_message"]
        assert "Usage souhaité : (non précisé)" in user_msg

    async def test_different_purpose_misses_cache(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": f"t{i}", "label": f"T{i}", "reason": None}
                    for i in range(5)
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        await suggester.suggest_topics("tech", "Tech", [], purpose="preparer_projet")
        await suggester.suggest_topics("tech", "Tech", [], purpose="culture_generale")
        # Cache key différente → 2 appels LLM.
        assert llm.chat_json.await_count == 2


class TestCacheTTL:
    async def test_cache_hits_skip_llm(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": "x", "label": "X", "reason": None},
                    {"topic_id": "y", "label": "Y", "reason": None},
                    {"topic_id": "z", "label": "Z", "reason": None},
                    {"topic_id": "u", "label": "U", "reason": None},
                    {"topic_id": "v", "label": "V", "reason": None},
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        first = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=["a", "b"],
        )
        second = await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=["b", "a"],  # ordre différent → même clé (sorted)
        )
        assert first == second
        assert llm.chat_json.await_count == 1  # cache hit le 2e

    async def test_different_excluded_misses_cache(self):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": "x", "label": "X", "reason": None},
                    {"topic_id": "y", "label": "Y", "reason": None},
                    {"topic_id": "z", "label": "Z", "reason": None},
                    {"topic_id": "u", "label": "U", "reason": None},
                    {"topic_id": "v", "label": "V", "reason": None},
                ]
            )
        )
        suggester = TopicSuggester(llm=llm)

        await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=["a"],
            excluded_topic_ids=[],
        )
        await suggester.suggest_topics(
            theme_id="education",
            theme_label="Éducation",
            selected_topic_ids=["a"],
            excluded_topic_ids=["banned"],
        )
        assert llm.chat_json.await_count == 2  # clés différentes

    async def test_cache_size_limit(self):
        """Le cache LRU évince les entrées quand on dépasse maxsize."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value=_llm_response(
                [
                    {"topic_id": "x", "label": "X", "reason": None},
                    {"topic_id": "y", "label": "Y", "reason": None},
                    {"topic_id": "z", "label": "Z", "reason": None},
                    {"topic_id": "u", "label": "U", "reason": None},
                    {"topic_id": "v", "label": "V", "reason": None},
                ]
            )
        )
        suggester = TopicSuggester(llm=llm, cache_size=2, cache_ttl=600)

        # 3 thèmes différents → le 1er est évincé.
        await suggester.suggest_topics("t1", "T1", [])
        await suggester.suggest_topics("t2", "T2", [])
        await suggester.suggest_topics("t3", "T3", [])
        # Le t1 est évincé : nouvel appel LLM attendu.
        await suggester.suggest_topics("t1", "T1", [])
        assert llm.chat_json.await_count == 4
