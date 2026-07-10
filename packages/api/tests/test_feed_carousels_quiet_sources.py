"""Tests DB-driven du carrousel « Tes sources discrètes » (quiet_sources).

Source « rare » = source suivie, active, avec < 3 articles publiés sur les
30 derniers jours. Item = dernier article (≤ 60 j) non consommé de chaque
source rare. Carrousel émis seulement si ≥ 2 items.
"""

import datetime
from unittest.mock import patch
from uuid import uuid4

import pytest

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.services.recommendation_service import RecommendationService


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


async def _seed_quiet_source(
    db_session,
    name: str,
    user_id,
    article_days_ago: float = 5,
    state: InterestState = InterestState.FOLLOWED,
    is_active: bool = True,
) -> tuple[Source, Content]:
    """One followed source with a single recent article (quiet by definition)."""
    source = _make_source(name, is_active=is_active)
    db_session.add(source)
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=state,
            added_at=_now() - datetime.timedelta(days=90),
        )
    )
    content = _make_content(source, article_days_ago, title=f"{name} latest")
    db_session.add(content)
    await db_session.commit()
    return source, content


async def _build(db_session, session_maker, user_id):
    # session_maker = fake_session_maker → la sonde quiet_sources (short
    # session capée en prod) tourne sur la db_session de test (le pattern
    # savepoint n'est pas visible d'une vraie connexion pool).
    service = RecommendationService(db_session, session_maker=session_maker)
    service.entity_overflow = []
    service.keyword_overflow = []
    _, carousels = await service._build_carousels([], {}, user_id=user_id)
    return carousels


def _quiet(carousels):
    return [c for c in carousels if c["carousel_type"] == "quiet_sources"]


@pytest.mark.asyncio
async def test_quiet_sources_carousel_basic(db_session, fake_session_maker):
    user_id = uuid4()
    src_a, content_a = await _seed_quiet_source(db_session, "Rare A", user_id)
    src_b, content_b = await _seed_quiet_source(
        db_session, "Rare B", user_id, article_days_ago=10
    )

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    c = quiet[0]
    assert c["title"] == "Tes sources discrètes"
    # ≤ 5 sources : le shuffle déterministe ne change pas l'ENSEMBLE, juste
    # l'ordre (l'ancien "most recent first" n'est plus garanti).
    assert {i.id for i in c["items"]} == {content_a.id, content_b.id}
    assert len(c["badges"]) == 2
    assert all(b["code"] == "quiet_source" for b in c["badges"])
    # Badge label = source name de l'item correspondant (ordre seedé → on
    # vérifie la correspondance item↔badge plutôt qu'une position fixe).
    name_by_id = {content_a.id: "Rare A", content_b.id: "Rare B"}
    for item, badge in zip(c["items"], c["badges"], strict=True):
        assert badge["label"] == name_by_id[item.id]
    assert c["position"] >= 5


@pytest.mark.asyncio
async def test_quiet_sources_rotate_subset_by_seed(db_session, fake_session_maker):
    """> 5 sources discrètes : deux seeds différents sélectionnent des
    sous-ensembles différents (rotation au fil des refresh), même seed ⇒ même
    sous-ensemble (stabilité dans la fenêtre de cache)."""
    user_id = uuid4()
    # 7 sources discrètes valides → pool > MAX_CAROUSEL_ITEMS (5).
    all_ids = set()
    for i in range(7):
        _, content = await _seed_quiet_source(
            db_session, f"Rare {i}", user_id, article_days_ago=5 + i
        )
        all_ids.add(content.id)

    async def _subset(seed_value):
        with patch(
            "app.services.recommendation.randomization.compute_seed",
            return_value=seed_value,
        ):
            carousels = await _build(db_session, fake_session_maker, user_id)
        quiet = _quiet(carousels)
        assert len(quiet) == 1
        items = quiet[0]["items"]
        assert len(items) == 5  # coupe à MAX_CAROUSEL_ITEMS
        ids = {i.id for i in items}
        assert ids <= all_ids  # sous-ensemble du pool
        return frozenset(ids)

    # seed 0 et seed 4 donnent des top-5 différents (shuffle Gumbel déterministe)
    subset0 = await _subset(0)
    subset4 = await _subset(4)
    assert subset0 != subset4  # rotation selon le seed

    # Déterminisme : même seed ⇒ même sous-ensemble
    assert await _subset(0) == subset0


