"""Tests de l'enrichissement carrousel de l'Essentiel (Story 32.1).

Vérifie au niveau fonction `_enrich_essentiel_carousel` :
- présence du carrousel du jour quand un type Phase B est éligible ;
- skip hors édition du jour (rewind J-7) ;
- fail-open : une exception dans la construction laisse la réponse intacte.
"""

import datetime
from unittest.mock import patch
from uuid import uuid4

import pytest

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source
from app.routers.essentiel import _enrich_essentiel_carousel
from app.schemas.essentiel import EssentielResponse
from app.utils.time import today_paris


def _now():
    return datetime.datetime.now(datetime.UTC)


def _make_source(name: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url="https://example.com",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )


def _make_content(source: Source, days_ago: float, title: str = "Article") -> Content:
    return Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=_now() - datetime.timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
    )


async def _seed_saved(db_session, user_id, n: int = 3):
    source = _make_source("EssSaves")
    db_session.add(source)
    arts = [_make_content(source, days_ago=1 + i) for i in range(n)]
    for a in arts:
        db_session.add(a)
    await db_session.flush()
    for i, a in enumerate(arts):
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=a.id,
                status=ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(minutes=i),
            )
        )
    await db_session.commit()
    return arts


def _empty_response() -> EssentielResponse:
    return EssentielResponse(
        target_date=today_paris(),
        generated_at=_now(),
        articles=[],
    )


@pytest.mark.asyncio
async def test_enrich_attaches_carousel_when_eligible(db_session):
    user_id = uuid4()
    await _seed_saved(db_session, user_id, n=3)
    response = _empty_response()

    with patch(
        "app.routers.essentiel.pick_essentiel_type",
        return_value="saved",
    ):
        out = await _enrich_essentiel_carousel(
            db_session, user_id, response, today_paris()
        )

    assert out.carousel is not None
    assert out.carousel.carousel_type == "saved"
    assert len(out.carousel.items) == 3
    assert out.carousel.badges  # badges alignés


@pytest.mark.asyncio
async def test_enrich_skips_when_not_today(db_session):
    """Édition passée (rewind) → aucun carrousel."""
    user_id = uuid4()
    await _seed_saved(db_session, user_id, n=3)
    response = _empty_response()
    yesterday = today_paris() - datetime.timedelta(days=1)

    out = await _enrich_essentiel_carousel(db_session, user_id, response, yesterday)
    assert out.carousel is None


@pytest.mark.asyncio
async def test_enrich_none_when_no_eligible_type(db_session):
    user_id = uuid4()
    # Aucune donnée Phase B → build_phase_b vide → pas de carrousel.
    response = _empty_response()
    out = await _enrich_essentiel_carousel(
        db_session, user_id, response, today_paris()
    )
    assert out.carousel is None


@pytest.mark.asyncio
async def test_enrich_fails_open_on_exception(db_session):
    """Une exception dans la construction ne remonte jamais et laisse la
    réponse inchangée (surface additive)."""
    user_id = uuid4()
    response = _empty_response()

    with patch(
        "app.routers.essentiel.build_phase_b",
        side_effect=RuntimeError("boom"),
    ):
        out = await _enrich_essentiel_carousel(
            db_session, user_id, response, today_paris()
        )

    assert out.carousel is None  # fail-open : pas de crash, pas de carrousel
