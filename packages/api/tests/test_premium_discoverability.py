"""Découvrabilité des sources payantes : config curée + fallback générique.

Couvre la résolution `PremiumConnectionResponse.from_source`, le signal
`has_paywall` exposé au mobile, et le helper `domain_key`.
"""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import SourceType
from app.models.source import Source
from app.schemas.source import PremiumConnectionResponse
from app.services.premium_curated_sources import (
    PREMIUM_CURATED_MAP,
    domain_key,
    is_paywalled_source,
)
from app.services.source_service import SourceService

MAP = PREMIUM_CURATED_MAP


def _stub(url=None, premium_connection_config=None, paywall_config=None):
    return SimpleNamespace(
        url=url,
        premium_connection_config=premium_connection_config,
        paywall_config=paywall_config,
    )


# ─── domain_key ───────────────────────────────────────────────────


def test_domain_key_normalizes_subdomains():
    assert domain_key("https://www.lemonde.fr/article/x") == "lemonde.fr"
    assert domain_key("https://m.lemonde.fr/") == "lemonde.fr"
    assert domain_key("https://abonnes.lemonde.fr") == "lemonde.fr"
    assert domain_key("https://LEMONDE.fr/UP") == "lemonde.fr"
    assert domain_key("lemonde.fr") == "lemonde.fr"


def test_domain_key_handles_multipart_tld_and_invalids():
    assert domain_key("https://www.theguardian.co.uk/news") == "theguardian.co.uk"
    assert domain_key(None) == ""
    assert domain_key("   ") == ""
    assert domain_key("https://") == ""


# ─── from_source : priorité config > map > générique > None ────────


def test_from_source_explicit_config_beats_curated_map():
    # url lemonde.fr (présente dans la map) mais config explicite → config gagne.
    src = _stub(
        url="https://www.lemonde.fr/article",
        premium_connection_config={
            "enabled": True,
            "login_url": "https://explicit.example/login",
            "test_url": "https://explicit.example/test",
        },
    )
    resp = PremiumConnectionResponse.from_source(src, curated_map=MAP)
    assert resp is not None
    assert resp.login_url == "https://explicit.example/login"
    assert resp.is_generic is False


def test_from_source_curated_map_is_not_generic():
    src = _stub(url="https://www.lemonde.fr/section/x")
    resp = PremiumConnectionResponse.from_source(src, curated_map=MAP)
    assert resp is not None
    assert resp.is_generic is False
    assert resp.login_url == MAP["lemonde.fr"]["login_url"]
    assert resp.test_url == MAP["lemonde.fr"]["test_url"]


@pytest.mark.parametrize(
    "url,domain",
    [
        ("https://www.nytimes.com/2026/01/01/world/x.html", "nytimes.com"),
        ("https://theathletic.com/123/article/", "theathletic.com"),
        ("https://www.washingtonpost.com/world/x/", "washingtonpost.com"),
        ("https://www.ft.com/content/abc", "ft.com"),
        ("https://www.economist.com/leaders/x", "economist.com"),
        ("https://www.wsj.com/articles/x", "wsj.com"),
    ],
)
def test_from_source_english_titles_are_curated_not_generic(url, domain):
    """Les grands titres EN ajoutés à la map (PO) exposent une connexion curée."""
    src = _stub(url=url)
    assert is_paywalled_source(src) is True
    resp = PremiumConnectionResponse.from_source(src, curated_map=MAP)
    assert resp is not None
    assert resp.is_generic is False
    assert resp.login_url == MAP[domain]["login_url"]
    assert resp.test_url == MAP[domain]["test_url"]


def test_from_source_paywall_config_only_is_generic_using_source_url():
    src = _stub(
        url="https://unknown-paper.example/news/x",
        paywall_config={"keywords": ["réservé aux abonnés"]},
    )
    resp = PremiumConnectionResponse.from_source(src, curated_map=MAP)
    assert resp is not None
    assert resp.is_generic is True
    assert resp.login_url == "https://unknown-paper.example/news/x"
    assert resp.test_url == resp.login_url


def test_from_source_disabled_config_blocks_curated_and_generic_fallback():
    curated = _stub(
        url="https://www.lemonde.fr/section/x",
        premium_connection_config={"enabled": False},
    )
    assert PremiumConnectionResponse.from_source(curated, curated_map=MAP) is None

    generic = _stub(
        url="https://unknown-paper.example/news/x",
        premium_connection_config={"enabled": False},
        paywall_config={"keywords": ["réservé aux abonnés"]},
    )
    assert PremiumConnectionResponse.from_source(generic, curated_map=MAP) is None


def test_from_source_free_source_returns_none():
    src = _stub(url="https://free-paper.example/")
    assert PremiumConnectionResponse.from_source(src, curated_map=MAP) is None


def test_from_source_paywalled_but_non_http_url_returns_none():
    src = _stub(url="ftp://weird-host", paywall_config={"keywords": ["x"]})
    assert PremiumConnectionResponse.from_source(src, curated_map=MAP) is None


# ─── is_paywalled_source ──────────────────────────────────────────


def test_is_paywalled_source_signals():
    assert is_paywalled_source(_stub(url="https://www.lemonde.fr/")) is True
    assert (
        is_paywalled_source(_stub(url="https://x.example/", paywall_config={"k": 1}))
        is True
    )
    assert is_paywalled_source(_stub(url="https://x.example/")) is False
    # premium_connection_config partiel ne suffit pas (faux signal).
    assert (
        is_paywalled_source(
            _stub(
                url="https://x.example/",
                premium_connection_config={"enabled": True},
            )
        )
        is False
    )


# ─── intégration service / DB ─────────────────────────────────────


@pytest.mark.asyncio
async def test_subscription_true_succeeds_for_generic_paywalled_source(
    db_session: AsyncSession,
):
    """Le 400 PremiumConnectionNotEnabled disparaît pour une source payante
    sans config explicite (fallback générique)."""
    source = Source(
        id=uuid4(),
        name="Generic Paywalled",
        url="https://generic-paper.example",
        feed_url=f"https://generic-paper.example/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
        paywall_config={"keywords": ["réservé aux abonnés"]},
    )
    db_session.add(source)
    await db_session.flush()

    response = await SourceService(db_session).update_source_subscription(
        str(uuid4()), str(source.id), True
    )

    assert response is not None
    assert response.has_subscription is True
    assert response.has_paywall is True
    assert response.premium_connection is not None
    assert response.premium_connection.is_generic is True


@pytest.mark.asyncio
async def test_curated_sources_expose_has_paywall(db_session: AsyncSession):
    map_source = Source(
        id=uuid4(),
        name="Le Monde",
        url="https://www.lemonde.fr",
        feed_url=f"https://www.lemonde.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
    )
    free_source = Source(
        id=uuid4(),
        name="Free Blog",
        url="https://free-blog.example",
        feed_url=f"https://free-blog.example/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
    )
    db_session.add_all([map_source, free_source])
    await db_session.flush()

    by_id = {r.id: r for r in await SourceService(db_session).get_curated_sources()}

    assert by_id[map_source.id].has_paywall is True
    assert by_id[map_source.id].premium_connection is not None
    assert by_id[map_source.id].premium_connection.is_generic is False
    assert (
        by_id[map_source.id].premium_connection.login_url
        == MAP["lemonde.fr"]["login_url"]
    )
    assert by_id[free_source.id].has_paywall is False
    assert by_id[free_source.id].premium_connection is None