@pytest.mark.asyncio
async def test_high_volume_source_excluded(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_quiet_source(db_session, "Rare A", user_id)
    await _seed_quiet_source(db_session, "Rare B", user_id)

    # Busy source: 3 articles in the last 30 days → not quiet
    busy = _make_source("Busy")
    db_session.add(busy)
    db_session.add(
        UserSource(user_id=user_id, source_id=busy.id, state=InterestState.FOLLOWED)
    )
    for d in (1, 5, 12):
        db_session.add(_make_content(busy, d))
    await db_session.commit()

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    sources_in_carousel = {i.source_id for i in quiet[0]["items"]}
    assert busy.id not in sources_in_carousel


@pytest.mark.asyncio
async def test_consumed_article_excluded(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_quiet_source(db_session, "Rare A", user_id)
    await _seed_quiet_source(db_session, "Rare B", user_id)
    _, consumed_content = await _seed_quiet_source(db_session, "Rare C", user_id)
    db_session.add(
        UserContentStatus(
            user_id=user_id,
            content_id=consumed_content.id,
            status=ContentStatus.CONSUMED,
        )
    )
    await db_session.commit()

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    assert consumed_content.id not in {i.id for i in quiet[0]["items"]}


@pytest.mark.asyncio
async def test_all_consumed_no_carousel(db_session, fake_session_maker):
    user_id = uuid4()
    for name in ("Rare A", "Rare B"):
        _, content = await _seed_quiet_source(db_session, name, user_id)
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=content.id,
                status=ContentStatus.CONSUMED,
            )
        )
    await db_session.commit()

    carousels = await _build(db_session, fake_session_maker, user_id)
    assert _quiet(carousels) == []


@pytest.mark.asyncio
async def test_old_article_beyond_60_days_excluded(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_quiet_source(db_session, "Rare A", user_id)
    await _seed_quiet_source(db_session, "Rare B", user_id)
    src_old, content_old = await _seed_quiet_source(
        db_session, "Rare Old", user_id, article_days_ago=75
    )

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    assert content_old.id not in {i.id for i in quiet[0]["items"]}


@pytest.mark.asyncio
async def test_below_min_display_items_no_carousel(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_quiet_source(db_session, "Lonely Rare", user_id)

    carousels = await _build(db_session, fake_session_maker, user_id)
    assert _quiet(carousels) == []


@pytest.mark.asyncio
async def test_unfollowed_and_inactive_sources_excluded(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_quiet_source(db_session, "Rare A", user_id)
    await _seed_quiet_source(db_session, "Rare B", user_id)
    _, c_unfollowed = await _seed_quiet_source(
        db_session, "Unfollowed", user_id, state=InterestState.UNFOLLOWED
    )
    _, c_inactive = await _seed_quiet_source(
        db_session, "Inactive", user_id, is_active=False
    )

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    ids = {i.id for i in quiet[0]["items"]}
    assert c_unfollowed.id not in ids
    assert c_inactive.id not in ids


@pytest.mark.asyncio
async def test_one_item_per_source_latest_only(db_session, fake_session_maker):
    user_id = uuid4()
    src_a, latest_a = await _seed_quiet_source(db_session, "Rare A", user_id)
    older_a = _make_content(src_a, 20, title="Rare A older")
    db_session.add(older_a)
    await _seed_quiet_source(db_session, "Rare B", user_id)
    await db_session.commit()

    carousels = await _build(db_session, fake_session_maker, user_id)
    quiet = _quiet(carousels)
    assert len(quiet) == 1
    items_from_a = [i for i in quiet[0]["items"] if i.source_id == src_a.id]
    assert len(items_from_a) == 1
    assert items_from_a[0].id == latest_a.id


@pytest.mark.asyncio
async def test_promoted_items_removed_from_main_feed(db_session, fake_session_maker):
    user_id = uuid4()
    _, content_a = await _seed_quiet_source(db_session, "Rare A", user_id)
    await _seed_quiet_source(db_session, "Rare B", user_id)

    service = RecommendationService(db_session, session_maker=fake_session_maker)
    service.entity_overflow = []
    service.keyword_overflow = []
    result, carousels = await service._build_carousels([content_a], {}, user_id=user_id)
    assert len(_quiet(carousels)) == 1
    assert content_a.id not in {a.id for a in result}


@pytest.mark.asyncio
async def test_deep_carousel_not_emitted(db_session, fake_session_maker):
    """PO decision: the deep carousel is disabled (flag DEEP_CAROUSEL_ENABLED)."""
    from app.services import recommendation_service as rs

    assert rs.DEEP_CAROUSEL_ENABLED is False
    user_id = uuid4()
    carousels = await _build(db_session, fake_session_maker, user_id)
    assert not any(c["carousel_type"] == "deep" for c in carousels)


@pytest.mark.asyncio
async def test_saved_carousel_most_recently_saved_first(db_session, fake_session_maker):
    user_id = uuid4()
    source = _make_source("Saved Source")
    db_session.add(source)
    contents = [_make_content(source, d, title=f"Saved {d}") for d in (1, 2, 3)]
    for i, content in enumerate(contents):
        db_session.add(content)
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=content.id,
                status=ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(days=i),
            )
        )
    await db_session.commit()

    carousels = await _build(db_session, fake_session_maker, user_id)
    saved = [c for c in carousels if c["carousel_type"] == "saved"]
    assert len(saved) == 1
    # contents[0] saved most recently (saved_at = now) → first
    assert [i.id for i in saved[0]["items"]] == [c.id for c in contents]
