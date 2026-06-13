"""Tests du feed veille curé par score (refonte curation).

Couvre le pipeline `fetch_veille_feed` : prefilter axes forts → scoring piliers
→ seuil → tri par score. Le thème macro est un signal faible (jamais dans le
prédicat) → un article « thème seul » n'entre jamais dans le pool.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, ReliabilityScore, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.services.veille.feed_filter import VeilleFilters, fetch_veille_feed
from app.services.veille.scoring_context import build_veille_scoring_context

pytestmark = pytest.mark.asyncio


def _now():
    return datetime.now(UTC)


@pytest_asyncio.fixture
async def user(db_session):
    u = UserProfile(user_id=uuid4(), display_name="scoring", onboarding_completed=True)
    db_session.add(u)
    await db_session.commit()
    return u


@pytest_asyncio.fixture
async def source(db_session):
    s = Source(
        id=uuid4(),
        name="Curated Tech",
        url="https://ct.example.com",
        feed_url=f"https://ct.example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
        reliability_score=ReliabilityScore.HIGH,
    )
    db_session.add(s)
    await db_session.commit()
    return s


async def _add_content(
    db_session,
    source,
    *,
    title,
    theme="tech",
    topics=None,
    description="",
    hours=2,
    reliability=None,
):
    c = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://ct.example.com/{uuid4()}",
        description=description,
        published_at=_now() - timedelta(hours=hours),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
        theme=theme,
        topics=topics or [],
    )
    db_session.add(c)
    await db_session.commit()
    return c


async def _make_config(
    db_session,
    user,
    *,
    theme_id="tech",
    topics=None,
    source_ids=None,
    global_keywords=None,
):
    """topics: list of (topic_id, label, [keywords]). source_ids/global_keywords lists."""
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user.user_id,
        theme_id=theme_id,
        theme_label=theme_id.capitalize(),
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.flush()

    for pos, (tid, label, kws) in enumerate(topics or []):
        topic = VeilleTopic(
            veille_config_id=cfg.id,
            topic_id=tid,
            label=label,
            kind="suggested",
            position=pos,
        )
        db_session.add(topic)
        await db_session.flush()
        for kpos, kw in enumerate(kws or []):
            db_session.add(
                VeilleKeyword(
                    veille_config_id=cfg.id,
                    veille_topic_id=topic.id,
                    keyword=kw,
                    position=kpos,
                )
            )

    for sid in source_ids or []:
        db_session.add(VeilleSource(veille_config_id=cfg.id, source_id=sid, kind="followed"))

    for kpos, kw in enumerate(global_keywords or []):
        db_session.add(
            VeilleKeyword(veille_config_id=cfg.id, keyword=kw, position=kpos)
        )

    await db_session.commit()
    return cfg


async def _titles(db_session, user):
    items, _ = await fetch_veille_feed(db_session, user.user_id, limit=20, offset=0)
    return [c.title for c, _axes, _group in items], items


async def test_theme_only_article_never_enters_pool(db_session, user, source):
    """Article matchant uniquement le thème macro → absent (prédicat sans thème)."""
    await _add_content(db_session, source, title="Topic AI", topics=["ai"])
    await _add_content(db_session, source, title="Theme Only", topics=["unrelated"])
    await _make_config(db_session, user, topics=[("ai", "IA", [])])

    titles, _ = await _titles(db_session, user)
    assert "Topic AI" in titles
    assert "Theme Only" not in titles


async def test_topic_outranks_keyword(db_session, user, source):
    """Thème + topic (>) thème + mot-clé : les deux présents, topic mieux classé."""
    await _add_content(db_session, source, title="Topic Match", topics=["ai"])
    await _add_content(
        db_session,
        source,
        title="Keyword Match transformers",
        topics=["other"],
        description="modèle transformers",
    )
    await _make_config(
        db_session,
        user,
        topics=[("ai", "IA", ["transformers"])],
    )

    titles, _ = await _titles(db_session, user)
    assert "Topic Match" in titles
    assert "Keyword Match transformers" in titles
    assert titles.index("Topic Match") < titles.index("Keyword Match transformers")


async def test_source_only_and_keyword_only_present(db_session, user, source):
    """Source-seule présente ; mot-clé-seul présent (valide le seuil)."""
    await _add_content(
        db_session, source, title="From Source", theme="economy", topics=["markets"]
    )
    await _make_config(db_session, user, source_ids=[source.id])
    titles, _ = await _titles(db_session, user)
    assert "From Source" in titles


async def test_keyword_only_present(db_session, user, source):
    await _add_content(
        db_session,
        source,
        title="Vélo électrique nouveau modèle",
        theme="society",
        topics=["mobility"],
        description="test du nouveau VAE",
    )
    await _make_config(db_session, user, global_keywords=["vélo"])
    titles, items = await _titles(db_session, user)
    assert "Vélo électrique nouveau modèle" in titles
    # items[i] = (content, axes, group) → axes en position 1.
    assert "keyword" in items[0][1]


async def test_weak_candidate_below_threshold_excluded(db_session, user):
    """Candidat faible (mot-clé, vieux, source basse fiabilité) < seuil → exclu."""
    weak_src = Source(
        id=uuid4(),
        name="Low",
        url="https://low.example.com",
        feed_url=f"https://low.example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="economy",
        is_active=True,
        is_curated=False,
        reliability_score=ReliabilityScore.LOW,
    )
    db_session.add(weak_src)
    await db_session.commit()
    await _add_content(
        db_session,
        weak_src,
        title="incident mineur vélo",
        theme="economy",
        topics=["misc"],
        hours=160,
    )
    await _make_config(db_session, user, global_keywords=["vélo"])
    titles, _ = await _titles(db_session, user)
    assert titles == []


async def test_excludes_hidden_seen_and_inactive(db_session, user, source):
    """Exclusions hidden/seen + is_active=False."""
    visible = await _add_content(db_session, source, title="Visible AI", topics=["ai"])
    hidden = await _add_content(db_session, source, title="Hidden AI", topics=["ai"])
    seen = await _add_content(db_session, source, title="Seen AI", topics=["ai"])

    db_session.add(
        UserContentStatus(
            user_id=user.user_id, content_id=hidden.id, is_hidden=True
        )
    )
    db_session.add(
        UserContentStatus(
            user_id=user.user_id,
            content_id=seen.id,
            status=ContentStatus.SEEN,
        )
    )
    await db_session.commit()

    await _make_config(db_session, user, topics=[("ai", "IA", [])])
    titles, _ = await _titles(db_session, user)
    assert "Visible AI" in titles
    assert "Hidden AI" not in titles
    assert "Seen AI" not in titles

    # is_active=False sur la source → tout disparaît.
    source.is_active = False
    await db_session.commit()
    titles2, _ = await _titles(db_session, user)
    assert titles2 == []


async def test_pagination_over_scored_set(db_session, user, source):
    """Pagination sur l'ensemble scoré : has_more + tranches cohérentes."""
    for i in range(5):
        await _add_content(
            db_session, source, title=f"AI article {i}", topics=["ai"], hours=i + 1
        )
    await _make_config(db_session, user, topics=[("ai", "IA", [])])

    page1, has_more1 = await fetch_veille_feed(
        db_session, user.user_id, limit=2, offset=0
    )
    page2, has_more2 = await fetch_veille_feed(
        db_session, user.user_id, limit=2, offset=2
    )
    assert len(page1) == 2
    assert has_more1 is True
    assert len(page2) == 2
    assert has_more2 is True
    titles1 = {c.title for c, _axes, _group in page1}
    titles2 = {c.title for c, _axes, _group in page2}
    assert titles1.isdisjoint(titles2)


