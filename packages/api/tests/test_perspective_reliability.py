"""PR B — indicateur de fiabilité par perspective.

Couvre la résolution lecture-seule de `Source.reliability_score` :
- `_extract_reliability_from_source` (source eager-loadée, sans DB) ;
- `resolve_reliability` (lookup DB par URL puis par nom, défaut "unknown") ;
- `_perspective_to_dict` porte bien le champ.

Aucune migration : la colonne `sources.reliability_score` existe déjà (Story 7.1).
"""

from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

from app.models.enums import BiasStance, ReliabilityScore, SourceType
from app.models.source import Source
from app.routers.contents import _perspective_to_dict
from app.services.perspective_service import Perspective, PerspectiveService


async def _make_source(
    db_session,
    *,
    name: str,
    url: str,
    reliability: ReliabilityScore,
) -> Source:
    src = Source(
        id=uuid4(),
        name=name,
        url=url,
        feed_url=f"https://feed.example/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
        bias_stance=BiasStance.UNKNOWN,
        reliability_score=reliability,
    )
    db_session.add(src)
    await db_session.commit()
    return src


# ── Unités pures (sans DB) ──────────────────────────────────────────────────


def test_extract_reliability_from_source_reads_value():
    src = SimpleNamespace(reliability_score=SimpleNamespace(value="high"))
    svc = PerspectiveService()
    assert svc._extract_reliability_from_source(src) == "high"


def test_extract_reliability_from_source_defaults_unknown():
    svc = PerspectiveService()
    assert svc._extract_reliability_from_source(None) == "unknown"
    assert (
        svc._extract_reliability_from_source(SimpleNamespace(reliability_score=None))
        == "unknown"
    )


def test_perspective_to_dict_carries_reliability():
    p = Perspective(
        title="Titre",
        url="https://ex.com/a",
        source_name="Le Monde",
        source_domain="lemonde.fr",
        bias_stance="center",
        reliability_score="high",
    )
    d = _perspective_to_dict(p)
    assert d["reliability_score"] == "high"


def test_perspective_to_dict_reliability_defaults_none():
    p = Perspective(
        title="Titre",
        url="https://ex.com/a",
        source_name="X",
        source_domain="x.com",
        bias_stance="unknown",
    )
    assert _perspective_to_dict(p)["reliability_score"] is None


async def test_resolve_reliability_no_db_returns_unknown():
    svc = PerspectiveService()  # pas de session → branche dégradée
    assert await svc.resolve_reliability("lemonde.fr") == "unknown"


# ── Intégration DB ──────────────────────────────────────────────────────────


async def test_resolve_reliability_by_url(db_session):
    await _make_source(
        db_session,
        name="Le Monde",
        url="https://lemonde.fr",
        reliability=ReliabilityScore.HIGH,
    )
    svc = PerspectiveService(db=db_session)
    assert await svc.resolve_reliability("lemonde.fr") == "high"


async def test_resolve_reliability_by_name_fallback(db_session):
    await _make_source(
        db_session,
        name="Source Douteuse",
        url="https://douteux.example",
        reliability=ReliabilityScore.LOW,
    )
    svc = PerspectiveService(db=db_session)
    # Domaine inconnu → fallback fuzzy par nom.
    assert (
        await svc.resolve_reliability("introuvable.test", source_name="Source Douteuse")
        == "low"
    )


async def test_resolve_reliability_unknown_when_absent(db_session):
    svc = PerspectiveService(db=db_session)
    assert await svc.resolve_reliability("inexistant.test") == "unknown"
