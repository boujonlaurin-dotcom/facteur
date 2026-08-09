"""`GET /api/alerts/suggestions` — proposer, mais seulement ce qui se justifie.

Le reproche PO était l'absence totale de proposition. Le risque symétrique, une
fois l'endpoint écrit, est de proposer n'importe quoi : une source morte, un
thème parent, une cible déjà sous cloche, ou une cible que l'utilisateur vient
d'écarter. Ces tests verrouillent donc autant les **exclusions** que le
classement, plus le coût en requêtes (même pattern que le lot B).
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState, SourceType
from app.models.learning import UserEntityAffinity
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.services.alert_suggestions import (
    MAX_SUGGESTIONS,
    SIGNAL_SOURCE_READ,
    SIGNAL_SOURCE_READ_LIGHT,
    SIGNAL_TOPIC_AFFINITY,
    SIGNAL_TOPIC_WEIGHT,
)

NOW = datetime.now(UTC)

#: Borne dure du coût de l'endpoint : 8 requêtes constantes (2 pour le compteur
#: de plafond canonique, 1 personnalisation, 3 sources, 2 sujets) + le budget de
#: cadence sujet (8). Elle ne doit jamais bouger sans une décision explicite :
#: cet endpoint est appelé à chaque ouverture de « Mes alertes ».
MAX_QUERIES = 16


class _QueryCounter:
    """Compteur de requêtes SQL réelles (hors SAVEPOINT de la fixture)."""

    def __init__(self) -> None:
        self.count = 0

    def _on_execute(self, conn, cursor, statement, parameters, context, executemany):
        upper = statement.lstrip().upper()
        if upper.startswith(("SAVEPOINT", "RELEASE", "ROLLBACK")):
            return
        self.count += 1

    def attach(self, sync_conn):
        event.listen(sync_conn, "before_cursor_execute", self._on_execute)

    def detach(self, sync_conn):
        event.remove(sync_conn, "before_cursor_execute", self._on_execute)


@pytest_asyncio.fixture
async def suggest_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Suggestions User",
            onboarding_completed=True,
        )
    )
    await db_session.commit()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        yield user_id
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _make_source(
    db_session, *, name: str, theme: str = "society", is_active: bool = True
) -> Source:
    source = Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme=theme,
        is_active=is_active,
        is_curated=True,
        logo_url=f"https://logo.example/{name}.png",
    )
    db_session.add(source)
    await db_session.flush()
    return source


async def _follow(
    db_session, user_id, source: Source, *, notify: bool | None = None
) -> None:
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=notify,
        )
    )


async def _publish(
    db_session,
    source: Source,
    *,
    count: int,
    days_ago_start: float = 1,
    entity: str | None = None,
) -> list[Content]:
    contents = []
    for i in range(count):
        content = Content(
            id=uuid4(),
            source_id=source.id,
            title=f"{source.name} article {i}",
            url=f"https://example.com/{uuid4()}",
            guid=str(uuid4()),
            published_at=NOW - timedelta(days=days_ago_start + i),
            content_type=ContentType.ARTICLE,
            theme="society",
            entities=[f'{{"name": "{entity}", "type": "EVENT"}}'] if entity else None,
        )
        db_session.add(content)
        contents.append(content)
    await db_session.flush()
    return contents


async def _mark(db_session, user_id, contents, *, read: int, seen: int = 0) -> None:
    """`read` contenus ouverts (`consumed`), `seen` simplement vus."""
    for content in contents[:read]:
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=content.id,
                status=ContentStatus.CONSUMED,
            )
        )
    for content in contents[read : read + seen]:
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=content.id,
                status=ContentStatus.SEEN,
            )
        )
    await db_session.flush()


async def _topic(
    db_session,
    user_id,
    *,
    name: str,
    notify: bool | None = None,
    composite_score: float = 0.0,
    priority_multiplier: float = 1.0,
    slug_parent: str = "sport",
) -> UserTopicProfile:
    profile = UserTopicProfile(
        user_id=user_id,
        topic_name=name,
        slug_parent=slug_parent,
        canonical_name=name,
        keywords=[],
        state=InterestState.FOLLOWED,
        notify=notify,
        composite_score=composite_score,
        priority_multiplier=priority_multiplier,
    )
    db_session.add(profile)
    await db_session.flush()
    return profile


async def _get_suggestions(client=None):
    if client is not None:
        return (await client.get("/api/alerts/suggestions")).json()
    async with _client() as c:
        return (await c.get("/api/alerts/suggestions")).json()


# ─────────────────────────────────────────────────────────────────────────────
# Le classement
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_la_source_lue_passe_devant_le_sujet_declare(suggest_user, db_session):
    """Consommation réelle > déclaratif : c'est tout l'ordre de preuve."""
    read_source = await _make_source(db_session, name="Le Lu")
    await _follow(db_session, suggest_user, read_source)
    contents = await _publish(db_session, read_source, count=10)
    await _mark(db_session, suggest_user, contents, read=8, seen=2)

    declared = await _topic(db_session, suggest_user, name="Ligue 1", composite_score=9)
    declared_source = await _make_source(db_session, name="Le Sujet")
    await _publish(db_session, declared_source, count=6, entity="Ligue 1")
    await db_session.commit()
    assert declared.id  # le sujet existe bien, il est juste moins bien classé

    body = await _get_suggestions()

    assert body["at_cap"] is False
    names = [s["target_name"] for s in body["suggestions"]]
    assert names[0] == "Le Lu"
    assert "Ligue 1" in names
    first = body["suggestions"][0]
    assert first["signal"] == SIGNAL_SOURCE_READ
    assert (
        first["reason"] == "Tu as ouvert 8 articles sur 10 de cette source ce mois-ci."
    )
    assert first["cadence_phrase"]
    assert body["suggestions"][-1]["signal"] == SIGNAL_TOPIC_WEIGHT


@pytest.mark.asyncio
async def test_le_sujet_a_affinite_passe_devant_la_source_a_peine_lue(
    suggest_user, db_session
):
    """Rang 2 (affinité apprise) devant rang 3 (une seule ouverture)."""
    thin = await _make_source(db_session, name="Le Feuilleté")
    await _follow(db_session, suggest_user, thin)
    contents = await _publish(db_session, thin, count=5)
    await _mark(db_session, suggest_user, contents, read=1)

    await _topic(db_session, suggest_user, name="Ligue 1")
    affinity_source = await _make_source(db_session, name="Le Sport")
    await _publish(db_session, affinity_source, count=6, entity="Ligue 1")
    db_session.add(
        UserEntityAffinity(
            user_id=suggest_user,
            entity_canonical="ligue 1",
            affinity=2.4,
            interaction_count=6,
        )
    )
    await db_session.commit()

    body = await _get_suggestions()

    signals = [s["signal"] for s in body["suggestions"]]
    names = [s["target_name"] for s in body["suggestions"]]
    assert names == ["Ligue 1", "Le Feuilleté"]
    assert signals == [SIGNAL_TOPIC_AFFINITY, SIGNAL_SOURCE_READ_LIGHT]
    assert (
        body["suggestions"][0]["reason"]
        == "Tu ouvres régulièrement les articles sur ce sujet."
    )
    assert (
        body["suggestions"][1]["reason"]
        == "Tu as ouvert 1 article de cette source ce mois-ci."
    )


@pytest.mark.asyncio
async def test_une_source_suivie_jamais_ouverte_nest_pas_proposee(
    suggest_user, db_session
):
    """« Une source suivie mais jamais ouverte ne mérite pas une cloche. »"""
    never_read = await _make_source(db_session, name="Le Jamais Ouvert")
    await _follow(db_session, suggest_user, never_read)
    contents = await _publish(db_session, never_read, count=12)
    # Vue en boucle dans le flux, jamais ouverte : `seen` n'est pas une preuve.
    await _mark(db_session, suggest_user, contents, read=0, seen=12)
    await db_session.commit()

    body = await _get_suggestions()

    assert body["suggestions"] == []


@pytest.mark.asyncio
async def test_au_plus_cinq_suggestions(suggest_user, db_session):
    for i in range(9):
        source = await _make_source(db_session, name=f"Source {i}")
        await _follow(db_session, suggest_user, source)
        contents = await _publish(db_session, source, count=14)
        await _mark(db_session, suggest_user, contents, read=3 + i)
    await db_session.commit()

    body = await _get_suggestions()

    assert len(body["suggestions"]) == MAX_SUGGESTIONS
    # Les plus lues d'abord.
    assert [s["target_name"] for s in body["suggestions"]] == [
        "Source 8",
        "Source 7",
        "Source 6",
        "Source 5",
        "Source 4",
    ]


# ─────────────────────────────────────────────────────────────────────────────
# Les exclusions
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_ni_deja_sous_cloche_ni_mutee_ni_morte_ni_inactive(
    suggest_user, db_session
):
    """Quatre exclusions, une seule requête : aucune ne doit sortir."""
    belled = await _make_source(db_session, name="Déjà Alerté")
    await _follow(db_session, suggest_user, belled, notify=True)
    await _mark(
        db_session, suggest_user, await _publish(db_session, belled, count=6), read=5
    )

    muted = await _make_source(db_session, name="Muté")
    await _follow(db_session, suggest_user, muted)
    await _mark(
        db_session, suggest_user, await _publish(db_session, muted, count=6), read=5
    )

    muted_theme = await _make_source(db_session, name="Thème Muté", theme="tech")
    await _follow(db_session, suggest_user, muted_theme)
    await _mark(
        db_session,
        suggest_user,
        await _publish(db_session, muted_theme, count=6),
        read=5,
    )

    dead = await _make_source(db_session, name="Morte")
    await _follow(db_session, suggest_user, dead)
    old = await _publish(db_session, dead, count=4, days_ago_start=200)
    await _mark(db_session, suggest_user, old, read=4)

    inactive = await _make_source(db_session, name="Inactive", is_active=False)
    await _follow(db_session, suggest_user, inactive)
    await _mark(
        db_session, suggest_user, await _publish(db_session, inactive, count=6), read=5
    )

    ok = await _make_source(db_session, name="La Bonne")
    await _follow(db_session, suggest_user, ok)
    await _mark(
        db_session, suggest_user, await _publish(db_session, ok, count=6), read=5
    )

    db_session.add(
        UserPersonalization(
            user_id=suggest_user,
            muted_sources=[muted.id],
            muted_themes=["tech"],
        )
    )
    await db_session.commit()

    body = await _get_suggestions()

    assert [s["target_name"] for s in body["suggestions"]] == ["La Bonne"]
    assert body["active_count"] == 1


@pytest.mark.asyncio
async def test_un_theme_parent_nest_jamais_propose(suggest_user, db_session):
    """La 30.3 l'a écarté : « politique » ferait de la cloche un robinet."""
    generalist = await _make_source(db_session, name="Le Généraliste")
    await _publish(db_session, generalist, count=40, entity="Politique")

    await _topic(db_session, suggest_user, name="Politique", composite_score=12)
    await _topic(db_session, suggest_user, name="Sport", composite_score=11)
    await _topic(db_session, suggest_user, name="Ligue 1", composite_score=3)
    await _publish(db_session, generalist, count=6, entity="Ligue 1")
    await db_session.commit()

    body = await _get_suggestions()

    names = [s["target_name"] for s in body["suggestions"]]
    assert names == ["Ligue 1"]


