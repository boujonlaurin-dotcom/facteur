"""Tests DB-driven du catalogue Phase B partagé (Story 32.1).

Couvre les builds extraits de `_build_carousels` vers `carousel_catalog` :
`build_new_source`, `build_saved`, `build_community` (unifié via
`get_top_recommendations`) et l'agrégateur `build_phase_b`. Le carrousel
`quiet_sources` a sa propre suite (`test_feed_carousels_quiet_sources.py`).

Ces tests tournent sur une vraie base de test (pas de mocks d'ordre d'appel) :
c'est la construction réelle des requêtes qui est vérifiée, robuste au
réordonnancement interne.
"""

import datetime
from unittest.mock import patch
from uuid import uuid4

import pytest

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.services.recommendation.carousel_catalog import (
    CarouselBuildContext,
    build_community,
    build_new_source,
    build_saved,
)
from app.services.recommendation.carousel_selection_service import build_phase_b


def _now():
    return datetime.datetime.now(datetime.UTC)


def _make_source(name: str, is_active: bool = True) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url="https://example.com",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=is_active,
        is_curated=False,
    )


def _make_content(
    source: Source,
    days_ago: float,
    title: str = "Article",
    content_type: ContentType = ContentType.ARTICLE,
) -> Content:
    return Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=_now() - datetime.timedelta(days=days_ago),
        content_type=content_type,
        guid=str(uuid4()),
    )


def _ctx(db_session, session_maker, user_id, consumed_ids=None) -> CarouselBuildContext:
    return CarouselBuildContext(
        session=db_session,
        session_maker=session_maker,
        user_id=user_id,
        consumed_ids=consumed_ids or set(),
    )


async def _add_new_source(
    db_session, user_id, name: str, *, added_days_ago: float, article_count: int
) -> Source:
    """Une source suivie ajoutée récemment + N articles frais (≤ 7 j)."""
    source = _make_source(name)
    db_session.add(source)
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            added_at=_now() - datetime.timedelta(days=added_days_ago),
        )
    )
    for i in range(article_count):
        db_session.add(_make_content(source, days_ago=1 + i, title=f"{name} art {i}"))
    await db_session.commit()
    return source


# --------------------------------------------------------------------------
# build_new_source
# --------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_build_new_source_basic(db_session, fake_session_maker):
    user_id = uuid4()
    await _add_new_source(
        db_session, user_id, "TechCrunch", added_days_ago=2, article_count=3
    )

    content = await build_new_source(_ctx(db_session, fake_session_maker, user_id))
    assert content is not None
    assert content.carousel_type == "new_source"
    assert "TechCrunch" in content.title
    assert len(content.items) == 3
    assert all(b["code"] == "new_source" for b in content.badges)
    assert len(content.badges) == len(content.items)


@pytest.mark.asyncio
async def test_build_new_source_skipped_within_cooldown(db_session, fake_session_maker):
    """Source ajoutée il y a < 6 h → cooldown post-add → pas de carrousel."""
    user_id = uuid4()
    # 2 h en jours = ~0.083.
    await _add_new_source(
        db_session, user_id, "FreshSrc", added_days_ago=2 / 24, article_count=3
    )

    content = await build_new_source(_ctx(db_session, fake_session_maker, user_id))
    assert content is None


@pytest.mark.asyncio
async def test_build_new_source_skipped_too_few_articles(
    db_session, fake_session_maker
):
    user_id = uuid4()
    await _add_new_source(
        db_session, user_id, "Sparse", added_days_ago=2, article_count=1
    )

    content = await build_new_source(_ctx(db_session, fake_session_maker, user_id))
    assert content is None


@pytest.mark.asyncio
async def test_build_new_source_rotates_by_seed(db_session, fake_session_maker):
    """≥ 3 sources récentes éligibles : la source mise en avant dépend du seed."""
    user_id = uuid4()
    for name in ("Alpha", "Bravo", "Charlie"):
        await _add_new_source(
            db_session, user_id, name, added_days_ago=2, article_count=3
        )

    async def _title(seed_value):
        with patch(
            "app.services.recommendation.randomization.compute_seed",
            return_value=seed_value,
        ):
            content = await build_new_source(
                _ctx(db_session, fake_session_maker, user_id)
            )
        assert content is not None
        return content.title

    title0 = await _title(0)
    title4 = await _title(4)
    assert title0 != title4  # rotation selon le seed
    assert await _title(0) == title0  # déterminisme intra-seed


@pytest.mark.asyncio
async def test_build_new_source_excludes_consumed(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("Consumable")
    db_session.add(source)
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            added_at=_now() - datetime.timedelta(days=2),
        )
    )
    arts = [_make_content(source, days_ago=1 + i, title=f"art {i}") for i in range(3)]
    for a in arts:
        db_session.add(a)
    await db_session.commit()

    # Consomme 2 des 3 → sous le seuil MIN_NEW_SOURCE_ITEMS (2).
    consumed = {arts[0].id, arts[1].id}
    content = await build_new_source(
        _ctx(db_session, fake_session_maker, user_id, consumed_ids=consumed)
    )
    assert content is None


# --------------------------------------------------------------------------
# build_saved
# --------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_build_saved_mixed_content_badges(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("Saves")
    db_session.add(source)
    # Ordre saved_at décroissant contrôlé : article (récent) > vidéo > podcast.
    art = _make_content(source, days_ago=1, title="A", content_type=ContentType.ARTICLE)
    vid = _make_content(source, days_ago=2, title="V", content_type=ContentType.YOUTUBE)
    pod = _make_content(source, days_ago=3, title="P", content_type=ContentType.PODCAST)
    for c in (art, vid, pod):
        db_session.add(c)
    await db_session.flush()
    for c, mins in ((art, 1), (vid, 2), (pod, 3)):
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=c.id,
                status=ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(minutes=mins),
            )
        )
    await db_session.commit()

    content = await build_saved(_ctx(db_session, fake_session_maker, user_id))
    assert content is not None
    assert content.carousel_type == "saved"
    assert len(content.items) == 3
    codes = [b["code"] for b in content.badges]
    assert codes == ["saved_article", "saved_video", "saved_audio"]


