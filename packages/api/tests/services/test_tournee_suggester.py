"""Tests du `TourneeSuggester` — arrangement intelligent de la Tournée (Story 22.3).

Couvre : exclusion validées + muted, plancher de contenu, correction de la
raison (breakdown vrai, label dominant, aucune suggérée sans breakdown),
déterminisme du seed, capacité (sub_cap), et suggestions source + élargissement
doux.

DB locale : `DATABASE_URL` → facteur_test (54322), cf. conftest.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState, ReliabilityScore, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile
from app.models.user_personalization import UserPersonalization
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.tournee_suggester import TourneeSuggester

# ── Helpers ──────────────────────────────────────────────────────────────────


def _source(
    name: str,
    theme: str,
    *,
    curated: bool = True,
    reliability: ReliabilityScore = ReliabilityScore.HIGH,
) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://example.com/{uuid4()}",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme=theme,
        is_active=True,
        is_curated=curated,
        reliability_score=reliability,
    )


def _content(source_id, theme: str, *, days_ago: int = 1) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="Article",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        theme=theme,
    )


async def _seed_theme_content(db, theme: str, n: int) -> Source:
    """Crée une source curée + `n` articles récents pour un thème."""
    src = _source(f"src-{theme}", theme)
    db.add(src)
    await db.flush()
    for i in range(n):
        db.add(_content(src.id, theme, days_ago=i % 7))
    await db.flush()
    return src


async def _make_user(db) -> UserProfile:
    profile = UserProfile(user_id=uuid4(), onboarding_completed=True)
    db.add(profile)
    await db.flush()
    return profile


# ── Tests ────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_excludes_validated_and_muted(db_session):
    """Un thème validé (déjà rendu) ou muté n'est jamais suggéré."""
    user = await _make_user(db_session)
    uid = user.user_id
    # 3 thèmes suivis, tous avec du contenu.
    for theme in ("tech", "science", "sport"):
        await _seed_theme_content(
            db_session, theme, ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 2
        )
        db_session.add(
            UserInterest(
                user_id=uid,
                interest_slug=theme,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    # science est muté.
    db_session.add(
        UserPersonalization(user_id=uid, muted_themes=["science"], muted_sources=[])
    )
    await db_session.flush()

    # tech est déjà validé → exclu. science muté → exclu. Reste sport.
    suggestions = await TourneeSuggester(db_session).arrange(
        uid, validated_theme_slugs={"tech"}, sub_cap=4
    )
    theme_slugs = {s.slug for s in suggestions if s.kind == "theme"}
    assert "tech" not in theme_slugs
    assert "science" not in theme_slugs
    assert "sport" in theme_slugs


@pytest.mark.asyncio
async def test_content_floor_excludes_sparse_themes(db_session):
    """Un thème suivi sous le plancher de contenu est écarté."""
    user = await _make_user(db_session)
    uid = user.user_id
    # tech : sous le plancher (floor-1). science : au-dessus.
    await _seed_theme_content(
        db_session, "tech", ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR - 1
    )
    await _seed_theme_content(
        db_session, "science", ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 3
    )
    for theme in ("tech", "science"):
        db_session.add(
            UserInterest(
                user_id=uid,
                interest_slug=theme,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    await db_session.flush()

    suggestions = await TourneeSuggester(db_session).arrange(
        uid, validated_theme_slugs=set(), sub_cap=4
    )
    theme_slugs = {s.slug for s in suggestions if s.kind == "theme"}
    assert "tech" not in theme_slugs  # sous le floor
    assert "science" in theme_slugs


@pytest.mark.asyncio
async def test_reason_breakdown_is_true_and_never_empty(db_session):
    """Chaque suggérée a un breakdown non vide, vrai, avec label dominant."""
    user = await _make_user(db_session)
    uid = user.user_id
    n = ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 4
    await _seed_theme_content(db_session, "tech", n)
    db_session.add(
        UserInterest(
            user_id=uid, interest_slug="tech", weight=1.0, state=InterestState.FOLLOWED
        )
    )
    await db_session.flush()

    suggestions = await TourneeSuggester(db_session).arrange(
        uid, validated_theme_slugs=set(), sub_cap=4
    )
    assert suggestions, "tech devrait être suggéré"
    for s in suggestions:
        # Invariant anti-boîte-noire : jamais de suggérée sans breakdown.
        assert s.breakdown, "aucune suggérée sans breakdown"
        assert s.reason_label
        assert s.reason_label == s.breakdown[0].label  # dominant en tête
        labels = [c.label for c in s.breakdown]
        # La quantité réelle est reflétée (n articles), et la diversité est la
        # dernière puce (miroir « Hasard pour diversifier »).
        assert any("article" in label for label in labels)
        assert s.breakdown[-1].label == "Varié pour aujourd'hui"
    tech = next(s for s in suggestions if s.slug == "tech")
    assert any("thème" in c.label for c in tech.breakdown)  # explicit présent


@pytest.mark.asyncio
async def test_deterministic_within_day(db_session):
    """Même user + même jour → même ordre (seed daily)."""
    user = await _make_user(db_session)
    uid = user.user_id
    for theme in ("tech", "science", "sport", "culture", "economy"):
        await _seed_theme_content(
            db_session, theme, ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 2
        )
        db_session.add(
            UserInterest(
                user_id=uid,
                interest_slug=theme,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    await db_session.flush()

    first = await TourneeSuggester(db_session).arrange(uid, set(), sub_cap=4)
    second = await TourneeSuggester(db_session).arrange(uid, set(), sub_cap=4)
    assert [s.key for s in first] == [s.key for s in second]


@pytest.mark.asyncio
async def test_sub_cap_zero_returns_empty(db_session):
    """sub_cap <= 0 (Tournée pleine) → aucune suggestion."""
    user = await _make_user(db_session)
    await _seed_theme_content(db_session, "tech", 5)
    db_session.add(
        UserInterest(
            user_id=user.user_id,
            interest_slug="tech",
            weight=1.0,
            state=InterestState.FOLLOWED,
        )
    )
    await db_session.flush()
    assert (
        await TourneeSuggester(db_session).arrange(user.user_id, set(), sub_cap=0) == []
    )


@pytest.mark.asyncio
async def test_sub_cap_limits_count(db_session):
    """Le nombre de suggérées ne dépasse jamais sub_cap."""
    user = await _make_user(db_session)
    uid = user.user_id
    for theme in ("tech", "science", "sport", "culture", "economy", "politics"):
        await _seed_theme_content(
            db_session, theme, ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 2
        )
        db_session.add(
            UserInterest(
                user_id=uid,
                interest_slug=theme,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    await db_session.flush()
    suggestions = await TourneeSuggester(db_session).arrange(uid, set(), sub_cap=2)
    assert len(suggestions) == 2


@pytest.mark.asyncio
async def test_followed_source_is_suggested(db_session):
    """Une source suivie (non favorite) avec du contenu devient une suggérée."""
    user = await _make_user(db_session)
    uid = user.user_id
    src = _source("Le Monde", "society")
    db_session.add(src)
    await db_session.flush()
    for i in range(ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 2):
        db_session.add(_content(src.id, "society", days_ago=i % 5))
    db_session.add(
        UserSource(
            user_id=uid, source_id=src.id, is_custom=False, state=InterestState.FOLLOWED
        )
    )
    await db_session.flush()

    suggestions = await TourneeSuggester(db_session).arrange(uid, set(), sub_cap=4)
    src_suggestions = [s for s in suggestions if s.kind == "source"]
    assert len(src_suggestions) == 1
    s = src_suggestions[0]
    assert s.source_id == src.id
    assert s.key == f"source:{src.id}"
    assert any("source" in c.label for c in s.breakdown)


@pytest.mark.asyncio
async def test_soft_expansion_curated_on_followed_theme(db_session):
    """Pool maigre → élargissement doux : source curée sur un thème suivi."""
    user = await _make_user(db_session)
    uid = user.user_id
    # Thème suivi tech, MAIS aucun contenu pour le thème (donc pas de candidat
    # thème direct) — seule une source curée tech avec du contenu existe.
    src = _source("Tech Source", "tech")
    db_session.add(src)
    await db_session.flush()
    for i in range(ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR + 2):
        db_session.add(_content(src.id, "tech", days_ago=i % 5))
    db_session.add(
        UserInterest(
            user_id=uid, interest_slug="tech", weight=1.0, state=InterestState.FOLLOWED
        )
    )
    await db_session.flush()

    suggestions = await TourneeSuggester(db_session).arrange(uid, set(), sub_cap=4)
    soft = [s for s in suggestions if s.kind == "source" and s.is_soft]
    assert soft, "la source curée on-thème devrait être suggérée en doux"
    assert any("thème que tu suis" in c.label for c in soft[0].breakdown)