@pytest.mark.asyncio
async def test_un_sujet_sans_predicat_ou_sans_article_nest_pas_propose(
    suggest_user, db_session
):
    """Une cloche qui ne peut pas sonner ne se propose pas."""
    empty = UserTopicProfile(
        user_id=suggest_user,
        topic_name="Sujet indécidable",
        slug_parent="society",
        canonical_name=None,
        keywords=[],
        state=InterestState.FOLLOWED,
        composite_score=8,
    )
    db_session.add(empty)
    # Prédicat valide, mais plus rien ne matche depuis longtemps.
    await _topic(db_session, suggest_user, name="Sujet éteint", composite_score=7)
    silent = await _make_source(db_session, name="Le Silencieux")
    await _publish(
        db_session, silent, count=5, days_ago_start=200, entity="Sujet éteint"
    )
    await db_session.commit()

    body = await _get_suggestions()

    assert body["suggestions"] == []


@pytest.mark.asyncio
async def test_deux_profils_homonymes_ne_font_quune_suggestion(
    suggest_user, db_session
):
    """Constaté en base : un compte peut porter deux lignes « NBA ».

    L'index unique ne couvre que `canonical_name` non nul, donc un doublon par
    mot-clé passe : c'est exactement la forme observée en production.
    """
    await _topic(db_session, suggest_user, name="NBA", composite_score=4)
    db_session.add(
        UserTopicProfile(
            user_id=suggest_user,
            topic_name="NBA",
            slug_parent="sport",
            canonical_name=None,
            keywords=["NBA"],
            state=InterestState.FOLLOWED,
            composite_score=2,
        )
    )
    await db_session.flush()
    carrier = await _make_source(db_session, name="Le Porteur")
    await _publish(db_session, carrier, count=6, entity="NBA")
    await db_session.commit()

    body = await _get_suggestions()

    assert [s["target_name"] for s in body["suggestions"]] == ["NBA"]