# ─── Note d'intention `why` + split de récence deux blocs (refonte curation) ──


async def test_intent_why_injected_as_custom_topic(db_session, user):
    """`build_veille_scoring_context` injecte un angle « Intention » depuis `why`."""
    sid = uuid4()
    config = VeilleConfig(
        id=uuid4(),
        user_id=user.user_id,
        theme_id="culture",
        theme_label="Bière",
        status=VeilleStatus.ACTIVE.value,
    )
    filters = VeilleFilters(
        theme_id="culture",
        source_ids=[sid],
        source_intents={sid: "brasserie artisanale houblon"},
    )
    ctx = await build_veille_scoring_context(db_session, config, filters, _now())
    intention = [t for t in ctx.user_custom_topics if t.topic_name == "Intention"]
    assert len(intention) == 1
    assert {"brasserie", "artisanale", "houblon"} <= set(intention[0].keywords)


async def test_recency_split_configured_30d_external_7d(db_session, user, source):
    """Configuré de 20 j visible (Bloc A) ; externe on-topic de 20 j absent (Bloc B)."""
    external = Source(
        id=uuid4(),
        name="External",
        url="https://ext.example.com",
        feed_url=f"https://ext.example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(external)
    await db_session.commit()

    # Bloc A : source configurée, 20 j → dans la fenêtre 30 j.
    await _add_content(
        db_session, source, title="Configured 20d", topics=["ai"], hours=20 * 24
    )
    # Bloc B : externe on-topic, 20 j → hors fenêtre 7 j → exclu.
    await _add_content(
        db_session, external, title="External 20d", topics=["ai"], hours=20 * 24
    )
    # Bloc B : externe on-topic, 2 j → dans la fenêtre 7 j → visible.
    await _add_content(
        db_session, external, title="External 2d", topics=["ai"], hours=2 * 24
    )

    await _make_config(
        db_session, user, topics=[("ai", "IA", [])], source_ids=[source.id]
    )

    items, _ = await fetch_veille_feed(db_session, user.user_id, limit=50)
    by_title = {c.title: group for c, _axes, group in items}
    assert by_title.get("Configured 20d") == "sources"
    assert "External 20d" not in by_title
    assert by_title.get("External 2d") == "elargie"
