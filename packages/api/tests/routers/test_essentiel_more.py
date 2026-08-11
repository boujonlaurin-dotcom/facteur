"""Tests pour `GET /api/essentiel/more` (Story 33.3).

Les tests de `fetch_essentiel_more` (moteur) vivent dans
`tests/test_essentiel_supplements.py` : ils couvrent l'exclusion, le `limit` et
le pool vide. Ce fichier couvre ce que le service ne voit jamais — la **couche
HTTP** :

- l'authentification (le CTA « Plus d'articles ? » est derrière un compte) ;
- le parsing de `exclude`, qui est de la logique à part entière (split sur la
  virgule, cap à `MAX_MORE_EXCLUDE_IDS`, id illisible ignoré au lieu de faire
  tomber tout le lot) ;
- les bornes de `limit`.

Le point le plus important est `test_exclude_illisible_n_invalide_pas_le_lot` :
un seul id corrompu dans SharedPreferences côté mobile ne doit pas transformer
« Plus d'articles ? » en erreur permanente pour la journée.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.user import UserProfile
from app.schemas.essentiel import MAX_MORE_EXCLUDE_IDS

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
async def user(db_session):
    """User sans source suivie ni thème apprécié ⇒ pool live vide.

    C'est exactement le cas « Pas de nouvel article pour l'instant. » du mobile :
    une réponse 200 à liste vide, jamais une erreur.
    """
    db_session.add(UserProfile(user_id=USER_ID))
    await db_session.commit()
    return USER_ID


@pytest.mark.asyncio
async def test_sans_jwt_401(db_session):
    """Sans override d'auth, la dépendance réelle rejette la requête.

    Le CTA est derrière un compte : un anonyme ne doit pas pouvoir tirer des
    recommandations personnalisées.
    """

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            response = await ac.get("/api/essentiel/more?limit=2")
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert response.status_code in (401, 403)


@pytest.mark.asyncio
async def test_pool_vide_renvoie_200_et_liste_vide(client, user):
    """Pool épuisé ⇒ 200 + `{"articles": []}`, surtout pas 202.

    Le mobile traite un 202 comme « digest en préparation » et le 4xx/5xx comme
    une panne : les deux feraient passer un état normal pour un incident.
    """
    response = await client.get("/api/essentiel/more?limit=2")

    assert response.status_code == 200
    assert response.json() == {"articles": []}


@pytest.mark.asyncio
async def test_exclude_illisible_n_invalide_pas_le_lot(client, user):
    """Un id corrompu est ignoré, le reste de la liste est honoré.

    Refuser tout le lot (422) rendrait le CTA définitivement mort tant que
    l'entrée corrompue reste dans SharedPreferences.
    """
    valide = uuid4()
    response = await client.get(
        f"/api/essentiel/more?limit=2&exclude=pas-un-uuid,{valide},,{uuid4()}"
    )

    assert response.status_code == 200
    assert response.json() == {"articles": []}


@pytest.mark.asyncio
async def test_exclude_au_dela_du_cap_ne_fait_pas_tomber_la_requete(client, user):
    """Au-delà de `MAX_MORE_EXCLUDE_IDS`, le surplus est tronqué, pas rejeté."""
    trop = ",".join(str(uuid4()) for _ in range(MAX_MORE_EXCLUDE_IDS + 20))
    response = await client.get(f"/api/essentiel/more?limit=2&exclude={trop}")

    assert response.status_code == 200
    assert response.json() == {"articles": []}


@pytest.mark.asyncio
async def test_exclude_de_250_ids_arrive_entier_au_service(client, user):
    """250 exclusions passent **sans troncature** (Story 33.4).

    Le slate n'est plus borné par la cible du jour : il porte tout le pool
    proposé et dépasse 100 ids sur une grosse journée de tri. La troncature
    `exclude.split(",")[:N]` est silencieuse — sous l'ancien cap de 100, on se
    remettait à proposer des articles déjà écartés sans que rien ne le signale.
    """
    ids = [uuid4() for _ in range(250)]

    with patch(
        "app.routers.essentiel.fetch_essentiel_more",
        new=AsyncMock(return_value=[]),
    ) as spy:
        response = await client.get(
            "/api/essentiel/more",
            params={"exclude": ",".join(str(i) for i in ids)},
        )

    assert response.status_code == 200
    assert spy.await_args.kwargs["exclude_ids"] == set(ids)


@pytest.mark.asyncio
@pytest.mark.parametrize("limit", [0, 11, -1])
async def test_limit_hors_bornes_rejete(client, user, limit):
    """`limit` est borné 1..10 par le contrat : hors bornes ⇒ 422."""
    response = await client.get(f"/api/essentiel/more?limit={limit}")

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_limit_dix_accepte_pour_le_prefetch_de_la_pile(client, user):
    """Un lot de 10 est accepté (Story 33.4).

    Le prefetch de la pile de tri demande des lots de 5, et l'endpoint doit
    laisser de la marge : sous l'ancien `le=5`, la seule façon d'alimenter une
    pile aurait été de multiplier les appels.
    """
    response = await client.get("/api/essentiel/more?limit=10")

    assert response.status_code == 200


@pytest.mark.asyncio
async def test_limit_par_defaut_accepte_sans_parametre(client, user):
    """Sans `limit`, le défaut (« Deux de plus ») s'applique."""
    response = await client.get("/api/essentiel/more")

    assert response.status_code == 200
    assert response.json() == {"articles": []}