@pytest.mark.asyncio
async def test_une_cible_bruyante_arrive_avec_le_mode_filtre_pre_coche(
    suggest_user, db_session
):
    """Règle 30.3 : jamais de cible bruyante proposée « nue »."""
    noisy = await _make_source(db_session, name="Le Robinet")
    await _follow(db_session, suggest_user, noisy)
    contents = await _publish(db_session, noisy, count=25)
    await _mark(db_session, suggest_user, contents, read=5)
    await db_session.commit()

    body = await _get_suggestions()

    suggestion = body["suggestions"][0]
    assert suggestion["noisy"] is True
    assert suggestion["prefill_filtered"] is True


@pytest.mark.asyncio
async def test_la_cadence_annoncee_est_celle_de_linventaire(suggest_user, db_session):
    """La suggestion et la fiche doivent dire la même chose de la même source.

    Cas qui les faisait diverger : une source **ancienne** avec seulement deux
    parutions récentes. Si le `min(published_at)` est restreint à la fenêtre
    30 j, `_per_day` clampe sur quelques jours et la source passe pour
    bruyante ; l'inventaire, lui, prend le `min` sur tout l'historique et
    annonce « une fois par mois ».
    """
    old_source = await _make_source(db_session, name="La Trimestrielle")
    await _follow(db_session, suggest_user, old_source)
    await _publish(db_session, old_source, count=6, days_ago_start=200)
    recent = await _publish(db_session, old_source, count=2, days_ago_start=1)
    await _mark(db_session, suggest_user, recent, read=2)
    await db_session.commit()

    async with _client() as client:
        suggestion = (await client.get("/api/alerts/suggestions")).json()[
            "suggestions"
        ][0]
        # On pose la cloche, puis on relit l'inventaire : c'est lui qui gouverne
        # les envois, donc c'est lui qui fait foi.
        await client.put(
            f"/api/sources/{old_source.id}/alert",
            json={"enabled": True, "filtered": False},
        )
        item = (await client.get("/api/alerts")).json()["items"][0]

    assert suggestion["articles_30d"] == item["articles_30d"] == 2
    assert suggestion["cadence_per_week"] == pytest.approx(item["cadence_per_week"])
    assert suggestion["noisy"] is False
    assert suggestion["prefill_filtered"] is False


