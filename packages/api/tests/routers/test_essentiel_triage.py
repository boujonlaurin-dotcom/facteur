"""Tests pour `POST /api/essentiel/triage` (Story 33.1).

Le test le plus important du fichier est
`test_pass_ne_touche_aucun_poids_de_reco` : c'est le garde-fou du piège n°1 de
la story. L'action `not_interested` existante ajoute la source entière à
`UserPersonalization.muted_sources` sans expiration
(`digest_service.py:_trigger_personalization_mute`) — brancher le swipe gauche
dessus ferait taire un média parce qu'un seul papier n'a pas plu. Sans ce test,
rien n'empêche un futur commit de rebrancher le tri sur les poids « pour que ça
serve à quelque chose ».
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentType, SourceType
from app.models.essentiel_triage import EssentielTriageDecision
from app.models.learning import UserEntityAffinity
from app.models.source import Source
from app.models.user import UserProfile, UserSubtopic
from app.models.user_personalization import UserPersonalization

USER_ID = uuid4()


@pytest_asyncio.fixture
async def client(db_session):
    async def _fake_user():
        return str(USER_ID)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def slate(db_session):
    """Un user + une source + 3 articles : le slate figé du jour."""
    db_session.add(UserProfile(user_id=USER_ID))
    source = Source(
        id=uuid4(),
        name="Le Monde",
        url="https://lemonde.example.com",
        feed_url=f"https://lemonde.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    contents = [
        Content(
            id=uuid4(),
            source_id=source.id,
            title=f"Article {i}",
            url=f"https://lemonde.example.com/a-{uuid4()}",
            guid=str(uuid4()),
            published_at=datetime.now(UTC),
            content_type=ContentType.ARTICLE,
            theme="society",
        )
        for i in range(3)
    ]
    db_session.add_all(contents)
    await db_session.commit()
    return {"source": source, "contents": contents}


def _payload(contents, decisions, *, slate_size=3, digest_date=None):
    return {
        "digest_date": (digest_date or date(2026, 8, 2)).isoformat(),
        "slate_size": slate_size,
        "decisions": [
            {
                "content_id": str(contents[i].id),
                "decision": decision,
                "rank": i + 1,
                "decided_via": "swipe",
                "latency_ms": 1200,
            }
            for i, decision in enumerate(decisions)
        ],
    }


async def _rows(db_session):
    return (
        (
            await db_session.execute(
                select(EssentielTriageDecision).where(
                    EssentielTriageDecision.user_id == USER_ID
                )
            )
        )
        .scalars()
        .all()
    )


@pytest.mark.asyncio
async def test_enregistre_le_batch_avec_rang_et_taille_de_slate(
    client, db_session, slate
):
    """Le rang et la taille du slate sont ce qui rend la collecte exploitable."""
    resp = await client.post(
        "/api/essentiel/triage",
        json=_payload(slate["contents"], ["keep", "pass", "pass"]),
    )

    assert resp.status_code == 200
    assert resp.json()["recorded"] == 3

    rows = sorted(await _rows(db_session), key=lambda r: r.rank)
    assert [r.decision for r in rows] == ["keep", "pass", "pass"]
    assert [r.rank for r in rows] == [1, 2, 3]
    assert {r.slate_size for r in rows} == {3}
    assert {r.digest_date for r in rows} == {date(2026, 8, 2)}
    assert {r.decided_via for r in rows} == {"swipe"}
    assert {r.latency_ms for r in rows} == {1200}


@pytest.mark.asyncio
async def test_upsert_idempotent_et_revision_de_choix(client, db_session, slate):
    """« Trier à nouveau » écrase la décision, sans dupliquer la ligne."""
    contents = slate["contents"]
    first = await client.post(
        "/api/essentiel/triage", json=_payload(contents, ["pass", "pass", "pass"])
    )
    assert first.status_code == 200

    # Rejeu à l'identique (flush réseau redondant) puis révision du choix.
    await client.post(
        "/api/essentiel/triage", json=_payload(contents, ["pass", "pass", "pass"])
    )
    revised = await client.post(
        "/api/essentiel/triage", json=_payload(contents, ["keep", "pass", "pass"])
    )
    assert revised.status_code == 200

    rows = await _rows(db_session)
    assert len(rows) == 3, "l'upsert doit écraser, pas empiler"
    by_content = {r.content_id: r.decision for r in rows}
    assert by_content[contents[0].id] == "keep"


@pytest.mark.asyncio
async def test_meme_article_deux_jours_de_suite_donne_deux_lignes(
    client, db_session, slate
):
    """La date fait partie de la clé — c'est la raison de ne pas réutiliser
    `article_feedback`, unique sur `(user_id, content_id)` seulement."""
    contents = slate["contents"]
    await client.post(
        "/api/essentiel/triage",
        json=_payload(contents, ["keep"], digest_date=date(2026, 8, 1)),
    )
    await client.post(
        "/api/essentiel/triage",
        json=_payload(contents, ["pass"], digest_date=date(2026, 8, 2)),
    )

    rows = await _rows(db_session)
    assert len(rows) == 2
    assert {r.digest_date for r in rows} == {date(2026, 8, 1), date(2026, 8, 2)}


@pytest.mark.asyncio
async def test_batch_partiel_content_id_inconnu_ignore(client, db_session, slate):
    """Un article purgé entre le tri hors-ligne et le flush ne doit pas faire
    perdre les décisions valides du même batch."""
    payload = _payload(slate["contents"], ["keep", "pass"])
    payload["decisions"].append(
        {"content_id": str(uuid4()), "decision": "pass", "rank": 3}
    )

    resp = await client.post("/api/essentiel/triage", json=payload)

    assert resp.status_code == 200
    assert resp.json()["recorded"] == 2
    assert len(await _rows(db_session)) == 2


@pytest.mark.asyncio
async def test_rang_superieur_au_slate_size_rejete(client, db_session, slate):
    """Un rang hors slate fausserait silencieusement le dénominateur de la jauge."""
    payload = _payload(slate["contents"], ["keep"], slate_size=3)
    payload["decisions"][0]["rank"] = 7

    resp = await client.post("/api/essentiel/triage", json=payload)

    assert resp.status_code == 422
    assert await _rows(db_session) == []


@pytest.mark.asyncio
async def test_decision_inconnue_rejetee(client, slate):
    payload = _payload(slate["contents"], ["keep"])
    payload["decisions"][0]["decision"] = "not_interested"

    resp = await client.post("/api/essentiel/triage", json=payload)

    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_decided_via_read_accepte_et_persiste(client, db_session, slate):
    """Story 33.2 : un `keep` venu d'une lecture depuis la pile porte la
    modalité `read` — accepté par le schéma ET par le CHECK de la table."""
    payload = _payload(slate["contents"], ["keep"])
    payload["decisions"][0]["decided_via"] = "read"

    resp = await client.post("/api/essentiel/triage", json=payload)

    assert resp.status_code == 200
    rows = await _rows(db_session)
    assert len(rows) == 1
    assert rows[0].decided_via == "read"
    assert rows[0].decision == "keep"


@pytest.mark.asyncio
async def test_decided_via_inconnu_rejete(client, db_session, slate):
    payload = _payload(slate["contents"], ["keep"])
    payload["decisions"][0]["decided_via"] = "telepathy"

    resp = await client.post("/api/essentiel/triage", json=payload)

    assert resp.status_code == 422
    assert await _rows(db_session) == []


@pytest.mark.asyncio
async def test_later_declenche_le_save_existant(client, db_session, slate):
    """Décision PO (a) : « Plus tard » fait exactement ce que fait le bouton
    signet de la carte, pour ne pas avoir deux « mettre de côté » divergents."""
    contents = slate["contents"]
    resp = await client.post(
        "/api/essentiel/triage", json=_payload(contents, ["later", "pass", "keep"])
    )

    assert resp.status_code == 200
    assert resp.json()["saved_for_later"] == 1

    saved = (
        (
            await db_session.execute(
                select(UserContentStatus).where(
                    UserContentStatus.user_id == USER_ID,
                    UserContentStatus.is_saved.is_(True),
                )
            )
        )
        .scalars()
        .all()
    )
    assert [s.content_id for s in saved] == [contents[0].id]


@pytest.mark.asyncio
async def test_pass_ne_touche_aucun_poids_de_reco(client, db_session, slate):
    """GARDE-FOU du piège n°1 : la collecte ne doit rien apprendre.

    `decision=pass` ne doit modifier ni `user_subtopics.weight`, ni
    `user_entity_affinity`, ni `user_personalization.muted_sources`. Si ce test
    tombe, c'est qu'on a rebranché le tri sur le scoring — ce que la décision PO
    n°2 interdit, et qui, via `not_interested`, muterait la source entière.
    """
    contents = slate["contents"]

    async def _weights_snapshot():
        subtopics = (
            (
                await db_session.execute(
                    select(UserSubtopic).where(UserSubtopic.user_id == USER_ID)
                )
            )
            .scalars()
            .all()
        )
        affinities = (
            (
                await db_session.execute(
                    select(UserEntityAffinity).where(
                        UserEntityAffinity.user_id == USER_ID
                    )
                )
            )
            .scalars()
            .all()
        )
        muted = await db_session.scalar(
            select(func.coalesce(UserPersonalization.muted_sources, [])).where(
                UserPersonalization.user_id == USER_ID
            )
        )
        return (
            {s.subtopic: s.weight for s in subtopics},
            {a.entity_name: a.affinity_score for a in affinities},
            sorted(muted or []),
        )

    before = await _weights_snapshot()

    resp = await client.post(
        "/api/essentiel/triage", json=_payload(contents, ["pass", "pass", "pass"])
    )
    assert resp.status_code == 200

    after = await _weights_snapshot()
    assert after == before, "le tri est en collecte seule : aucun poids ne doit bouger"

    # Et surtout : la source de l'article rejeté n'est pas mutée.
    assert slate["source"].id not in (after[2] or [])
    assert len(await _rows(db_session)) == 3
