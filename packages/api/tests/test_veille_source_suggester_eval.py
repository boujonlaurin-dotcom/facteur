"""Tests structurels du SourceSuggester sur 10 fixtures de veilles types.

Pour chaque fixture (theme + topics + purpose + brief), on stub le LLM avec une
réponse canned représentative (12 candidats dont 2 doublons de domaine), puis
on vérifie que le pipeline produit une liste rankée propre :

- count > 0
- chaque `theme` ∈ `_ALLOWED_SOURCE_THEMES`
- URLs parseables (host non null)
- pas de doublon par domaine racine (`_root_domain`)
- résultats triés par `relevance_score` desc
- `is_already_followed` cohérent avec un user fixture pré-suivant 1 source

Pas de LLM judge, pas d'appel réel — couverture structurelle uniquement.
"""

import json
from pathlib import Path
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.services.veille.source_suggester import (
    _ALLOWED_SOURCE_THEMES,
    SourceSuggester,
    _root_domain,
)

_FIXTURES_PATH = Path(__file__).parent / "fixtures" / "veille_eval_cases.json"
_CASES = json.loads(_FIXTURES_PATH.read_text())


def _canned_candidates() -> list[dict]:
    """12 candidats plausibles dont 2 doublons de domaine (foo.example.com)."""
    return [
        {
            "name": "Le Grand Continent",
            "url": "https://legrandcontinent.example.com",
            "why": "Analyses géopolitiques de fond",
            "relevance_score": 0.95,
        },
        {
            "name": "Mediapart",
            "url": "https://mediapart.example.com",
            "why": "Investigations indépendantes",
            "relevance_score": 0.9,
        },
        {
            "name": "Foo Hebdo",
            "url": "https://foo.example.com",
            "why": "Hebdo généraliste",
            "relevance_score": 0.6,
        },
        {
            "name": "Foo Plus",
            "url": "https://www.foo.example.com/plus",
            "why": "Version premium du même éditeur",
            "relevance_score": 0.85,
        },
        {
            "name": "Alternatives Économiques",
            "url": "https://alternatives-eco.example.com",
            "why": "Économie et société",
            "relevance_score": 0.8,
        },
        {
            "name": "Les Jours",
            "url": "https://lesjours.example.com",
            "why": "Obsessions long format",
            "relevance_score": 0.78,
        },
        {
            "name": "Reporterre",
            "url": "https://reporterre.example.com",
            "why": "Écologie et luttes",
            "relevance_score": 0.75,
        },
        {
            "name": "AOC",
            "url": "https://aoc.example.com",
            "why": "Tribunes d'auteurs",
            "relevance_score": 0.7,
        },
        {
            "name": "Le Monde Diplomatique",
            "url": "https://mondediplo.example.com",
            "why": "Mensuel d'analyse",
            "relevance_score": 0.68,
        },
        {
            "name": "Brut",
            "url": "https://brut.example.com",
            "why": "Vidéos courtes",
            "relevance_score": 0.55,
        },
        {
            "name": "Konbini",
            "url": "https://konbini.example.com",
            "why": "Pop culture",
            "relevance_score": 0.5,
        },
        {
            "name": "Heidi News",
            "url": "https://heidi-news.example.com",
            "why": "Suisse — sciences et climat",
            "relevance_score": 0.65,
        },
    ]


@pytest_asyncio.fixture
async def eval_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Eval User",
        onboarding_completed=True,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


@pytest_asyncio.fixture
async def pre_followed_source(db_session, eval_user):
    """Source pré-suivie par l'user — pour vérifier `is_already_followed=True`
    quand le LLM la renvoie dans ses candidats."""
    # `feed_url` doit matcher exactement ce que `_detect_response_factory`
    # produira pour cette URL, sinon le hydrate_or_ingest crée une 2e row.
    src = Source(
        id=uuid4(),
        name="Mediapart",
        url="https://mediapart.example.com",
        feed_url="https://mediapart.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(src)
    db_session.add(
        UserSource(
            id=uuid4(),
            user_id=eval_user.user_id,
            source_id=src.id,
        )
    )
    await db_session.commit()
    return src


def _detect_response_factory():
    """Pour chaque URL, renvoie un feed_url unique stable (basé sur l'URL)."""
    from app.services.rss_parser import DetectedFeed

    async def _detect(url: str) -> DetectedFeed:
        feed_url = f"{url.rstrip('/')}/feed.xml"
        return DetectedFeed(
            feed_url=feed_url,
            title=url,
            description=f"{url} — auto-detected",
            feed_type="rss",
            logo_url=None,
            entries=[],
        )

    return _detect


@pytest.mark.parametrize("case", _CASES, ids=[c["id"] for c in _CASES])
async def test_eval_case_structural(db_session, eval_user, pre_followed_source, case):
    """Pour chaque fixture, vérifie les invariants structurels."""
    # Pour les fixtures society/economy etc., on doit aligner le theme du
    # pre_followed_source car `_persist_detected` réutilise sa row si la
    # feed_url match. On utilise un user secondaire ici via
    # excluded_source_ids pour éviter la pollution croisée — mais on garde
    # la row de mediapart.
    llm = AsyncMock()
    llm.is_ready = True
    llm.chat_json = AsyncMock(return_value={"sources": _canned_candidates()})
    suggester = SourceSuggester(llm=llm)

    with patch(
        "app.services.veille.source_suggester.RSSParser.detect",
        new=AsyncMock(side_effect=_detect_response_factory()),
    ):
        result = await suggester.suggest_sources(
            session=db_session,
            user_id=eval_user.user_id,
            theme_id=case["theme_id"],
            topic_labels=case["topic_labels"],
            purpose=case.get("purpose"),
            editorial_brief=case.get("editorial_brief"),
        )

    # 1. Count > 0
    assert len(result.sources) > 0, f"{case['id']}: empty result"

    # 2. Theme valide
    for s in result.sources:
        assert s.theme in _ALLOWED_SOURCE_THEMES, (
            f"{case['id']}: invalid theme {s.theme}"
        )

    # 3. URLs parseables
    from urllib.parse import urlparse

    for s in result.sources:
        host = urlparse(s.url).hostname
        assert host, f"{case['id']}: url not parseable {s.url}"

    # 4. Pas de doublon par domaine racine
    domains = [_root_domain(s.url) for s in result.sources]
    assert len(domains) == len(set(domains)), (
        f"{case['id']}: duplicate domain in {domains}"
    )

    # 5. Tri par relevance_score desc
    scores = [s.relevance_score or 0.0 for s in result.sources]
    assert scores == sorted(scores, reverse=True), (
        f"{case['id']}: not sorted desc: {scores}"
    )

    # 6. is_already_followed cohérent : la row Mediapart pré-suivie sort
    #    avec True (le LLM la renvoie dans ses candidats).
    mediapart_items = [s for s in result.sources if "mediapart.example.com" in s.url]
    assert len(mediapart_items) == 1
    assert mediapart_items[0].is_already_followed is True

    # Toutes les autres sources NE sont PAS suivies par eval_user.
    other_items = [s for s in result.sources if "mediapart.example.com" not in s.url]
    assert all(not s.is_already_followed for s in other_items)
