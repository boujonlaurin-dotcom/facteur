"""Tests curation veille par score (Story 23.4).

Couvre la curation v2 du feed veille — gatée derrière `is_veille` pour ne pas
toucher le chemin custom-topic de la Tournée (Epic 11) :

- **Pertinence veille** (`PertinencePillar._score_custom_topics`) : barème
  escaladant (2kw > 1kw), topic > keyword, combo (topic+kw) en tête, source
  suivie conditionnée (boost on-angle only, jamais sur source-seul).
- **Floor + seuil + anti-starvation** (`feed_filter._score_and_rank`) : la
  source est un boost, pas un free-pass ; le seuil 48 coupe le bruit ; la
  relâche anti-starvation ne réadmet jamais un floor-pruned.
- **DB end-to-end** (`fetch_veille_feed`) : un article source-seule off-angle
  est exclu du feed.
- **Régression** : un custom topic Epic 11 (sans `is_veille`) garde le `+25` plat.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState
from app.models.source import Source, SourceType
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.services.recommendation.pillars.pertinence import PertinencePillar
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.veille.feed_filter import (
    VeilleAngle,
    VeilleFilters,
    _matched_axes,
    _score_block,
    fetch_veille_feed,
)


def _score_and_rank(candidates, context, filters):
    """Shim Bloc B (floor + seuil + anti-starvation) — comportement historique."""
    return _score_block(
        candidates, context, filters, apply_floor=True, apply_threshold=True
    )
from app.services.veille.scoring_context import VeilleAngleTopic, _tokenize_intent

# ─── Helpers légers pour le pilier Pertinence ────────────────────────────────


class _Content:
    """Stand-in minimal pour `_score_custom_topics` (topics/title/desc/source)."""

    def __init__(self, *, topics=None, title="", description="", source_id=None):
        self.topics = topics or []
        self.title = title
        self.description = description
        self.source_id = source_id


class _Ctx:
    def __init__(self, angles, followed=None):
        self.user_custom_topics = angles
        self.followed_source_ids = followed or set()


def _veille_angle(slug="ai", keywords=("llm", "gpt", "agent")):
    return VeilleAngleTopic(
        slug_parent=slug,
        keywords=list(keywords),
        topic_name="IA",
        is_veille=True,
    )


def _angle_score(content, *, followed=None) -> float:
    pillar = PertinencePillar()
    score, _ = pillar._score_custom_topics(content, _Ctx([_veille_angle()], followed))
    return score


# ─── Pertinence veille : barème ──────────────────────────────────────────────


def test_keyword_bonus_escalates_with_distinct_matches():
    """2 mots-clés distincts rapportent plus qu'un seul (courbe escaladante)."""
    one = _angle_score(_Content(topics=["tech"], title="Un nouveau LLM est sorti"))
    two = _angle_score(
        _Content(topics=["tech"], title="Un nouveau LLM signé GPT débarque")
    )
    assert one == pytest.approx(ScoringWeights.VEILLE_KEYWORD_BASE_BONUS)
    assert two == pytest.approx(
        ScoringWeights.VEILLE_KEYWORD_BASE_BONUS + ScoringWeights.VEILLE_KEYWORD_INCREMENT
    )
    assert two > one


def test_keyword_matching_is_word_boundary():
    """Mot-entier : « agent » matche « un agent » mais pas « agentic » (Pb 3).

    Avant le fix, le matching en sous-chaîne laissait passer des articles
    hors-sujet dont le titre contenait juste le mot-clé en fragment.
    """
    whole = _angle_score(_Content(topics=["tech"], title="Un agent autonome débarque"))
    substring = _angle_score(
        _Content(topics=["tech"], title="Les agentic workflows expliqués")
    )
    assert whole == pytest.approx(ScoringWeights.VEILLE_KEYWORD_BASE_BONUS)
    assert substring == 0.0


