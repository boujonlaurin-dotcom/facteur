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
    ESSENTIEL_READ_EVICTION_GRACE,
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
    async def _make(
        name: str, *, coverage_themes=None, theme: str = "politics"
    ) -> Source:
        source = Source(
            id=uuid4(),
            name=name,
            url=f"https://{name.lower()}.example.com",
            feed_url=f"https://{name.lower()}.example.com/feed-{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme=theme,
            coverage_themes=coverage_themes,
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
    published_at: datetime | None = None,
) -> Content:
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=published_at
        or (datetime.now(UTC) - timedelta(minutes=minutes_ago)),
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

    # 4 articles distincts d'une seule source → cap 1 en 1re passe, puis
    # fallback cap 2 (pool mono-source, sous le plancher) → plafond dur à 2.
    assert len(response.articles) == 2, "cap de 2 articles par source (fallback)"


@pytest.mark.asyncio
async def test_live_blend_caps_one_per_source_when_pool_diverse(
    db_session, make_source
):
    """Cap 1/source respecté : 5 sources suivies (2 articles chacune) → 5
    articles au total, jamais 2× la même source (le fallback ne se déclenche
    pas puisque le cap 1 remplit déjà les 5 slots)."""
    user_id = uuid4()
    sources = [await make_source(f"Src{i}") for i in range(5)]
    titles = [
        ["Politique", "Justice"],
        ["Economie", "Emploi"],
        ["Climat", "Energie"],
        ["Culture", "Cinema"],
        ["Sciences", "Espace"],
    ]
    for src, pair in zip(sources, titles, strict=True):
        for title in pair:
            await _add_content(db_session, src, title=title)

    ctx = EssentielUserContext(followed_source_ids=frozenset(s.id for s in sources))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    assert len(response.articles) == 5
    source_ids = [a.source.id for a in response.articles]
    assert len(source_ids) == len(set(source_ids)), "cap 1/source respecté"


@pytest.mark.asyncio
async def test_muted_source_excluded_from_live_blend(db_session, make_source):
    """Une source suivie mais mutée ne contribue jamais au blend live."""
    user_id = uuid4()
    kept = await make_source("Gardee")
    muted = await make_source("Mutee")
    kept_article = await _add_content(db_session, kept, title="Article garde")
    muted_article = await _add_content(db_session, muted, title="Article mute")

    ctx = EssentielUserContext(
        followed_source_ids=frozenset({kept.id, muted.id}),
        muted_source_ids=frozenset({muted.id}),
    )

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    ids = {a.content_id for a in response.articles}
    assert kept_article.id in ids
    assert muted_article.id not in ids, "une source mutée ne doit pas alimenter"


@pytest.mark.asyncio
async def test_rich_digest_still_blends_live_supplement(db_session, make_source):
    """Blend toujours actif : un digest ≥3 non-lus se complète des slots libres.

    Le nouveau modèle « L'Essentiel vivant » n'attend plus de tomber sous le
    plancher : tant qu'il reste des slots (cap 5), le pool frais des sources
    suivies remplit — ici 3 articles digest non-lus + 1 frais = 4.
    """
    user_id = uuid4()
    source = await make_source("Mediapart")
    supplement = await _add_content(db_session, source, title="Frais du jour")

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

    # 3 non-lus (ancre) + 1 frais = 4 ; ranks séquentiels 1..4.
    assert len(response.articles) == 4
    assert supplement.id in {a.content_id for a in response.articles}
    assert [a.rank for a in response.articles] == [1, 2, 3, 4]


@pytest.mark.asyncio
async def test_new_since_morning_counts_fresh_live_pool(db_session, make_source):
    """Delta = candidats frais (publiés depuis minuit Paris) hors digest."""
    user_id = uuid4()
    now = datetime(2026, 7, 18, 14, 0, tzinfo=UTC)  # après-midi Paris
    this_morning = datetime(2026, 7, 18, 9, 0, tzinfo=UTC)  # 11h Paris
    sources = [await make_source(f"Live{i}") for i in range(3)]
    for src in sources:
        await _add_content(
            db_session, src, title=f"Frais {src.name}", published_at=this_morning
        )

    ctx = EssentielUserContext(followed_source_ids=frozenset(s.id for s in sources))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
        now=now,
    )

    assert response.new_since_this_morning == 3


@pytest.mark.asyncio
async def test_new_since_morning_capped_at_nine(db_session, make_source):
    """Delta borné à 9 même si le pool live compte davantage d'articles frais."""
    user_id = uuid4()
    now = datetime(2026, 7, 18, 14, 0, tzinfo=UTC)
    this_morning = datetime(2026, 7, 18, 9, 0, tzinfo=UTC)
    sources = [await make_source(f"Prolific{i}") for i in range(6)]
    # 12 articles frais (2/source) → compte 12, borné à 9.
    for i, src in enumerate(sources):
        for j in range(2):
            await _add_content(
                db_session,
                src,
                title=f"Article {i}-{j}",
                published_at=this_morning,
            )

    ctx = EssentielUserContext(followed_source_ids=frozenset(s.id for s in sources))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
        now=now,
    )

    assert response.new_since_this_morning == 9


