"""Régression Sentry PYTHON-3K — race condition pk_user_letter_progress.

L'ancien `_init_progress` faisait un check-then-insert (`_ensure_rows` : si
aucune row → init complet). Sous concurrence (deux GET /api/letters quasi
simultanés pour un user tout juste créé), les deux requêtes voyaient « aucune
row » et inséraient toute la progression → IntegrityError sur
pk_user_letter_progress → 500, ce qui bloquait la lecture de L'Édition.

Le fix encapsule les INSERT de `_init_progress` dans un savepoint (`begin_nested`)
+ catch IntegrityError ; `_ensure_rows` relit ensuite l'état complet écrit par
la requête gagnante. La requête « perdante » d'une course emprunte la branche
catch — c'est exactement ce qu'exerce ici un second appel séquentiel sur le
même user.

NB : la fixture `db_session` isole chaque test dans une connexion unique +
savepoints (cf. conftest), donc une vraie concurrence 2-connexions n'est pas
reproductible ici ; on valide le chemin savepoint → catch de façon déterministe
(même approche que tests/test_interest_weight_concurrency.py).
"""

from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.user_letter_progress import UserLetterProgress
from app.services.letters.catalog import LETTERS_ORDER
from app.services.letters.service import _ensure_rows, _get_rows, _init_progress


@pytest.mark.asyncio
async def test_init_progress_twice_no_integrity_error(db_session):
    """2e _init_progress pour le même user → aucune exception, une row par
    lettre, aucun doublon."""
    user_id = uuid4()

    await _init_progress(user_id, db_session)
    # Requête « perdante » : mêmes (user_id, letter_id) → viole
    # pk_user_letter_progress sur le flush du savepoint → catch.
    await _init_progress(user_id, db_session)

    rows = await _get_rows(user_id, db_session)
    assert len(rows) == len(LETTERS_ORDER)
    assert set(rows.keys()) == {catalog["id"] for catalog in LETTERS_ORDER}

    total = await db_session.scalar(
        select(func.count())
        .select_from(UserLetterProgress)
        .where(UserLetterProgress.user_id == user_id)
    )
    assert total == len(LETTERS_ORDER), "aucun doublon : la PK tient"


@pytest.mark.asyncio
async def test_ensure_rows_coherent_after_double_init(db_session):
    """Après un double init racé, `_ensure_rows` retourne un état cohérent :
    une row par lettre, statuts par défaut du catalogue préservés."""
    user_id = uuid4()

    await _init_progress(user_id, db_session)
    await _init_progress(user_id, db_session)

    rows = await _ensure_rows(user_id, db_session)
    assert len(rows) == len(LETTERS_ORDER)
    for catalog in LETTERS_ORDER:
        assert rows[catalog["id"]].status == catalog["default_status"]