def test_keyword_bonus_is_capped():
    """Le bonus mots-clés ne dépasse jamais le cap, même avec beaucoup de hits."""
    many = VeilleAngleTopic(
        slug_parent="ai",
        keywords=["a", "b", "c", "d", "e", "f", "g", "h"],
        topic_name="IA",
        is_veille=True,
    )
    pillar = PertinencePillar()
    score, _ = pillar._score_custom_topics(
        _Content(topics=["tech"], title="a b c d e f g h"), _Ctx([many])
    )
    assert score == pytest.approx(ScoringWeights.VEILLE_KEYWORD_CAP)


def test_topic_beats_single_keyword():
    """Le topic canonique (+50) pèse plus qu'un mot-clé seul (+18)."""
    topic_only = _angle_score(_Content(topics=["ai"], title="Intelligence artificielle"))
    kw_only = _angle_score(_Content(topics=["tech"], title="Un nouveau LLM"))
    assert topic_only == pytest.approx(ScoringWeights.VEILLE_TOPIC_MATCH_BONUS)
    assert topic_only > kw_only


def test_combo_topic_and_keyword_is_strongest():
    """Topic + mot-clé = signal on-angle le plus fort (topic + kw + combo)."""
    combo = _angle_score(_Content(topics=["ai"], title="Le LLM star de l'IA"))
    topic_only = _angle_score(_Content(topics=["ai"], title="Intelligence générale"))
    kw_only = _angle_score(_Content(topics=["tech"], title="Un LLM impressionnant"))
    expected = (
        ScoringWeights.VEILLE_KEYWORD_BASE_BONUS
        + ScoringWeights.VEILLE_TOPIC_MATCH_BONUS
        + ScoringWeights.VEILLE_TOPIC_KEYWORD_COMBO_BONUS
    )
    assert combo == pytest.approx(expected)
    assert combo > topic_only > kw_only


def test_source_only_off_angle_scores_zero():
    """Un article source-seule (ni topic ni mot-clé) n'a aucune pertinence veille."""
    sid = uuid4()
    score = _angle_score(
        _Content(topics=["sport"], title="Résultats du match", source_id=sid),
        followed={sid},
    )
    assert score == 0.0


def test_followed_source_conditional_bonus():
    """+12 source seulement quand l'article a déjà topic|keyword (bonus>0)."""
    sid = uuid4()
    on_angle = _Content(topics=["ai"], title="Avancées en IA", source_id=sid)
    not_followed = _angle_score(on_angle)
    followed = _angle_score(on_angle, followed={sid})
    assert followed - not_followed == pytest.approx(
        ScoringWeights.VEILLE_SOURCE_ON_TOPIC_BONUS
    )


def test_non_veille_custom_topic_keeps_flat_bonus():
    """Régression : un custom topic Epic 11 (sans is_veille) garde le +25 plat."""

    class _RealTopic:
        slug_parent = "ai"
        keywords = ["llm", "gpt", "agent"]
        topic_name = "IA"
        priority_multiplier = 1.0
        state = InterestState.FOLLOWED
        # pas de `is_veille` → getattr(..., False)

    pillar = PertinencePillar()
    # topic + 3 mots-clés : en veille ce serait ~113, ici reste plat à +25.
    score, _ = pillar._score_custom_topics(
        _Content(topics=["ai"], title="Le LLM GPT agent IA"), _Ctx([_RealTopic()])
    )
    assert score == pytest.approx(ScoringWeights.CUSTOM_TOPIC_BASE_BONUS)


# ─── Floor + seuil + anti-starvation (`_score_and_rank`) ─────────────────────


def _make_source(name="Src", followed=True):
    return Source(
        id=uuid4(),
        name=name,
        theme="tech",
        is_curated=True,
        secondary_themes=[],
        tone=None,
    )


