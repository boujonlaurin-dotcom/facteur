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
    thumbnail_url=None,
    content_quality=None,
    language=None,
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
        thumbnail_url=thumbnail_url,
        content_quality=content_quality,
        language=language,
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
        db_session.add(
            VeilleSource(veille_config_id=cfg.id, source_id=sid, kind="followed")
        )

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
    """Topic (>) mot-clé : les deux présents, topic mieux classé. La grappe porte
    2 mots-clés (floor durci B : un keyword-only exige ≥ 2 hits) et les articles
    sont de qualité normale (au-dessus du seuil composite sans anti-starvation)."""
    await _add_content(
        db_session,
        source,
        title="Topic Match",
        topics=["ai"],
        thumbnail_url="https://img.example.com/x.jpg",
        content_quality="full",
    )
    await _add_content(
        db_session,
        source,
        title="Keyword Match transformers",
        topics=["other"],
        description="nouveau modèle transformers",
        thumbnail_url="https://img.example.com/x.jpg",
        content_quality="full",
    )
    await _make_config(
        db_session,
        user,
        topics=[("ai", "IA", ["transformers", "modèle"])],
    )

    titles, _ = await _titles(db_session, user)
    assert "Topic Match" in titles
    assert "Keyword Match transformers" in titles
    assert titles.index("Topic Match") < titles.index("Keyword Match transformers")


async def test_source_only_config_passthrough_present(db_session, user, source):
    """Config purement source (floor/gate inactifs) : un article de la source
    configurée est présent. Article de qualité normale (thumbnail + full) pour
    dépasser franchement le seuil composite — l'anti-starvation, qui rattrapait
    les articles source-seuls ~45-47, a été supprimée (C)."""
    await _add_content(
        db_session,
        source,
        title="From Source",
        theme="economy",
        topics=["markets"],
        thumbnail_url="https://img.example.com/x.jpg",
        content_quality="full",
    )
    await _make_config(db_session, user, source_ids=[source.id])
    titles, _ = await _titles(db_session, user)
    assert "From Source" in titles


async def test_keyword_only_present(db_session, user, source):
    """Config mot-clés seuls : un article matchant qualifie le floor durci (B)
    via **2 hits distincts** et reste au-dessus du gate + seuil."""
    await _add_content(
        db_session,
        source,
        title="Vélo électrique nouveau modèle",
        theme="society",
        topics=["mobility"],
        description="test du nouveau VAE",
        thumbnail_url="https://img.example.com/x.jpg",
        content_quality="full",
    )
    # 2 mots-clés distincts (floor durci exige ≥ 2 hits pour un keyword-only).
    await _make_config(db_session, user, global_keywords=["vélo", "électrique"])
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
        UserContentStatus(user_id=user.user_id, content_id=hidden.id, is_hidden=True)
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


# ─── Split de récence deux blocs (refonte curation) ──────────────────────────


async def test_why_no_longer_injected_as_custom_topic(db_session, user):
    """E — la tokenisation des `why` est retirée : `build_veille_scoring_context`
    ne fabrique plus d'angle « Intention », même quand des sources ont un `why`
    (le champ `source_intents` n'existe plus sur `VeilleFilters`)."""
    sid = uuid4()
    config = VeilleConfig(
        id=uuid4(),
        user_id=user.user_id,
        theme_id="culture",
        theme_label="Bière",
        status=VeilleStatus.ACTIVE.value,
    )
    filters = VeilleFilters(theme_id="culture", source_ids=[sid])
    ctx = await build_veille_scoring_context(db_session, config, filters, _now())
    assert all(t.topic_name != "Intention" for t in ctx.user_custom_topics)


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


# ─── D — pool Bloc A équitable par source ────────────────────────────────────


