"""Régression Sentry PYTHON-5R — race condition user_profiles_user_id_key.

L'ancien `create_profile` faisait un check-then-insert (get_profile ; si absent →
add() + flush). Sous concurrence (deux GET /api/notification-preferences/ quasi
simultanés pour un user tout juste créé), les deux requêtes voyaient « aucun
profil » et inséraient → IntegrityError sur user_profiles_user_id_key → 500.

Le fix encapsule l'INSERT dans un savepoint (`begin_nested`) + catch
IntegrityError + re-read de la row écrite par la requête gagnante. La requête
« perdante » d'une course emprunte la branche re-read — c'est exactement ce
qu'exerce ici un second appel séquentiel sur le même user_id.

NB : la fixture `db_session` isole chaque test dans une connexion unique +
savepoints (cf. conftest), donc une vraie concurrence 2-connexions n'est pas
reproductible ici ; on valide le chemin savepoint → catch → re-read de façon
déterministe (même approche que tests/test_interest_weight_concurrency.py).
"""

from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.user import UserProfile
from app.services.user_service import UserService


@pytest.mark.asyncio
async def test_create_profile_twice_no_integrity_error(db_session):
    """2e create_profile pour le même user_id → aucune exception, re-read de la
    row gagnante, une seule row en DB."""
    service = UserService(db_session)
    user_id = str(uuid4())

    p1 = await service.create_profile(user_id)
    await db_session.commit()

    # Requête « perdante » : même user_id → viole user_profiles_user_id_key sur
    # le flush du savepoint → catch → re-read de la row de la gagnante.
    p2 = await service.create_profile(user_id)
    await db_session.commit()

    assert p1 is not None
    assert p2 is not None
    assert str(p2.user_id) == user_id
    assert p2.user_id == p1.user_id

    count = await db_session.scalar(
        select(func.count())
        .select_from(UserProfile)
        .where(UserProfile.user_id == p1.user_id)
    )
    assert count == 1, "aucun doublon : la contrainte unique tient"


@pytest.mark.asyncio
async def test_get_or_create_profile_idempotent(db_session):
    """Deux get_or_create_profile → même profil, aucune exception, une row."""
    service = UserService(db_session)
    user_id = str(uuid4())

    p1 = await service.get_or_create_profile(user_id)
    await db_session.commit()
    p2 = await service.get_or_create_profile(user_id)
    await db_session.commit()

    assert p1.user_id == p2.user_id

    count = await db_session.scalar(
        select(func.count())
        .select_from(UserProfile)
        .where(UserProfile.user_id == p1.user_id)
    )
    assert count == 1, "aucun doublon : la contrainte unique tient"