@pytest.mark.asyncio
async def test_build_saved_skipped_too_few(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("OneSave")
    db_session.add(source)
    c = _make_content(source, days_ago=1)
    db_session.add(c)
    await db_session.flush()
    db_session.add(
        UserContentStatus(
            user_id=user_id,
            content_id=c.id,
            status=ContentStatus.UNSEEN,
            is_saved=True,
            saved_at=_now(),
        )
    )
    await db_session.commit()

    content = await build_saved(_ctx(db_session, fake_session_maker, user_id))
    assert content is None  # < MIN_CAROUSEL_ITEMS (3)


@pytest.mark.asyncio
async def test_build_saved_excludes_consumed_status(db_session, fake_session_maker):
    """Un article sauvegardé mais CONSUMED ne compte pas."""
    user_id = uuid4()
    source = _make_source("MixedSaves")
    db_session.add(source)
    arts = [_make_content(source, days_ago=1 + i) for i in range(3)]
    for a in arts:
        db_session.add(a)
    await db_session.flush()
    for i, a in enumerate(arts):
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=a.id,
                # Le 3e est consommé → 2 restants < seuil.
                status=ContentStatus.CONSUMED if i == 2 else ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(minutes=i),
            )
        )
    await db_session.commit()

    content = await build_saved(_ctx(db_session, fake_session_maker, user_id))
    assert content is None


# --------------------------------------------------------------------------
# build_community (unifié via get_top_recommendations)
# --------------------------------------------------------------------------


async def _like(db_session, content_id, *, n: int, hours_ago: float = 1.0):
    """N tournesols communautaires (utilisateurs distincts) sur un article."""
    for _ in range(n):
        db_session.add(
            UserContentStatus(
                user_id=uuid4(),
                content_id=content_id,
                status=ContentStatus.UNSEEN,
                is_liked=True,
                liked_at=_now() - datetime.timedelta(hours=hours_ago),
            )
        )


@pytest.mark.asyncio
async def test_build_community_basic_unified(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("Community")
    db_session.add(source)
    arts = [_make_content(source, days_ago=1 + i, title=f"C{i}") for i in range(3)]
    for a in arts:
        db_session.add(a)
    await db_session.flush()
    # arts[0] : 3 tournesols → badge "🌻 3" ; arts[1..2] : 1 → "Reco communauté".
    await _like(db_session, arts[0].id, n=3, hours_ago=1)
    await _like(db_session, arts[1].id, n=1, hours_ago=2)
    await _like(db_session, arts[2].id, n=1, hours_ago=3)
    await db_session.commit()

    content = await build_community(_ctx(db_session, fake_session_maker, user_id))
    assert content is not None
    assert content.carousel_type == "community"
    assert content.title == "Recos de la communauté"
    assert len(content.items) == 3
    assert all(b["code"] == "community" for b in content.badges)
    # Le plus tournesolé (arts[0]) porte le compteur "🌻 3".
    top_badge = content.badges[0]
    assert "3" in top_badge["label"]


@pytest.mark.asyncio
async def test_build_community_skipped_too_few(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("SmallCommunity")
    db_session.add(source)
    arts = [_make_content(source, days_ago=1 + i) for i in range(2)]
    for a in arts:
        db_session.add(a)
    await db_session.flush()
    await _like(db_session, arts[0].id, n=1)
    await _like(db_session, arts[1].id, n=1)
    await db_session.commit()

    content = await build_community(_ctx(db_session, fake_session_maker, user_id))
    assert content is None  # < MIN_CAROUSEL_ITEMS (3)


@pytest.mark.asyncio
async def test_build_community_excludes_consumed(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("ConsumedCommunity")
    db_session.add(source)
    arts = [_make_content(source, days_ago=1 + i) for i in range(3)]
    for a in arts:
        db_session.add(a)
    await db_session.flush()
    for a in arts:
        await _like(db_session, a.id, n=2)
    await db_session.commit()

    # Exclut 1 des 3 → 2 restants < seuil.
    content = await build_community(
        _ctx(db_session, fake_session_maker, user_id, consumed_ids={arts[0].id})
    )
    assert content is None


# --------------------------------------------------------------------------
# build_phase_b (agrégateur)
# --------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_build_phase_b_returns_eligible_types(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("Both")
    db_session.add(source)
    saved_arts = [_make_content(source, days_ago=1 + i) for i in range(3)]
    comm_arts = [_make_content(source, days_ago=1 + i, title=f"cm{i}") for i in range(3)]
    for a in saved_arts + comm_arts:
        db_session.add(a)
    await db_session.flush()
    for i, a in enumerate(saved_arts):
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=a.id,
                status=ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(minutes=i),
            )
        )
    for a in comm_arts:
        await _like(db_session, a.id, n=2)
    await db_session.commit()

    contents = await build_phase_b(_ctx(db_session, fake_session_maker, user_id))
    assert set(contents.keys()) == {"saved", "community"}
    assert len(contents["saved"].items) == 3
    assert len(contents["community"].items) == 3


@pytest.mark.asyncio
async def test_build_phase_b_empty_when_no_data(db_session, fake_session_maker):
    user_id = uuid4()
    contents = await build_phase_b(_ctx(db_session, fake_session_maker, user_id))
    assert contents == {}
