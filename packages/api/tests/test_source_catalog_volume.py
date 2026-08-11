"""Tests des signaux de reco exposés sur le catalogue (`GET /sources`).

Le recommander d'onboarding tourne **100 % côté client** : tout ce qu'il ne voit
pas dans `SourceResponse` est un signal mort. Ce module verrouille les deux
familles de signaux qu'il consomme :

- `articles_30d` (biais « sources productives ») : enrichi par un unique GROUP BY
  batché, jamais d'appel par source ;
- les inputs de pertinence thématique (`secondary_themes`, `granular_topics`,
  `source_tier`, `coverage_themes`) : recopiés depuis la ligne `Source` déjà
  chargée. `coverage_themes` (couverture réellement publiée) permet au client de
  reléguer une généraliste diluée hors des intérêts déclarés.

Couvre :
- `get_all_sources` : `articles_30d` peuplé pour les curées actives, fenêtre 30 j
  respectée (un article à 40 j exclu), 0 pour une curée sans contenu récent ;
- `get_curated_sources` : même enrichissement ;
- sérialisation des signaux thématiques, `None` inclus (couverture inconnue).
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.routers.sources import _source_to_response
from app.services.source_service import SourceService


def _curated_source(name: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )


def _content(source_id, *, days_ago: int) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="Article",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        theme="society",
    )


@pytest.mark.asyncio
async def test_get_all_sources_populates_articles_30d(db_session: AsyncSession):
    active = _curated_source("Active Source")
    quiet = _curated_source("Quiet Source")
    db_session.add_all([active, quiet])
    await db_session.flush()

    # 3 articles récents + 1 hors fenêtre (40 j) pour 'active' ; rien pour 'quiet'.
    for d in (0, 5, 20):
        db_session.add(_content(active.id, days_ago=d))
    db_session.add(_content(active.id, days_ago=40))
    await db_session.commit()

    catalog = await SourceService(db_session).get_all_sources(str(uuid4()))
    by_name = {s.name: s for s in catalog.curated}

    assert by_name["Active Source"].articles_30d == 3  # le 40 j est exclu
    assert by_name["Quiet Source"].articles_30d == 0


@pytest.mark.asyncio
async def test_catalog_serializes_relevance_signals(db_session: AsyncSession):
    """Les inputs du scoring client sont sérialisés tels quels (ou `None`)."""
    rich = _curated_source("Généraliste Diluée")
    rich.secondary_themes = ["politics", "economy"]
    rich.granular_topics = ["elections", "democracy"]
    rich.source_tier = "deep"
    rich.coverage_themes = ["sport", "culture"]

    thin = _curated_source("Petite Source Récente")  # aucun signal dérivé
    db_session.add_all([rich, thin])
    await db_session.commit()

    catalog = await SourceService(db_session).get_all_sources(str(uuid4()))
    by_name = {s.name: s for s in catalog.curated}

    got = by_name["Généraliste Diluée"]
    assert got.coverage_themes == ["sport", "culture"]
    assert got.secondary_themes == ["politics", "economy"]
    assert got.granular_topics == ["elections", "democracy"]
    assert got.source_tier == "deep"

    # Signaux non dérivés : `None` (le client traite ça comme « inconnu » et ne
    # pénalise jamais la source sur cette absence).
    quiet = by_name["Petite Source Récente"]
    assert quiet.coverage_themes is None
    assert quiet.granular_topics is None
    assert quiet.source_tier == "mainstream"


def test_router_converter_serializes_the_same_relevance_signals():
    """`_source_to_response` ne doit pas dériver du builder du service.

    Deux convertisseurs `Source -> SourceResponse` coexistent : celui du service
    (`GET /sources`) et celui du routeur (liste curée, suggestions par thème,
    fiche source). Un signal ajouté d'un seul côté rend la même source
    différente selon l'endpoint — et le client conclut « couverture inconnue »
    là où la donnée existe. Ce test verrouille la parité.
    """
    s = _curated_source("Généraliste Diluée")
    s.secondary_themes = ["politics"]
    s.granular_topics = ["elections"]
    s.source_tier = "deep"
    s.coverage_themes = ["sport", "culture"]

    got = _source_to_response(s)

    assert got.coverage_themes == ["sport", "culture"]
    assert got.secondary_themes == ["politics"]
    assert got.granular_topics == ["elections"]
    assert got.source_tier == "deep"


@pytest.mark.asyncio
async def test_get_curated_sources_populates_articles_30d(db_session: AsyncSession):
    src = _curated_source("Curated Source")
    db_session.add(src)
    await db_session.flush()
    for d in (1, 2):
        db_session.add(_content(src.id, days_ago=d))
    await db_session.commit()

    curated = await SourceService(db_session).get_curated_sources()
    match = next(s for s in curated if s.name == "Curated Source")
    assert match.articles_30d == 2
