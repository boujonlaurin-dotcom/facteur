"""Tests pour scripts/repair_broken_feeds.py (Composant 3).

Couvre : Mécaniques du Complot réparé (feed_url -> URL connue qui probe OK) ;
les 6 flux PO désactivés (is_active=false, follows conservés) ; dry-run =
aucune mutation ; idempotence (re-run = no-op, sources déjà inactives).

`test_feed` (probe réseau) est monkeypatché : aucun appel HTTP réel.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import text

import scripts.repair_broken_feeds as rbf
from app.models.enums import BiasOrigin, BiasStance, ReliabilityScore, SourceType
from app.models.source import Source
from scripts.repair_broken_feeds import (
    DEACTIVATE,
    KNOWN_FIXES,
    apply_repairs,
    diagnose,
)

pytestmark = pytest.mark.asyncio

MECANIQUES = (
    "https://www.radiofrance.fr/franceculture/podcasts/mecaniques-du-complot.rss"
)
MECANIQUES_FIX = KNOWN_FIXES[MECANIQUES]


async def _fake_test_feed(client, name, url):
    # Seule la nouvelle URL Mécaniques probe OK (entries>0) ; tout le reste = 0.
    entries = 5 if url == MECANIQUES_FIX else 0
    return {
        "http_status": 200,
        "entries_count": entries,
        "status": "ok",
        "error": None,
    }


def make_source(feed_url: str, name: str, **kw) -> Source:
    defaults = {
        "id": uuid4(),
        "name": name,
        "url": "https://media.test",
        "feed_url": feed_url,
        "type": SourceType.ARTICLE,
        "theme": "society",
        "is_active": True,
        "is_curated": True,
        "bias_stance": BiasStance.UNKNOWN,
        "reliability_score": ReliabilityScore.UNKNOWN,
        "bias_origin": BiasOrigin.CURATED,
    }
    defaults.update(kw)
    return Source(**defaults)


async def _seed_allowlist(session) -> None:
    session.add(make_source(MECANIQUES, "Mécaniques du Complot"))
    for url, name in DEACTIVATE.items():
        session.add(make_source(url, name))
    await session.commit()


async def _is_active(session, feed_url: str) -> bool:
    r = await session.execute(
        text("SELECT is_active FROM sources WHERE feed_url = :f"), {"f": feed_url}
    )
    return r.scalar_one()


async def _feed_url_of(session, name: str) -> str:
    r = await session.execute(
        text("SELECT feed_url FROM sources WHERE name = :n"), {"n": name}
    )
    return r.scalar_one()


# --------------------------------------------------------------------------- #
# diagnose : assignation des actions + dry-run sans mutation
# --------------------------------------------------------------------------- #


async def test_diagnose_assigns_actions(db_session, monkeypatch):
    monkeypatch.setattr(rbf, "test_feed", _fake_test_feed)
    await _seed_allowlist(db_session)

    report = await diagnose(db_session, client=None)
    by_url = {e["feed_url"]: e for e in report}

    assert by_url[MECANIQUES]["action"] == "repair"
    assert by_url[MECANIQUES]["new_feed_url"] == MECANIQUES_FIX
    for url in DEACTIVATE:
        assert by_url[url]["action"] == "deactivate"

    # Dry-run (diagnose seul) : aucune mutation.
    assert await _is_active(db_session, next(iter(DEACTIVATE))) is True
    assert await _feed_url_of(db_session, "Mécaniques du Complot") == MECANIQUES


# --------------------------------------------------------------------------- #
# apply : réparation + désactivation
# --------------------------------------------------------------------------- #


async def test_apply_repairs_and_deactivates(db_session, monkeypatch):
    monkeypatch.setattr(rbf, "test_feed", _fake_test_feed)
    await _seed_allowlist(db_session)

    report = await diagnose(db_session, client=None)
    counts = await apply_repairs(db_session, report)

    assert counts == {"repaired": 1, "deactivated": 6}

    # Mécaniques : feed_url réparé, source toujours active + présente.
    assert await _feed_url_of(db_session, "Mécaniques du Complot") == MECANIQUES_FIX
    assert await _is_active(db_session, MECANIQUES_FIX) is True

    # Les 6 : désactivées mais conservées (pas de delete, follows intacts).
    for url in DEACTIVATE:
        assert await _is_active(db_session, url) is False
        r = await db_session.execute(
            text("SELECT count(*) FROM sources WHERE feed_url = :f"), {"f": url}
        )
        assert r.scalar_one() == 1


# --------------------------------------------------------------------------- #
# Idempotence
# --------------------------------------------------------------------------- #


async def test_rerun_is_noop(db_session, monkeypatch):
    monkeypatch.setattr(rbf, "test_feed", _fake_test_feed)
    await _seed_allowlist(db_session)

    report = await diagnose(db_session, client=None)
    await apply_repairs(db_session, report)

    # 2e passe : Mécaniques a une nouvelle feed_url (hors allowlist) -> non re-fetchée.
    # Les 6 sont déjà inactives -> action "already_inactive" (no-op).
    report2 = await diagnose(db_session, client=None)
    by_url2 = {e["feed_url"]: e for e in report2}
    assert MECANIQUES not in by_url2
    for url in DEACTIVATE:
        assert by_url2[url]["action"] == "already_inactive"

    counts2 = await apply_repairs(db_session, report2)
    assert counts2 == {"repaired": 0, "deactivated": 0}
