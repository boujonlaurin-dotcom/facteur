"""Production des candidats d'alerte source (stories 30.2 puis 30.3 v2).

Le gate de rareté a disparu en v2 : ce qui est testé ici est donc l'inverse de
la 30.2 — une source bavarde **produit** des candidats — plus le nouveau mode
filtré, où c'est le meilleur article qui part et non le plus récent.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_topic_profile import UserTopicProfile
from app.services.essentiel_service import EssentielUserContext
from app.services.source_alert_producer import (
    count_active_alerts,
    find_source_alert_candidates,
    source_alert_kind,
)

NOW = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)


def _source(name: str = "Source") -> Source:
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


def _content(
    source_id, *, hours_ago: float, title: str = "Article", theme: str = "society"
) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=NOW - timedelta(hours=hours_ago),
        content_type=ContentType.ARTICLE,
        theme=theme,
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


def _bell(user_id, source_id, *, filtered: bool | None = None) -> UserSource:
    return UserSource(
        user_id=user_id,
        source_id=source_id,
        state=InterestState.FOLLOWED,
        notify=True,
        notify_filtered=filtered,
    )


# ── kind composite ───────────────────────────────────────────────────


def test_source_alert_kind_fits_the_column_and_round_trips():
    source_id = uuid4()
    kind = source_alert_kind(source_id)
    assert len(kind) <= 32
    # Deux sources distinctes → deux kinds distincts (sinon collision sur
    # UniqueConstraint(device_id, target_date, kind)).
    assert kind != source_alert_kind(uuid4())


# ── plafond partagé ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_cap_counts_sources_and_topics_together(db_session):
    """5 cloches, toutes familles confondues — c'est un budget d'attention."""
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add(_bell(user_id, source.id))
    db_session.add(
        UserTopicProfile(
            user_id=user_id,
            topic_name="Ligue 1",
            slug_parent="sport",
            canonical_name="Ligue 1",
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    assert await count_active_alerts(db_session, user_id=user_id) == 2


# ── find_source_alert_candidates ─────────────────────────────────────


@pytest.mark.asyncio
async def test_returns_fresh_article_of_a_followed_source(db_session):
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
    db_session.add(_bell(user_id, source.id))
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert len(candidates) == 1
    assert candidates[0].content_title == "Le nouvel article"
    assert candidates[0].source_name == "Mensuel"
    assert candidates[0].articles_30d == 2


@pytest.mark.asyncio
async def test_noisy_source_is_no_longer_gated(db_session):
    """Régression 30.3 : la v1 filtrait cette source, la v2 la laisse sonner.

    Le bruit se règle par le mode filtré et le gouverneur, pas par un veto qui
    se lit comme une interdiction.
    """
    user_id = await _seed_user(db_session)
    source = _source("Quotidien bavard")
    db_session.add(source)
    await db_session.flush()
    db_session.add_all([_content(source.id, hours_ago=h) for h in range(1, 20)])
    db_session.add(_bell(user_id, source.id))
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert len(candidates) == 1


@pytest.mark.asyncio
async def test_ignores_articles_older_than_24h(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add(_content(source.id, hours_ago=30))
    db_session.add(_bell(user_id, source.id))
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
async def test_default_mode_keeps_the_most_recent_of_the_day(db_session):
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            _content(source.id, hours_ago=20, title="Le plus ancien du jour"),
            _content(source.id, hours_ago=1, title="Le plus récent"),
        ]
    )
    db_session.add(_bell(user_id, source.id))
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert len(candidates) == 1
    assert candidates[0].content_title == "Le plus récent"


@pytest.mark.asyncio
async def test_filtered_mode_keeps_the_best_scored_not_the_latest(db_session):
    """Mode filtré : le thème apprécié bat la fraîcheur.

    C'est tout l'intérêt du mode — sur une source bavarde, recevoir *le* bon
    article plutôt que le dernier tombé.
    """
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            _content(source.id, hours_ago=1, title="Dépêche fraîche"),
            _content(source.id, hours_ago=10, title="Thème apprécié", theme="sport"),
        ]
    )
    db_session.add(_bell(user_id, source.id, filtered=True))
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session,
        user_id=user_id,
        now=NOW,
        ctx=EssentielUserContext(topic_weights={"sport": 3.0}),
    )
    assert [c.content_title for c in candidates] == ["Thème apprécié"]


@pytest.mark.asyncio
async def test_filtered_mode_falls_back_to_freshness_without_signal(db_session):
    """Contexte vide → aucun article ne se distingue : le plus récent gagne."""
    user_id = await _seed_user(db_session)
    source = _source()
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            _content(source.id, hours_ago=10, title="Ancien"),
            _content(source.id, hours_ago=1, title="Récent"),
        ]
    )
    db_session.add(_bell(user_id, source.id, filtered=True))
    await db_session.commit()

    candidates = await find_source_alert_candidates(
        db_session, user_id=user_id, now=NOW
    )
    assert [c.content_title for c in candidates] == ["Récent"]