def _make_content(source, *, topics, title, mins=30):
    return Content(
        id=uuid4(),
        title=title,
        description="",
        theme="tech",
        topics=topics,
        published_at=datetime(2026, 6, 2, 10, 0, tzinfo=UTC) - timedelta(minutes=mins),
        source_id=source.id,
        source=source,
        content_type=ContentType.ARTICLE,
        duration_seconds=None,
        entities=[],
        content_quality="full",
        thumbnail_url="https://img",
    )


def _veille_context(followed_ids):
    return ScoringContext(
        user_profile=None,
        user_interests={"tech"},
        user_interest_weights={},
        followed_source_ids=set(followed_ids),
        user_prefs={},
        now=datetime(2026, 6, 2, 10, 0, tzinfo=UTC),
        user_subtopics={"ai"},
        user_subtopic_weights={},
        user_custom_topics=[_veille_angle()],
    )


def _veille_filters(source_ids):
    return VeilleFilters(
        theme_id="tech",
        angles=[VeilleAngle(topic_id="ai", label="IA", keywords=["llm", "gpt", "agent"])],
        source_ids=list(source_ids),
        global_keywords=[],
    )


def test_floor_prunes_source_only_candidates():
    """La source est un boost, pas un free-pass : source-seul off-angle écarté."""
    src = _make_source()
    on_angle = _make_content(src, topics=["ai"], title="Nouveau LLM GPT agent")
    source_only = _make_content(src, topics=["sport"], title="Résultats du PSG")
    flt = _veille_filters([src.id])
    ctx = _veille_context([src.id])

    kept = _score_and_rank([on_angle, source_only], ctx, flt)
    kept_ids = {c.id for c, _s, _a in kept}
    assert on_angle.id in kept_ids
    assert source_only.id not in kept_ids


def test_on_topic_from_unfollowed_source_survives():
    """Un on-topic d'une source NON suivie passe le floor (topic = axe qualifiant)."""
    followed = _make_source("Followed")
    other = _make_source("Other")
    on_topic = _make_content(other, topics=["ai"], title="Intelligence artificielle")
    flt = _veille_filters([followed.id])  # other n'est pas suivie
    ctx = _veille_context([followed.id])

    kept = _score_and_rank([on_topic], ctx, flt)
    assert {c.id for c, _s, _a in kept} == {on_topic.id}


def test_threshold_cuts_below_floor_score():
    """Le seuil 48 reste au-dessus du plancher anti-starvation (40)."""
    assert ScoringWeights.VEILLE_RELEVANCE_THRESHOLD > 40.0


def test_anti_starvation_never_readmits_floor_pruned():
    """Sous le min feed, on relâche le seuil — mais jamais un source-seul."""
    src = _make_source()
    # 1 seul on-angle faible + plein de source-seul off-angle.
    weak = _make_content(src, topics=["tech"], title="Un agent vaguement tech")
    floods = [
        _make_content(src, topics=["tech"], title=f"Bon plan #{i}", mins=40 + i)
        for i in range(6)
    ]
    flt = _veille_filters([src.id])
    ctx = _veille_context([src.id])

    kept = _score_and_rank([weak, *floods], ctx, flt)
    kept_ids = {c.id for c, _s, _a in kept}
    # Aucun des articles source-seule (floods) n'est réadmis par l'anti-starvation.
    for f in floods:
        assert f.id not in kept_ids


# ─── Note d'intention `why` : tokenisation ───────────────────────────────────


def test_tokenize_intent_strips_stopwords_and_short_tokens():
    """Stopwords FR + tokens < 4 caractères retirés ; dédup ordre stable."""
    tokens = _tokenize_intent(["Je veux suivre la brasserie artisanale et le houblon"])
    assert {"brasserie", "artisanale", "houblon"} <= set(tokens)
    assert "la" not in tokens
    assert "et" not in tokens


def test_tokenize_intent_dedupes():
    assert _tokenize_intent(["houblon houblon HOUBLON"]).count("houblon") == 1


# ─── Bloc A « Tes sources » : laisser-passer + cap diversité ─────────────────


