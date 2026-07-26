"""Éligibilité « source rare » + production des candidats (story 30.2)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.services.source_alert_producer import (
    find_source_alert_candidates,
    is_rare_source,
    rarity_phrase,
    source_alert_kind,
)

NOW = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)


def _source(name: str = "Source rare") -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )


def _content(source_id, *, hours_ago: float, title: str = "Article") -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=NOW - timedelta(hours=hours_ago),
        content_type=ContentType.ARTICLE,
        theme="society",
    )


async def _seed_user(db_session) -> object:
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Alert User",
            onboarding_completed=True,
        )
    )
    await db_session.flush()
    return user_id


# ── is_rare_source ───────────────────────────────────────────────────


def test_monthly_source_is_rare():
    # 1 article sur 30 jours d'historique → ~0,23/semaine.
    assert is_rare_source(1, NOW - timedelta(days=30), NOW) is True


def test_weekly_source_is_not_rare():
    # 5 articles sur 30 jours → ~1,17/semaine, au-dessus du seuil.
    assert is_rare_source(5, NOW - timedelta(days=30), NOW) is False


def test_daily_source_is_not_rare():
    assert is_rare_source(30, NOW - timedelta(days=30), NOW) is False


def test_fresh_source_is_not_underestimated_by_the_clamp():
    """3 articles en 2 jours = quotidien, pas « rare ».

    Sans le clamp sur l'âge réel, la fenêtre de 30 j diluerait le volume à
    0,1/jour et la source passerait pour rare — la cloche sonnerait tous les
    jours.
    """
    assert is_rare_source(3, NOW - timedelta(days=2), NOW) is False


def test_source_without_history_uses_the_full_window():
    assert is_rare_source(1, None, NOW) is True
    assert is_rare_source(20, None, NOW) is False


def test_silent_source_is_not_eligible():
    """0 article = aucune preuve qu'elle publie : promesse vide."""
    assert is_rare_source(0, NOW - timedelta(days=90), NOW) is False
    assert is_rare_source(0, None, NOW) is False


def test_rarity_phrase_matches_the_eligibility_thresholds():
    assert rarity_phrase(1, NOW - timedelta(days=30), NOW) == (
        "Ça n'arrive qu'une fois par mois."
    )
    # 3 articles / 30 j = 0,7 / semaine → « toutes les deux semaines ».
    assert rarity_phrase(3, NOW - timedelta(days=30), NOW) == (
        "Ça n'arrive qu'une fois toutes les deux semaines."
    )


# ── kind composite ───────────────────────────────────────────────────


def test_source_alert_kind_fits_the_column_and_round_trips():
    source_id = uuid4()
    kind = source_alert_kind(source_id)
    assert len(kind) <= 32
    # Deux sources distinctes → deux kinds distincts (sinon collision sur
    # UniqueConstraint(device_id, target_date, kind)).
    assert kind != source_alert_kind(uuid4())


# ── find_source_alert_candidates ─────────────────────────────────────


@pytest.mark.asyncio
async def test_returns_fresh_article_of_a_rare_followed_source(db_session):
    user_id = await _seed_user(db_session)
    source = _source("Mensuel")
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            _content(source.id, hours_ago=2, title="Le nouvel article"),
            _content(source.id, hours_ago=24 * 29),
        ]
    )
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert len(candidates) == 1
    assert candidates[0].content_title == "Le nouvel article"
    assert candidates[0].source_name == "Mensuel"
    assert candidates[0].articles_30d == 2


@pytest.mark.asyncio
async def test_ignores_articles_older_than_24h(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add(_content(source.id, hours_ago=30))
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    assert (
        await find_source_alert_candidates(db_session, user_id=user_id, now=NOW) == []
    )


@pytest.mark.asyncio
async def test_ignores_source_without_bell(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add(_content(source.id, hours_ago=2))
    # `notify` laissé à NULL (legacy) : lu comme « pas de cloche ».
    db_session.add(
        UserSource(user_id=user_id, source_id=source.id, state=InterestState.FOLLOWED)
    )
    await db_session.commit()

    assert (
        await find_source_alert_candidates(db_session, user_id=user_id, now=NOW) == []
    )


@pytest.mark.asyncio
async def test_ignores_unfollowed_source(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add(_content(source.id, hours_ago=2))
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.UNFOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    assert (
        await find_source_alert_candidates(db_session, user_id=user_id, now=NOW) == []
    )


@pytest.mark.asyncio
async def test_rarity_is_replayed_at_dispatch(db_session):
    """Cloche posée quand la source était calme, source devenue bavarde."""
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add_all([_content(source.id, hours_ago=h) for h in range(1, 40)])
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    assert (
        await find_source_alert_candidates(db_session, user_id=user_id, now=NOW) == []
    )


@pytest.mark.asyncio
async def test_one_candidate_per_source_keeps_the_most_recent(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            # Historique de 30 j : sans lui, le clamp ramènerait la fenêtre à
            # 1 jour et 2 articles suffiraient à disqualifier la source.
            _content(source.id, hours_ago=24 * 30, title="Archive"),
            _content(source.id, hours_ago=20, title="Le plus ancien du jour"),
            _content(source.id, hours_ago=1, title="Le plus récent"),
        ]
    )
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert len(candidates) == 1
    assert candidates[0].content_title == "Le plus récent"
