"""Tests de la carte de partage publique `GET /api/pages/a/{id}`.

Story partage.1 (PR 1). C'est la **seule surface d'injection HTML** du chantier
partage : les tests d'échappement et de validation de schéma sont volontairement
explicites plutôt que déduits d'un rendu global.
"""

import re
from datetime import UTC, datetime
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source


@pytest_asyncio.fixture
async def pages_client(db_session):
    """Client HTTP non authentifié (la page est publique) avec override db."""

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def make_content(db_session):
    """Fabrique un Content rattaché à une Source fraîche."""

    async def _make(**overrides):
        source = Source(
            id=uuid4(),
            name=overrides.pop("source_name", "Le Média Test"),
            url="https://media.example.com",
            feed_url=f"https://media.example.com/feed-{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
            is_curated=False,
        )
        content = Content(
            id=uuid4(),
            source_id=source.id,
            title=overrides.pop("title", "Un titre d'article"),
            url=overrides.pop("url", "https://media.example.com/article-1"),
            guid=str(uuid4()),
            published_at=datetime.now(UTC),
            content_type=ContentType.ARTICLE,
            description=overrides.pop("description", "Un résumé sobre."),
            thumbnail_url=overrides.pop("thumbnail_url", None),
        )
        db_session.add_all([source, content])
        await db_session.commit()
        return content

    return _make


@pytest.mark.asyncio
async def test_no_template_token_survives_rendering(pages_client, make_content):
    """Aucun `__TOKEN__` ne doit fuiter tel quel dans la page servie.

    Le template est substitué en une passe depuis un dict : un token ajouté au
    HTML mais oublié dans le dict se rendrait littéralement, sans casser aucune
    assertion ciblée. Ce test ferme cette classe d'oubli d'un coup, page 200
    comme page 404.
    """
    content = await make_content()

    for path in (f"/api/pages/a/{content.id}", "/api/pages/a/inconnu"):
        body = (await pages_client.get(path)).text
        assert not re.search(r"__[A-Z_]+__", body), path


@pytest.mark.asyncio
async def test_page_renders_open_graph_and_cta(pages_client, make_content):
    content = await make_content(
        title="Le titre partagé",
        description="Un résumé qui tient en une phrase.",
        thumbnail_url="https://cdn.example.com/img.jpg",
        source_name="Le Média Test",
    )

    resp = await pages_client.get(f"/api/pages/a/{content.id}")

    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert resp.headers["cache-control"] == "public, max-age=600"

    body = resp.text
    assert '<meta property="og:title" content="Le titre partagé">' in body
    assert (
        '<meta property="og:description" content="Un résumé qui tient en une phrase.">'
        in body
    )
    assert (
        f'<meta property="og:url" content="https://facteur.app/a/{content.id}">' in body
    )
    assert '<meta property="og:site_name" content="Facteur">' in body
    assert '<meta property="og:type" content="article">' in body
    assert (
        '<meta property="og:image" content="https://cdn.example.com/img.jpg">' in body
    )
    assert '<meta name="twitter:card" content="summary_large_image">' in body
    # Nom de la source, lien sortant et deep link app.
    assert "Le Média Test" in body
    assert 'href="https://media.example.com/article-1"' in body
    assert f"io.supabase.facteur://feed/content/{content.id}" in body
    # Page sans contenu original : ne pas l'indexer.
    assert '<meta name="robots" content="noindex, follow">' in body


@pytest.mark.asyncio
async def test_page_escapes_title_and_description(pages_client, make_content):
    content = await make_content(
        title='<script>alert("xss")</script>',
        description="<img src=x onerror=alert(1)> \" puis ' apostrophe",
    )

    body = (await pages_client.get(f"/api/pages/a/{content.id}")).text

    # Aucune balise injectée ne survit, ni dans le corps ni dans les attributs OG.
    assert "<script>alert" not in body
    assert "onerror=" not in body
    assert "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;" in body
    # Les balises de la description sont retirées, pas seulement échappées.
    assert "&lt;img" not in body


@pytest.mark.asyncio
async def test_page_rejects_javascript_scheme_in_article_url(
    pages_client, make_content
):
    content = await make_content(url="javascript:alert(1)")

    body = (await pages_client.get(f"/api/pages/a/{content.id}")).text

    assert "javascript:alert" not in body
    # Repli sur la home plutôt qu'un href actif hostile.
    assert 'href="https://facteur.app"' in body


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "thumbnail",
    [
        "javascript:alert(1)",
        "http://cdn.example.com/img.jpg",  # http : carte muette côté crawlers
        "/relative/img.jpg",
        None,
    ],
)
async def test_page_omits_og_image_when_thumbnail_unusable(
    pages_client, make_content, thumbnail
):
    content = await make_content(thumbnail_url=thumbnail)

    body = (await pages_client.get(f"/api/pages/a/{content.id}")).text

    assert "og:image" not in body
    assert "javascript:alert" not in body
    # Sans visuel, la carte texte simple s'affiche proprement.
    assert '<meta name="twitter:card" content="summary">' in body


@pytest.mark.asyncio
async def test_page_truncates_long_description(pages_client, make_content):
    content = await make_content(description="mot " * 200)

    body = (await pages_client.get(f"/api/pages/a/{content.id}")).text

    excerpt = body.split('<meta name="description" content="')[1].split('">')[0]
    assert len(excerpt) <= 201  # 200 caractères + le caractère de troncature
    assert excerpt.endswith("…")


@pytest.mark.asyncio
async def test_valid_ref_flows_into_store_links(pages_client, make_content):
    content = await make_content()

    body = (await pages_client.get(f"/api/pages/a/{content.id}?ref=ab12_CD")).text

    # Play : la query UTM complète part dans `referrer` (Install Referrer API).
    assert "referrer=utm_source%3Dapp%26utm_medium%3Dpartage_in_app" in body
    assert "ref%3Dab12_CD" in body
    # App Store : seul `ct` est une chaîne libre.
    assert "ct=partage_article_ab12_CD" in body
    assert f'content="https://facteur.app/a/{content.id}?ref=ab12_CD"' in body


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_ref", ["<script>", "a" * 40, "espace ici", ""])
async def test_invalid_ref_is_ignored_not_rejected(pages_client, make_content, bad_ref):
    content = await make_content()

    resp = await pages_client.get(f"/api/pages/a/{content.id}", params={"ref": bad_ref})

    # Un lien au `ref` tronqué doit rester une page qui s'affiche.
    assert resp.status_code == 200
    assert "ct=partage_article&" in resp.text  # campagne sans suffixe de ref
    assert "ref%3D" not in resp.text  # rien n'est reporté dans le referrer Play
    assert "<script>" not in resp.text.split("<script>\n(function")[0]


@pytest.mark.asyncio
async def test_unknown_id_returns_html_404(pages_client):
    resp = await pages_client.get(f"/api/pages/a/{uuid4()}")

    assert resp.status_code == 404
    assert resp.headers["content-type"].startswith("text/html")
    assert resp.headers["cache-control"] == "public, max-age=60"
    assert "Ce contenu n'est plus disponible" in resp.text


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_id", ["not-a-uuid", "123", "%3Cscript%3E"])
async def test_malformed_id_returns_html_404_not_422(pages_client, bad_id):
    """Un humain qui suit un lien tronqué doit voir une page, pas un JSON 422."""
    resp = await pages_client.get(f"/api/pages/a/{bad_id}")

    assert resp.status_code == 404
    assert resp.headers["content-type"].startswith("text/html")
