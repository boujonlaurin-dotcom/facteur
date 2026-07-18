"""Tests POST /api/waitlist — champs comité de revue (page /methodologie).

Couvre : payload complet (motivation + methode_complete), payload legacy sans
les nouveaux champs, et doublon email qui met à jour les champs comité sur la
ligne existante sans créer de doublon.
"""

from unittest.mock import MagicMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.main import app
from app.models.waitlist import WaitlistEntry


@pytest_asyncio.fixture
async def client(db_session):
    """AsyncClient avec get_db overridé sur la session de test + PostHog mocké."""

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    with patch(
        "app.routers.waitlist.get_posthog_client", return_value=MagicMock()
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            try:
                yield c
            finally:
                app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_join_with_comite_fields(client, db_session):
    """Payload complet : motivation et methode_complete persistés."""
    resp = await client.post(
        "/api/waitlist",
        json={
            "email": "Comite@Example.com",
            "utm_source": "site",
            "utm_medium": "methodologie",
            "utm_campaign": "methodologie-comite",
            "motivation": "Je veux relire la grille.",
            "methode_complete": True,
        },
    )
    assert resp.status_code == 200
    assert resp.json()["is_new"] is True

    entry = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "comite@example.com")
        )
    ).scalar_one()
    assert entry.motivation == "Je veux relire la grille."
    assert entry.methode_complete is True
    assert entry.utm_campaign == "methodologie-comite"


@pytest.mark.asyncio
async def test_join_legacy_payload_without_new_fields(client, db_session):
    """Payload legacy (formulaire waitlist index.html) : comportement inchangé."""
    resp = await client.post("/api/waitlist", json={"email": "legacy@example.com"})
    assert resp.status_code == 200
    assert resp.json()["is_new"] is True

    entry = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "legacy@example.com")
        )
    ).scalar_one()
    assert entry.motivation is None
    assert entry.methode_complete is False


@pytest.mark.asyncio
async def test_duplicate_updates_comite_fields(client, db_session):
    """Un inscrit waitlist existant peut rejoindre le comité (upsert des champs)."""
    first = await client.post("/api/waitlist", json={"email": "dup@example.com"})
    assert first.json()["is_new"] is True

    second = await client.post(
        "/api/waitlist",
        json={
            "email": "dup@example.com",
            "motivation": "Chercheur en SIC.",
            "methode_complete": True,
        },
    )
    assert second.status_code == 200
    assert second.json()["is_new"] is False

    count = await db_session.scalar(
        select(func.count())
        .select_from(WaitlistEntry)
        .where(WaitlistEntry.email == "dup@example.com")
    )
    assert count == 1

    entry = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "dup@example.com")
        )
    ).scalar_one()
    assert entry.motivation == "Chercheur en SIC."
    assert entry.methode_complete is True


@pytest.mark.asyncio
async def test_duplicate_without_comite_fields_leaves_row_untouched(
    client, db_session
):
    """Doublon sans les nouveaux champs : la ligne existante n'est pas modifiée."""
    await client.post(
        "/api/waitlist",
        json={"email": "keep@example.com", "motivation": "Première motivation."},
    )
    resp = await client.post("/api/waitlist", json={"email": "keep@example.com"})
    assert resp.json()["is_new"] is False

    entry = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "keep@example.com")
        )
    ).scalar_one()
    assert entry.motivation == "Première motivation."