async def test_block_a_per_source_pool_is_fair(db_session, user, source, monkeypatch):
    """D — une source bavarde ne rafle plus tout le pool : sous un cap externe
    serré, les articles d'une source discrète (plus anciens, mais dans la fenêtre
    30 j) restent visibles. Avec l'ancien `ORDER BY published_at DESC LIMIT cap`
    **global**, les récents de la source dense les évinceraient ; le
    `row_number() PARTITION BY source_id` borne d'abord chaque source."""
    from app.services.recommendation.scoring_config import ScoringWeights as _SW

    # Cap externe serré + 2 candidats/source pour rendre l'effet observable sans
    # insérer des centaines d'articles (l'effet ne mord qu'au-delà du cap global).
    monkeypatch.setattr(_SW, "VEILLE_BLOCK_A_PER_SOURCE_CANDIDATES", 2)
    monkeypatch.setattr(_SW, "VEILLE_CANDIDATE_CAP", 3)

    quiet = Source(
        id=uuid4(),
        name="Quiet",
        url="https://q.example.com",
        feed_url=f"https://q.example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
        reliability_score=ReliabilityScore.HIGH,
    )
    db_session.add(quiet)
    await db_session.commit()

    # Source dense : 5 articles on-topic récents (1 à 5 h).
    for i in range(5):
        await _add_content(
            db_session,
            source,
            title=f"Dense {i}",
            topics=["ai"],
            hours=i + 1,
            thumbnail_url="https://img.example.com/x.jpg",
            content_quality="full",
        )
    # Source discrète : 2 articles on-topic plus anciens (100-101 h < 30 j).
    for i in range(2):
        await _add_content(
            db_session,
            quiet,
            title=f"Quiet {i}",
            topics=["ai"],
            hours=100 + i,
            thumbnail_url="https://img.example.com/x.jpg",
            content_quality="full",
        )

    await _make_config(
        db_session, user, topics=[("ai", "IA", [])], source_ids=[source.id, quiet.id]
    )

    titles, _ = await _titles(db_session, user)
    # La source discrète n'est pas affamée : au moins un de ses articles passe.
    assert any(t.startswith("Quiet") for t in titles)


# ─── G1 — filtre langue du Bloc B ────────────────────────────────────────────


async def _add_external_source(db_session, *, language=None):
    s = Source(
        id=uuid4(),
        name=f"Ext {uuid4().hex[:6]}",
        url=f"https://ext-{uuid4().hex}.com",
        feed_url=f"https://ext-{uuid4().hex}.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
        language=language,
    )
    db_session.add(s)
    await db_session.commit()
    return s


async def test_block_b_language_filter_excludes_foreign(db_session, user, source):
    """G1 — Bloc B : un article de langue étrangère (en) d'une source non
    configurée est écarté ; `language=None` passe (permissif)."""
    ext = await _add_external_source(db_session)
    await _add_content(
        db_session, ext, title="AI breakthrough", topics=["ai"], language="en"
    )
    await _add_content(
        db_session, ext, title="Percée IA sans langue", topics=["ai"], language=None
    )
    # Source configurée FR (fixture `source`, language=None) → allowed = {fr}.
    await _make_config(
        db_session, user, topics=[("ai", "IA", [])], source_ids=[source.id]
    )

    titles, _ = await _titles(db_session, user)
    assert "AI breakthrough" not in titles  # en → filtré
    assert "Percée IA sans langue" in titles  # NULL → permissif


async def test_block_b_language_filter_allows_configured_source_language(
    db_session, user
):
    """G1 — une langue portée par une source **configurée** (en) est autorisée au
    Bloc B : un article externe en anglais redevient visible."""
    configured_en = await _add_external_source(db_session, language="en")
    other_en = await _add_external_source(db_session, language="en")
    await _add_content(
        db_session,
        other_en,
        title="AI breakthrough abroad",
        topics=["ai"],
        language="en",
    )
    # La config déclare une source de langue en → 'en' entre dans allowed.
    await _make_config(
        db_session, user, topics=[("ai", "IA", [])], source_ids=[configured_en.id]
    )

    titles, _ = await _titles(db_session, user)
    assert "AI breakthrough abroad" in titles
