"""Tests de complétion de l'Essentiel depuis les sources suivies (plan QA).

Quand le digest produit moins de `ESSENTIEL_MIN_ARTICLES`, on complète avec des
articles frais des sources suivies/favorites, en excluant lus/masqués, et en
mode serein on ne garde que `Content.is_serene == True`. Si le total reste < 3,
le router renverra 202 (ici on vérifie le contrat du service).
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source
from app.schemas.digest import DigestResponse
from app.services.essentiel_service import (
    ESSENTIEL_MIN_ARTICLES,
    EssentielUserContext,
    build_essentiel_response_with_supplements,
)


def _empty_digest() -> DigestResponse:
    """Digest vide → 0 article issu du digest, force le chemin de complétion."""
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=datetime.now(UTC).date(),
        generated_at=datetime.now(UTC),
        format_version="topics_v1",
        items=[],
        topics=[],
        is_stale_fallback=False,
    )


@pytest_asyncio.fixture
async def make_source(db_session):
    async def _make(name: str) -> Source:
        source = Source(
            id=uuid4(),
            name=name,
            url=f"https://{name.lower()}.example.com",
            feed_url=f"https://{name.lower()}.example.com/feed-{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme="politics",
            is_active=True,
            is_curated=False,
        )
        db_session.add(source)
        await db_session.commit()
        return source

    return _make


async def _add_content(
    db,
    source: Source,
    *,
    title: str,
    is_serene=None,
    minutes_ago: int = 30,
    content_type: ContentType = ContentType.ARTICLE,
) -> Content:
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=datetime.now(UTC) - timedelta(minutes=minutes_ago),
        content_type=content_type,
        guid=str(uuid4()),
        is_serene=is_serene,
    )
    db.add(content)
    await db.commit()
    return content


@pytest.mark.asyncio
async def test_poor_digest_completed_from_followed_sources(db_session, make_source):
    """Digest vide + 3 sources suivies avec articles frais → 3 articles complétés."""
    user_id = uuid4()
    # Titres mono-mot distincts → pas de dédup par similarité de titre.
    titles = ["Politique", "Economie", "Climat"]
    sources = [await make_source(f"Src{i}") for i in range(3)]
    for src, title in zip(sources, titles, strict=True):
        await _add_content(db_session, src, title=title)

    ctx = EssentielUserContext(
        followed_source_ids=frozenset(s.id for s in sources),
    )

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    assert 3 <= len(response.articles) <= 5
    # Tous viennent des sources suivies → flag is_followed_source à True, ranks 1..N.
    assert all(a.is_followed_source for a in response.articles)
    assert [a.rank for a in response.articles] == list(
        range(1, len(response.articles) + 1)
    )


@pytest.mark.asyncio
async def test_serein_mode_excludes_non_serene_content(db_session, make_source):
    """En mode serein, seuls les contenus `is_serene == True` complètent."""
    user_id = uuid4()
    serene_titles = ["Sport", "Culture", "Sciences"]
    serene_sources = [await make_source(f"Calme{i}") for i in range(3)]
    for src, title in zip(serene_sources, serene_titles, strict=True):
        await _add_content(db_session, src, title=title, is_serene=True)
    anxious = await make_source("Anxiogene")
    anxious_content = await _add_content(
        db_session, anxious, title="Catastrophe", is_serene=False
    )

    ctx = EssentielUserContext(
        followed_source_ids=frozenset([*(s.id for s in serene_sources), anxious.id]),
    )

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=True,
    )

    assert len(response.articles) >= 3
    ids = {a.content_id for a in response.articles}
    assert anxious_content.id not in ids, "un contenu non-serein ne doit pas compléter"


@pytest.mark.asyncio
async def test_read_and_hidden_content_excluded(db_session, make_source):
    """Les contenus lus (CONSUMED) ou masqués sont écartés de la complétion."""
    user_id = uuid4()
    source = await make_source("Mediapart")
    read = await _add_content(db_session, source, title="Article deja lu")
    hidden = await _add_content(db_session, source, title="Article masque par moi")
    fresh = await _add_content(db_session, source, title="Article jamais vu")

    db_session.add(
        UserContentStatus(
            id=uuid4(),
            user_id=user_id,
            content_id=read.id,
            status=ContentStatus.CONSUMED,
        )
    )
    db_session.add(
        UserContentStatus(
            id=uuid4(),
            user_id=user_id,
            content_id=hidden.id,
            status=ContentStatus.UNSEEN,
            is_hidden=True,
        )
    )
    await db_session.commit()

    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    ids = {a.content_id for a in response.articles}
    assert read.id not in ids
    assert hidden.id not in ids
    assert fresh.id in ids


@pytest.mark.asyncio
async def test_no_admissible_supplement_stays_below_floor(db_session, make_source):
    """Sans complément admissible, le total reste < 3 (le router renverra 202)."""
    user_id = uuid4()
    source = await make_source("Mediapart")
    # Seul contenu : déjà lu → exclu.
    read = await _add_content(db_session, source, title="Tout est lu")
    db_session.add(
        UserContentStatus(
            id=uuid4(),
            user_id=user_id,
            content_id=read.id,
            status=ContentStatus.CONSUMED,
        )
    )
    await db_session.commit()

    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    assert len(response.articles) < ESSENTIEL_MIN_ARTICLES


@pytest.mark.asyncio
async def test_max_two_articles_per_source(db_session, make_source):
    """Diversité dure : au plus 2 articles d'une même source dans la complétion."""
    user_id = uuid4()
    source = await make_source("Mediapart")
    for title in ["Politique", "Economie", "Climat", "Sport"]:
        await _add_content(db_session, source, title=title)

    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    # 4 articles distincts d'une seule source → cap dur à 2.
    assert len(response.articles) == 2, "cap de 2 articles par source"


@pytest.mark.asyncio
async def test_rich_digest_skips_supplement_query(db_session, make_source):
    """Digest déjà ≥3 articles → pas de complétion (les sources suivies ignorées)."""
    user_id = uuid4()
    source = await make_source("Mediapart")
    supplement = await _add_content(db_session, source, title="Ne doit pas apparaitre")

    # Digest "riche" simulé via 3 articles supplémentaires injectés ? Ici on
    # vérifie surtout que si le digest fournit >= 3 articles, le contenu DB des
    # sources suivies n'est pas pioché. On construit un digest à 3 topics.
    from app.schemas.content import SourceMini
    from app.schemas.digest import DigestTopic, DigestTopicArticle

    def _topic(label: str) -> DigestTopic:
        return DigestTopic(
            topic_id=uuid4().hex,
            label=label,
            rank=1,
            reason="Test",
            theme=label.lower(),
            perspective_count=2,
            articles=[
                DigestTopicArticle(
                    content_id=uuid4(),
                    title=label,
                    url=f"https://example.com/{label.lower()}",
                    published_at=datetime.now(UTC),
                    source=SourceMini(
                        id=uuid4(),
                        name="Le Monde",
                        logo_url=None,
                        type="rss",
                        theme=None,
                    ),
                    rank=1,
                    reason="Test",
                )
            ],
        )

    digest = DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=datetime.now(UTC).date(),
        generated_at=datetime.now(UTC),
        format_version="topics_v1",
        items=[],
        topics=[_topic("Politique"), _topic("Sciences"), _topic("Cuisine")],
        is_stale_fallback=False,
    )

    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        digest,
        user_context=ctx,
        is_serene=False,
    )

    assert len(response.articles) == 3
    assert supplement.id not in {a.content_id for a in response.articles}
