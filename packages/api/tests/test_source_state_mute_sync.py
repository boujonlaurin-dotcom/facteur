"""Sync `personalization.muted_sources` ↔ état HIDDEN d'une source.

Le feed n'exclut une source que via `personalization.muted_sources` (cf.
`recommendation_service` + `pillars/penalties`), JAMAIS via `UserSource.state`.
Le palier « Masqué » du curseur de priorité (fiche source) passe la source en
`HIDDEN` : ces tests garantissent que cet état miroite bien dans `muted_sources`
(ajout au masquage, retrait au démasquage), pour que « Masqué » retire
réellement la source du flux.
"""

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user_personalization import UserPersonalization
from app.services.user_interests_service import UserSourcesStateService


async def _make_source(db):
    source = Source(
        id=uuid4(),
        name="Mute Sync Source",
        url="https://mute.example.com",
        feed_url=f"https://mute.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db.add(source)
    await db.commit()
    return source


async def _muted_sources(db, user_id):
    perso = (
        await db.execute(
            select(UserPersonalization).where(
                UserPersonalization.user_id == user_id
            )
        )
    ).scalar_one_or_none()
    return list(perso.muted_sources) if perso else []


@pytest.mark.asyncio
async def test_hidden_state_mutes_source_in_feed(db_session):
    """set_state(HIDDEN) ajoute la source à `muted_sources` (exclue du feed)."""
    user_id = uuid4()
    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.HIDDEN)

    assert source.id in await _muted_sources(db_session, user_id)
    # L'état déclaré reste bien HIDDEN côté UserSource.
    state = (
        await db_session.execute(
            select(UserSource.state).where(
                UserSource.user_id == user_id,
                UserSource.source_id == source.id,
            )
        )
    ).scalar_one()
    assert state == InterestState.HIDDEN


@pytest.mark.asyncio
async def test_unhiding_source_removes_it_from_muted(db_session):
    """Repasser à FOLLOWED retire la source de `muted_sources` (réversible)."""
    user_id = uuid4()
    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.HIDDEN)
    assert source.id in await _muted_sources(db_session, user_id)

    await service.set_state(user_id, source.id, InterestState.FOLLOWED)
    assert source.id not in await _muted_sources(db_session, user_id)


@pytest.mark.asyncio
async def test_hidden_is_idempotent_no_duplicate(db_session):
    """Masquer deux fois ne crée pas de doublon dans `muted_sources`."""
    user_id = uuid4()
    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.HIDDEN)
    await service.set_state(user_id, source.id, InterestState.HIDDEN)

    muted = await _muted_sources(db_session, user_id)
    assert muted.count(source.id) == 1


@pytest.mark.asyncio
async def test_non_hidden_state_is_noop_without_personalization(db_session):
    """Suivre une source sans row de perso ne crée pas de masquage parasite."""
    user_id = uuid4()
    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.FOLLOWED)

    assert await _muted_sources(db_session, user_id) == []
