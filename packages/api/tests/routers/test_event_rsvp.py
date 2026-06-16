"""Tests pour POST /api/events/rsvp et le comptage (Story 25.1).

Couvre le scénario clé : un email déjà présent dans la waitlist (que
`WaitlistService.register` dédoublonne et ignore) DOIT quand même être capturé
comme participant dans la table dédiée `event_rsvps`.
"""

from unittest.mock import MagicMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.main import app
from app.models.event_rsvp import EventRsvp
from app.models.waitlist import WaitlistEntry


@pytest_asyncio.fixture
async def client(db_session):
    """AsyncClient avec get_db overridé sur la session de test + PostHog mocké."""

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    with patch(
        "app.routers.event_rsvp.get_posthog_client", return_value=MagicMock()
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            try:
                yield c
            finally:
                app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_rsvp_new_email_creates_rsvp_and_waitlist(client, db_session):
    """Happy path : RSVP d'un nouvel email → ligne event_rsvps + waitlist."""
    resp = await client.post(
        "/api/events/rsvp", json={"email": "Alice@Example.com "}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_new"] is True
    assert body["rsvp_count"] == 1

    # RSVP enregistré (email normalisé)
    rsvp = (
        await db_session.execute(select(EventRsvp).where(EventRsvp.email == "alice@example.com"))
    ).scalar_one()
    assert rsvp.event_slug == "soiree-prelancement"

    # Ajouté aussi à la waitlist avec source = slug de l'événement
    wl = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "alice@example.com")
        )
    ).scalar_one()
    assert wl.source == "soiree-prelancement"


@pytest.mark.asyncio
async def test_rsvp_duplicate_is_idempotent(client, db_session):
    """Un 2e RSVP du même email ne crée pas de doublon (is_new False, count stable)."""
    first = await client.post("/api/events/rsvp", json={"email": "bob@example.com"})
    assert first.json()["is_new"] is True

    second = await client.post("/api/events/rsvp", json={"email": "bob@example.com"})
    assert second.status_code == 200
    assert second.json()["is_new"] is False
    assert second.json()["rsvp_count"] == 1

    count = await db_session.scalar(
        select(func.count()).select_from(EventRsvp).where(EventRsvp.email == "bob@example.com")
    )
    assert count == 1


@pytest.mark.asyncio
async def test_rsvp_existing_waitlist_member_is_still_captured(client, db_session):
    """Le cœur du fix : un email DÉJÀ sur la waitlist est capturé comme participant."""
    db_session.add(WaitlistEntry(email="carol@example.com", source="landing"))
    await db_session.commit()

    resp = await client.post("/api/events/rsvp", json={"email": "carol@example.com"})
    assert resp.status_code == 200
    assert resp.json()["is_new"] is True  # nouveau RSVP, même si déjà sur la waitlist

    rsvp = (
        await db_session.execute(
            select(EventRsvp).where(EventRsvp.email == "carol@example.com")
        )
    ).scalar_one()
    assert rsvp.event_slug == "soiree-prelancement"

    # La source d'origine de la waitlist n'est PAS écrasée (register dédoublonne)
    wl = (
        await db_session.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == "carol@example.com")
        )
    ).scalar_one()
    assert wl.source == "landing"


@pytest.mark.asyncio
async def test_rsvp_count_endpoint(client, db_session):
    """GET /api/events/{slug}/rsvp/count renvoie le nombre de RSVP."""
    for email in ("d@example.com", "e@example.com"):
        await client.post("/api/events/rsvp", json={"email": email})

    resp = await client.get("/api/events/soiree-prelancement/rsvp/count")
    assert resp.status_code == 200
    body = resp.json()
    assert body["event_slug"] == "soiree-prelancement"
    assert body["count"] == 2

    # Un autre événement est compté séparément
    other = await client.get("/api/events/autre-event/rsvp/count")
    assert other.json()["count"] == 0