@pytest.mark.asyncio
async def test_au_plafond_on_ne_propose_rien_et_on_le_dit(suggest_user, db_session):
    for i in range(5):
        belled = await _make_source(db_session, name=f"Cloche {i}")
        await _follow(db_session, suggest_user, belled, notify=True)
    tempting = await _make_source(db_session, name="La Tentante")
    await _follow(db_session, suggest_user, tempting)
    await _mark(
        db_session, suggest_user, await _publish(db_session, tempting, count=8), read=8
    )
    await db_session.commit()

    body = await _get_suggestions()

    assert body["at_cap"] is True
    assert body["active_count"] == 5
    assert body["cap"] == 5
    assert body["suggestions"] == []


@pytest.mark.asyncio
async def test_au_plafond_aucun_signal_nest_interroge(suggest_user, db_session):
    """Le plafond se tranche avant tout, pas après avoir tout calculé.

    Sans ce test, la garde pouvait migrer après les requêtes de signaux sans
    que rien ne le voie : la réponse serait identique, le coût non.
    """
    for i in range(5):
        belled = await _make_source(db_session, name=f"Cloche {i}")
        await _follow(db_session, suggest_user, belled, notify=True)
    for i in range(6):
        tempting = await _make_source(db_session, name=f"Tentante {i}")
        await _follow(db_session, suggest_user, tempting)
        await _mark(
            db_session,
            suggest_user,
            await _publish(db_session, tempting, count=8),
            read=8,
        )
    await db_session.commit()

    counter = _QueryCounter()
    raw = await db_session.connection()
    counter.attach(raw.sync_connection)
    try:
        body = await _get_suggestions()
    finally:
        counter.detach(raw.sync_connection)

    assert body["at_cap"] is True
    # Les 2 requêtes du compteur canonique, et rien d'autre.
    assert counter.count == 2, f"{counter.count} requêtes au plafond"


