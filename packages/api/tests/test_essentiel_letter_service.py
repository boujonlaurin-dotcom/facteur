"""Tests de `generate_letter` (chat_json mocké) — Story 9.6."""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.schemas.content import SourceMini
from app.schemas.essentiel import EssentielArticle
from app.schemas.essentiel_letter import LetterSegmentType
from app.services.essentiel_letter_service import (
    build_letter_plan,
    generate_letter,
)


def _article(rank: int, theme: str | None, source_name: str = "Le Monde"):
    return EssentielArticle(
        content_id=uuid4(),
        title=f"Titre {rank}",
        url=f"https://example.org/{rank}",
        description=f"Description {rank}",
        published_at=datetime.now(UTC),
        source=SourceMini(
            id=uuid4(), name=source_name, logo_url=None, type="rss", theme=theme
        ),
        source_letter=source_name[0],
        section_label=f"Sujet {rank}",
        rank=rank,
        theme=theme,
    )


_CHAPO_PAD = (
    "L'actualite du jour s'organise autour de plusieurs dossiers suivis de "
    "pres, dont la portee doit se preciser dans les prochaines heures pour "
    "l'ensemble du pays"
)
_RUBRIQUE_PAD = (
    "Le dossier connait une nouvelle etape decisive qui sera suivie de pres "
    "dans les prochains jours"
)


def _valid_output_for(articles):
    """Construit une sortie LLM valide pour le plan déterministe des picks."""
    plan = build_letter_plan(articles)
    chapo_markers = " ".join(f"[[{rank}]]" for rank in plan.chapo_ranks)
    rubriques = []
    for theme, ranks in plan.rubriques:
        markers = " ".join(f"[[{rank}]]" for rank in ranks)
        rubriques.append({"theme": theme, "text": f"{_RUBRIQUE_PAD} {markers}."})
    return {"chapo": f"{_CHAPO_PAD} {chapo_markers}.", "rubriques": rubriques}


class _FakeLLM:
    def __init__(self, responses):
        self.chat_json = AsyncMock(side_effect=responses)
        self.close = AsyncMock()


@pytest.fixture
def articles():
    return [
        _article(1, "politique"),
        _article(2, "environnement", "franceinfo"),
        _article(3, "economie", "Les Échos"),
        _article(4, "economie", "La Tribune"),
        _article(5, "tech", "Numerama"),
    ]


async def test_generate_letter_nominal(articles):
    llm = _FakeLLM([_valid_output_for(articles)])
    letter = await generate_letter(articles, client=llm)

    assert letter is not None
    assert llm.chat_json.await_count == 1
    # Chaque pick référencé exactement une fois, tous blocs confondus.
    refs = [
        seg.content_id
        for seg in letter.chapo + [s for r in letter.rubriques for s in r.segments]
        if seg.type == LetterSegmentType.SOURCE_REF
    ]
    assert sorted(refs) == sorted(a.content_id for a in articles)
    assert letter.model == "mistral-small-latest"
    # call_site propagé pour api_usage_events.
    assert llm.chat_json.await_args.kwargs["call_site"] == "essentiel_letter"


async def test_generate_letter_retry_with_corrections(articles):
    bad = _valid_output_for(articles)
    bad = {**bad, "chapo": bad["chapo"].replace("[[1]]", "")}
    llm = _FakeLLM([bad, _valid_output_for(articles)])

    letter = await generate_letter(articles, client=llm)

    assert letter is not None
    assert llm.chat_json.await_count == 2
    retry_message = llm.chat_json.await_args_list[1].kwargs["user_message"]
    assert "CORRECTIONS OBLIGATOIRES" in retry_message


async def test_generate_letter_fails_after_retry(articles):
    bad = _valid_output_for(articles)
    bad = {**bad, "chapo": "Trop court [[1]] [[2]]."}
    llm = _FakeLLM([bad, bad])

    letter = await generate_letter(articles, client=llm)

    assert letter is None
    assert llm.chat_json.await_count == 2


async def test_generate_letter_llm_error_no_retry(articles):
    llm = _FakeLLM([None])
    letter = await generate_letter(articles, client=llm)
    assert letter is None
    assert llm.chat_json.await_count == 1


async def test_generate_letter_empty_articles():
    llm = _FakeLLM([])
    assert await generate_letter([], client=llm) is None
    assert llm.chat_json.await_count == 0


async def test_generate_letter_three_picks_single_rubrique_theme():
    articles = [
        _article(1, "politique"),
        _article(2, "international", "RFI"),
        _article(3, "international", "France 24"),
    ]
    llm = _FakeLLM([_valid_output_for(articles)])
    letter = await generate_letter(articles, client=llm)
    assert letter is not None
    assert [r.theme for r in letter.rubriques] == ["international"]
    assert len([s for s in letter.rubriques[0].segments if s.content_id]) == 2


async def test_generate_letter_serein_tone_in_system(articles):
    llm = _FakeLLM([_valid_output_for(articles)])
    await generate_letter(articles, is_serene=True, client=llm)
    system = llm.chat_json.await_args.kwargs["system"]
    assert "SEREINE" in system


async def test_generate_letter_footer_themes(articles):
    llm = _FakeLLM([_valid_output_for(articles)])
    letter = await generate_letter(
        articles, followed_themes=["culture", "politique"], client=llm
    )
    # « politique » est couvert par un pick → seul « culture » reste au pied.
    assert letter.footer_themes == ["culture"]