def test_block_a_keeps_source_only_off_angle():
    """Bloc A (apply_floor=False) : un article source-seul off-angle est gardé."""
    src = _make_source()
    source_only = _make_content(src, topics=["sport"], title="Résultats du PSG")
    flt = _veille_filters([src.id])
    ctx = _veille_context([src.id])

    kept = _score_block(
        [source_only], ctx, flt, apply_floor=False, apply_threshold=False
    )
    assert {c.id for c, _s, _a in kept} == {source_only.id}


def test_block_a_diversity_cap_limits_per_source():
    """Bloc A : au plus VEILLE_SOURCE_DIVERSITY_CAP articles par source."""
    src = _make_source()
    cap = ScoringWeights.VEILLE_SOURCE_DIVERSITY_CAP
    contents = [
        _make_content(src, topics=["ai"], title=f"Article IA #{i}", mins=10 + i)
        for i in range(cap + 4)
    ]
    flt = _veille_filters([src.id])
    ctx = _veille_context([src.id])

    kept = _score_block(
        contents,
        ctx,
        flt,
        apply_floor=False,
        apply_threshold=False,
        diversity_cap=cap,
    )
    assert len(kept) == cap


# ─── DB end-to-end (`fetch_veille_feed`) ─────────────────────────────────────


async def _insert_source(db_session, name="Veille Source") -> Source:
    src = Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4().hex}.com",
        feed_url=f"https://{uuid4().hex}.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(src)
    await db_session.commit()
    return src


async def _insert_content(db_session, source_id, *, topics, title) -> UUID:
    cid = uuid4()
    db_session.add(
        Content(
            id=cid,
            source_id=source_id,
            title=title,
            url=f"https://example.com/{cid}",
            guid=f"guid-{cid}",
            published_at=datetime.now(UTC) - timedelta(hours=2),
            content_type=ContentType.ARTICLE,
            theme="tech",
            topics=topics,
            content_quality="full",
        )
    )
    await db_session.commit()
    return cid


@pytest.mark.asyncio
async def test_fetch_veille_feed_two_blocks(db_session):
    """End-to-end (refonte deux blocs) :

    - Bloc A « Tes sources » : un article off-angle d'une source **configurée**
      passe (laisser-passer), tagué ``group="sources"``.
    - Bloc B « Couverture élargie » : un article off-angle d'une source **non
      configurée** est élagué par le floor (source = boost, pas free-pass).
    - Un on-topic d'une source externe entre dans le Bloc B.
    """
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()
    configured = await _insert_source(db_session, name="Configurée")
    external = await _insert_source(db_session, name="Externe")

    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user_id,
        theme_id="tech",
        theme_label="Tech",
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.commit()

    db_session.add(
        VeilleTopic(
            veille_config_id=cfg.id,
            topic_id="ai",
            label="IA",
            kind="preset",
            position=0,
        )
    )
    db_session.add(
        VeilleSource(
            veille_config_id=cfg.id, source_id=configured.id, kind="curated", position=0
        )
    )
    await db_session.commit()

    # Bloc A : off-angle mais source configurée → passe (laisser-passer).
    block_a_off_angle = await _insert_content(
        db_session, configured.id, topics=["sport"], title="Résultats du match"
    )
    # Bloc B : on-topic d'une source externe → passe (topic = axe qualifiant).
    block_b_on_topic = await _insert_content(
        db_session, external.id, topics=["ai"], title="Avancées en IA"
    )
    # Bloc B : off-angle d'une source externe → floor-pruned.
    external_source_only = await _insert_content(
        db_session, external.id, topics=["sport"], title="Transfert record au PSG"
    )

    items, _has_more = await fetch_veille_feed(db_session, user_id, limit=20)
    by_id = {content.id: group for content, _axes, group in items}

    assert by_id.get(block_a_off_angle) == "sources"
    assert by_id.get(block_b_on_topic) == "elargie"
    assert external_source_only not in by_id