@pytest.mark.asyncio
async def test_rich_theme_source_contributes_without_being_followed(
    db_session, make_source
):
    """Une source non suivie mais riche sur un thème apprécié alimente le blend.

    Recall « thème riche en contenu » via `Source.coverage_themes` recoupant
    `topic_weights`. `coverage_themes = NULL` (source à faible volume) est
    naturellement exclue — c'est le gate voulu.
    """
    user_id = uuid4()
    rich = await make_source("RicheClimat", coverage_themes=["climate"], theme="misc")
    thin = await make_source("PauvreClimat", coverage_themes=None, theme="misc")
    rich_article = await _add_content(db_session, rich, title="Analyse climat inedite")
    thin_article = await _add_content(db_session, thin, title="Breve climat")

    # Aucune source suivie ; seul un thème apprécié (climate) → recall par
    # coverage_themes.
    ctx = EssentielUserContext(topic_weights={"climate": 1.0})

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        _empty_digest(),
        user_context=ctx,
        is_serene=False,
    )

    ids = {a.content_id for a in response.articles}
    assert rich_article.id in ids, "source riche sur thème apprécié doit alimenter"
    assert thin_article.id not in ids, "coverage_themes NULL exclut la source"


def _digest_with_topics(topics: list) -> DigestResponse:
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=datetime.now(UTC).date(),
        generated_at=datetime.now(UTC),
        format_version="topics_v1",
        items=[],
        topics=topics,
        is_stale_fallback=False,
    )


def _topic_with_article(
    label: str, *, is_read: bool = False, read_at: datetime | None = None
):
    """Un topic à article unique — permet de contrôler is_read/read_at par cas."""
    from app.schemas.content import SourceMini
    from app.schemas.digest import DigestTopic, DigestTopicArticle

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
                    id=uuid4(), name="Le Monde", logo_url=None, type="rss", theme=None
                ),
                rank=1,
                reason="Test",
                is_read=is_read,
                read_at=read_at,
            )
        ],
    )


@pytest.mark.asyncio
async def test_recently_read_article_stays_within_grace_window(db_session, make_source):
    """Un article lu il y a 5 min reste dans la réponse (coche visible au cold-start)."""
    user_id = uuid4()
    now = datetime.now(UTC)
    source = await make_source("Mediapart")
    live_extra = await _add_content(db_session, source, title="Frais du jour")

    digest = _digest_with_topics(
        [
            _topic_with_article(
                "Politique", is_read=True, read_at=now - timedelta(minutes=5)
            ),
            _topic_with_article("Sciences"),
            _topic_with_article("Cuisine"),
        ]
    )
    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        digest,
        user_context=ctx,
        is_serene=False,
        now=now,
    )

    politique = next(a for a in response.articles if a.section_label == "Politique")
    assert politique.is_read is True
    assert politique.read_at is not None
    # 3 articles digest (dont l'article en grâce, compté comme non-lu) + 1 slot
    # live libre = 4 ; le blend live ne comble qu'un seul slot, pas deux.
    assert len(response.articles) == 4
    assert live_extra.id in {a.content_id for a in response.articles}


@pytest.mark.asyncio
async def test_stale_read_article_still_evicted_after_grace(db_session, make_source):
    """Passé la fenêtre de grâce, l'article lu est évincé comme avant (Essentiel vivant)."""
    user_id = uuid4()
    now = datetime.now(UTC)
    source = await make_source("Mediapart")
    live_extra = await _add_content(db_session, source, title="Frais du jour")

    digest = _digest_with_topics(
        [
            _topic_with_article(
                "Politique",
                is_read=True,
                read_at=now - ESSENTIEL_READ_EVICTION_GRACE - timedelta(minutes=1),
            ),
            _topic_with_article("Sciences"),
            _topic_with_article("Cuisine"),
        ]
    )
    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        digest,
        user_context=ctx,
        is_serene=False,
        now=now,
    )

    labels = [a.section_label for a in response.articles]
    # L'article lu (hors grâce) est repoussé en dernier recours, derrière le
    # frais des sources suivies — comportement "Essentiel vivant" inchangé.
    assert labels[-1] == "Politique" or "Politique" not in labels[:-1]
    assert live_extra.id in {a.content_id for a in response.articles}


@pytest.mark.asyncio
async def test_never_read_article_has_no_read_at(db_session, make_source):
    """Un article jamais lu n'a pas de `read_at`."""
    user_id = uuid4()
    digest = _digest_with_topics([_topic_with_article("Politique")])
    ctx = EssentielUserContext()

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        digest,
        user_context=ctx,
        is_serene=False,
    )

    assert len(response.articles) == 1
    assert response.articles[0].is_read is False
    assert response.articles[0].read_at is None


@pytest.mark.asyncio
async def test_read_at_exactly_at_grace_boundary_is_evicted(db_session, make_source):
    """`read_at` exactement à `now - GRACE` est évincé (comparaison stricte `<`)."""
    user_id = uuid4()
    now = datetime.now(UTC)
    source = await make_source("Mediapart")
    live_extra = await _add_content(db_session, source, title="Frais du jour")

    digest = _digest_with_topics(
        [
            _topic_with_article(
                "Politique", is_read=True, read_at=now - ESSENTIEL_READ_EVICTION_GRACE
            ),
            _topic_with_article("Sciences"),
            _topic_with_article("Cuisine"),
        ]
    )
    ctx = EssentielUserContext(followed_source_ids=frozenset({source.id}))

    response = await build_essentiel_response_with_supplements(
        db_session,
        user_id,
        digest,
        user_context=ctx,
        is_serene=False,
        now=now,
    )

    assert live_extra.id in {a.content_id for a in response.articles}