# ─────────────────────────────────────────────────────────────────────────────
# Le refus se souvient
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_une_suggestion_refusee_ne_revient_pas(suggest_user, db_session):
    refused = await _make_source(db_session, name="La Refusée")
    await _follow(db_session, suggest_user, refused)
    await _mark(
        db_session, suggest_user, await _publish(db_session, refused, count=6), read=5
    )
    kept = await _make_source(db_session, name="La Gardée")
    await _follow(db_session, suggest_user, kept)
    await _mark(
        db_session, suggest_user, await _publish(db_session, kept, count=6), read=4
    )
    await db_session.commit()

    async with _client() as client:
        before = (await client.get("/api/alerts/suggestions")).json()
        assert {s["target_name"] for s in before["suggestions"]} == {
            "La Refusée",
            "La Gardée",
        }

        dismissed = await client.post(
            "/api/alerts/suggestions/dismiss",
            json={"kind": "source", "target_id": str(refused.id)},
        )
        assert dismissed.status_code == 200
        assert dismissed.json() == {"dismissed": True}

        # Idempotent : un second refus ne duplique rien et ne casse rien.
        assert (
            await client.post(
                "/api/alerts/suggestions/dismiss",
                json={"kind": "source", "target_id": str(refused.id)},
            )
        ).status_code == 200

        after = (await client.get("/api/alerts/suggestions")).json()

    assert [s["target_name"] for s in after["suggestions"]] == ["La Gardée"]

    perso = await db_session.get(UserPersonalization, suggest_user)
    assert perso.dismissed_alert_sources == [refused.id]
    assert perso.dismissed_alert_topics == []


@pytest.mark.asyncio
async def test_un_sujet_refuse_ne_revient_pas(suggest_user, db_session):
    profile = await _topic(db_session, suggest_user, name="Ligue 1", composite_score=5)
    source = await _make_source(db_session, name="Le Sport")
    await _publish(db_session, source, count=6, entity="Ligue 1")
    await db_session.commit()

    async with _client() as client:
        before = (await client.get("/api/alerts/suggestions")).json()
        assert [s["target_name"] for s in before["suggestions"]] == ["Ligue 1"]

        await client.post(
            "/api/alerts/suggestions/dismiss",
            json={"kind": "topic", "target_id": str(profile.id)},
        )
        after = (await client.get("/api/alerts/suggestions")).json()

    assert after["suggestions"] == []


# ─────────────────────────────────────────────────────────────────────────────
# Le coût
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_le_cout_en_requetes_reste_borne(suggest_user, db_session):
    """Une passe agrégée, pas une boucle par cible.

    Pire cas construit à la main : 12 sources suivies et lues, **et** 10 sujets
    à affinité (rang 2, donc servis avant les sources), dont les mieux classés
    sont éteints. Chaque sujet examiné coûte une requête de cadence : c'est le
    seul poste variable de l'endpoint, et le budget dur doit le plafonner.
    """
    for i in range(12):
        source = await _make_source(db_session, name=f"Source {i}")
        await _follow(db_session, suggest_user, source)
        contents = await _publish(db_session, source, count=4)
        await _mark(db_session, suggest_user, contents, read=1)

    carrier = await _make_source(db_session, name="Le Porteur")
    for i in range(10):
        name = f"Sujet numéro {chr(ord('A') + i)}"
        await _topic(db_session, suggest_user, name=name)
        db_session.add(
            UserEntityAffinity(
                user_id=suggest_user,
                entity_canonical=name.lower(),
                # Les mieux classés sont ceux qui n'ont plus rien à annoncer :
                # ils brûlent le budget avant que les vivants sortent.
                affinity=2.9 - i * 0.1,
                interaction_count=5,
            )
        )
        await _publish(
            db_session,
            carrier,
            count=3,
            days_ago_start=1 if i >= 5 else 300,
            entity=name,
        )
    await db_session.commit()

    counter = _QueryCounter()
    raw = await db_session.connection()
    counter.attach(raw.sync_connection)
    try:
        async with _client() as client:
            body = (await client.get("/api/alerts/suggestions")).json()
    finally:
        counter.detach(raw.sync_connection)

    assert len(body["suggestions"]) == MAX_SUGGESTIONS
    # Le budget a bien été sollicité : sinon le test ne prouverait rien.
    assert counter.count > 6, "le poste variable n'a pas été exercé"
    assert counter.count <= MAX_QUERIES, (
        f"{counter.count} requêtes pour une passe de suggestions (borne {MAX_QUERIES})"
    )
    # Le budget épuisé ne laisse pas l'écran vide : les sources prennent le
    # relais sur les places restantes.
    assert {s["kind"] for s in body["suggestions"]} == {"topic", "source"}


@pytest.mark.asyncio
async def test_compte_vide_ne_propose_rien_sans_planter(suggest_user, db_session):
    await db_session.commit()

    body = await _get_suggestions()

    assert body == {
        "cap": 5,
        "active_count": 0,
        "at_cap": False,
        "suggestions": [],
    }
