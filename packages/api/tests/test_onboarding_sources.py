"""Tests : enregistrement robuste des sources en fin d'onboarding.

Couvre le bug récurrent de "silent error" : les sources sélectionnées doivent
être enregistrées atomiquement, sans qu'un ID inexistant/inactif/invalide ne
fasse échouer (rollback) tout l'onboarding, et avec un compte exact retourné.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import select

from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.schemas.user import OnboardingAnswers
from app.services.user_service import UserService


def _answers(preferred_sources: list[str]) -> OnboardingAnswers:
    """Réponses d'onboarding minimales valides + sources à enregistrer."""
    return OnboardingAnswers(
        objective="learn",
        approach="direct",
        response_style="decisive",
        preferred_sources=preferred_sources,
    )


async def _make_source(db_session, *, is_active: bool = True) -> Source:
    source = Source(
        id=uuid4(),
        name="Src",
        url="https://example.com",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=is_active,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    return source


@pytest.mark.asyncio
async def test_registers_active_sources(db_session):
    """Les sources actives demandées sont enregistrées (count exact)."""
    user_id = str(uuid4())
    s1 = await _make_source(db_session)
    s2 = await _make_source(db_session)

    result = await UserService(db_session).save_onboarding(
        user_id, _answers([str(s1.id), str(s2.id)])
    )

    assert result["sources_requested"] == 2
    assert result["sources_created"] == 2
    assert result["sources_skipped"] == 0

    rows = (
        (
            await db_session.execute(
                select(UserSource).where(UserSource.user_id == UUID(user_id))
            )
        )
        .scalars()
        .all()
    )
    assert {r.source_id for r in rows} == {s1.id, s2.id}


@pytest.mark.asyncio
async def test_skips_invalid_inactive_unknown_without_rollback(db_session):
    """Un ID invalide / inactif / inconnu est ignoré, sans faire échouer l'onboarding.

    C'est le cœur du correctif : avant, un ID inconnu provoquait une FK
    IntegrityError → rollback total → onboarding échoué silencieusement.
    """
    user_id = str(uuid4())
    active = await _make_source(db_session)
    inactive = await _make_source(db_session, is_active=False)
    unknown = str(uuid4())  # format valide mais aucune source correspondante
    invalid = "pas-un-uuid"

    result = await UserService(db_session).save_onboarding(
        user_id,
        _answers([str(active.id), str(inactive.id), unknown, invalid]),
    )

    # Seule la source active est enregistrée ; les 3 autres sont ignorées.
    assert result["sources_requested"] == 4
    assert result["sources_created"] == 1
    assert result["sources_skipped"] == 3

    # L'onboarding a bien abouti (profil marqué complété, pas de rollback).
    assert result["profile"].onboarding_completed is True

    rows = (
        (
            await db_session.execute(
                select(UserSource).where(UserSource.user_id == UUID(user_id))
            )
        )
        .scalars()
        .all()
    )
    assert {r.source_id for r in rows} == {active.id}


@pytest.mark.asyncio
async def test_idempotent_rerun(db_session):
    """Relancer l'onboarding ne duplique pas les sources et n'échoue pas."""
    user_id = str(uuid4())
    s1 = await _make_source(db_session)
    service = UserService(db_session)

    first = await service.save_onboarding(user_id, _answers([str(s1.id)]))
    assert first["sources_created"] == 1

    second = await service.save_onboarding(user_id, _answers([str(s1.id)]))
    # Déjà suivie → 0 nouvelle insertion, 0 ignorée (la source existe/est active)
    assert second["sources_created"] == 0
    assert second["sources_skipped"] == 0

    rows = (
        (
            await db_session.execute(
                select(UserSource).where(UserSource.user_id == UUID(user_id))
            )
        )
        .scalars()
        .all()
    )
    assert len(rows) == 1
