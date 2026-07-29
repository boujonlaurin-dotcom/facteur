"""Production des candidats d'alerte sujet (story 30.3 « alertes v2 »)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.user_topic_profile import UserTopicProfile
from app.services.essentiel_service import EssentielUserContext
from app.services.topic_alert_producer import (
    build_topic_predicate,
    find_topic_alert_candidates,
    topic_alert_kind,
    topic_frequency_stats,
)

NOW = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)


async def _seed_source(db_session) -> Source:
    source = Source(
        id=uuid4(),
        name="Source",
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    return source


async def _seed_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id, display_name="Topic User", onboarding_completed=True
        )
    )
    await db_session.flush()
    return user_id


def _topic(
    user_id,
    *,
    name: str = "Ligue 1",
    canonical: str | None = "Ligue 1",
    keywords: list[str] | None = None,
    notify: bool | None = True,
    filtered: bool | None = None,
) -> UserTopicProfile:
    return UserTopicProfile(
        user_id=user_id,
        topic_name=name,
        slug_parent="sport",
        canonical_name=canonical,
        keywords=keywords or [],
        state=InterestState.FOLLOWED,
        notify=notify,
        notify_filtered=filtered,
    )


def _content(
    source_id,
    *,
    hours_ago: float,
    title: str = "Article",
    description: str | None = None,
    entities: list[str] | None = None,
    theme: str = "society",
) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        description=description,
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=NOW - timedelta(hours=hours_ago),
        content_type=ContentType.ARTICLE,
        theme=theme,
        entities=entities,
    )


# ── prédicat ─────────────────────────────────────────────────────────


def test_predicate_is_none_without_entity_or_keyword():
    """Un sujet indécidable ne matche rien plutôt que tout.

    Sans ce garde-fou, une cloche sur un profil non enrichi sonnerait sur
    l'intégralité du flux.
    """
    profile = _topic(uuid4(), canonical=None, keywords=[])
    assert build_topic_predicate(profile) is None


def test_topic_alert_kind_fits_the_column_and_round_trips():
    kind = topic_alert_kind(uuid4())
    assert len(kind) <= 32
    assert kind != topic_alert_kind(uuid4())


# ── matching ─────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_matches_on_canonical_entity(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    db_session.add_all(
        [
            _content(
                source.id,
                hours_ago=2,
                title="Un match hier soir",
                entities=['{"name": "Ligue 1", "type": "EVENT"}'],
            ),
            _content(source.id, hours_ago=2, title="Rien à voir"),
        ]
    )
    db_session.add(_topic(user_id))
    await db_session.commit()

    candidates = await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW)
    assert [c.content_title for c in candidates] == ["Un match hier soir"]
    assert candidates[0].topic_name == "Ligue 1"


@pytest.mark.asyncio
async def test_matches_keywords_on_word_boundaries_only(db_session):
    """« nets » ne doit pas survivre dans « internets » — mot entier, pas sous-chaîne."""
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    db_session.add_all(
        [
            _content(source.id, hours_ago=1, title="Les internets sont en feu"),
            _content(source.id, hours_ago=3, title="Des nets tendus"),
        ]
    )
    db_session.add(_topic(user_id, canonical=None, keywords=["nets"]))
    await db_session.commit()

    candidates = await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW)
    assert [c.content_title for c in candidates] == ["Des nets tendus"]


@pytest.mark.asyncio
async def test_parent_theme_alone_never_matches(db_session):
    """Le thème parent n'est pas un axe : « sport » ne doit pas tout ramener.

    Sinon la cloche devient un robinet — c'est le raisonnement `_matched_axes`
    du filtre de veille, rejoué ici.
    """
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    db_session.add(
        _content(source.id, hours_ago=1, title="Un match de foot", theme="sport")
    )
    db_session.add(_topic(user_id, canonical="Ligue 1", keywords=[]))
    await db_session.commit()

    assert await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW) == []


@pytest.mark.asyncio
async def test_ignores_topic_without_bell(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    db_session.add(
        _content(
            source.id,
            hours_ago=1,
            title="Match",
            entities=['{"name": "Ligue 1", "type": "EVENT"}'],
        )
    )
    # `notify` NULL (legacy) = pas de cloche.
    db_session.add(_topic(user_id, notify=None))
    await db_session.commit()

    assert await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW) == []


@pytest.mark.asyncio
async def test_ignores_matches_older_than_24h(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    db_session.add(
        _content(
            source.id,
            hours_ago=30,
            title="Match",
            entities=['{"name": "Ligue 1", "type": "EVENT"}'],
        )
    )
    db_session.add(_topic(user_id))
    await db_session.commit()

    assert await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW) == []


# ── régimes ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_default_mode_keeps_the_most_recent_match(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    entities = ['{"name": "Ligue 1", "type": "EVENT"}']
    db_session.add_all(
        [
            _content(source.id, hours_ago=10, title="Ancien", entities=entities),
            _content(source.id, hours_ago=1, title="Récent", entities=entities),
        ]
    )
    db_session.add(_topic(user_id))
    await db_session.commit()

    candidates = await find_topic_alert_candidates(db_session, user_id=user_id, now=NOW)
    assert [c.content_title for c in candidates] == ["Récent"]


@pytest.mark.asyncio
async def test_filtered_mode_keeps_the_best_scored_match(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    entities = ['{"name": "Ligue 1", "type": "EVENT"}']
    db_session.add_all(
        [
            _content(source.id, hours_ago=1, title="Brève", entities=entities),
            _content(
                source.id,
                hours_ago=10,
                title="Thème apprécié",
                entities=entities,
                theme="sport",
            ),
        ]
    )
    db_session.add(_topic(user_id, filtered=True))
    await db_session.commit()

    candidates = await find_topic_alert_candidates(
        db_session,
        user_id=user_id,
        now=NOW,
        ctx=EssentielUserContext(topic_weights={"sport": 3.0}),
    )
    assert [c.content_title for c in candidates] == ["Thème apprécié"]


# ── cadence ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_frequency_stats_count_only_matching_articles(db_session):
    user_id = await _seed_user(db_session)
    source = await _seed_source(db_session)
    entities = ['{"name": "Ligue 1", "type": "EVENT"}']
    db_session.add_all(
        [
            _content(source.id, hours_ago=h * 24, title=f"Match {h}", entities=entities)
            for h in range(1, 5)
        ]
        + [_content(source.id, hours_ago=2, title="Hors sujet")]
    )
    profile = _topic(user_id)
    db_session.add(profile)
    await db_session.commit()

    articles_30d, oldest = await topic_frequency_stats(
        db_session, profile=profile, now=NOW
    )
    assert articles_30d == 4
    assert oldest == NOW - timedelta(hours=4 * 24)


@pytest.mark.asyncio
async def test_frequency_stats_of_an_undecidable_topic_are_empty(db_session):
    user_id = await _seed_user(db_session)
    profile = _topic(user_id, canonical=None, keywords=[])
    db_session.add(profile)
    await db_session.commit()

    assert await topic_frequency_stats(db_session, profile=profile, now=NOW) == (
        0,
        None,
    )
