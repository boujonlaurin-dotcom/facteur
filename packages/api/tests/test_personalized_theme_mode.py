"""Unit tests for the Tournée du jour personalized theme mode.

When `?personalized=true` is combined with `?theme=` or `?topic=` on
`/api/feed/`, `_get_candidates` must:
  1. restrict the candidate pool to articles published in the last 24h
     (fenêtre élargie à 48h/72h si le pool est trop maigre — Fix #2),
  2. restrict sources to the user's followed sources (with the existing
     two-phase + curated fallback path on empty follow set), and
  3. boost articles whose `Content.topics` overlap `user_subtopics` via a
     secondary ORDER BY (soft boost — does not exclude non-matchers).

When `personalized=False`, the existing exploration mode (chip taps) must
behave exactly as before: no source restriction, no time window, no
subtopic ORDER BY tweak.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.services.recommendation_service import (
    RecommendationService,
    is_personalized_theme_mode,
)


def _stub_scalars(captured: list):
    """Return an async `session.scalars` that captures the compiled SQL."""

    result = MagicMock()
    result.all.return_value = []

    async def _scalars(stmt):
        captured.append(stmt.compile(compile_kwargs={"literal_binds": False}).__str__())
        return result

    return _scalars, result


def _make_service():
    session = MagicMock()
    session.rollback = AsyncMock()
    return RecommendationService(session), session


def _mock_content():
    """Minimal Content stub: only `.id` (dedup) + `.source` (logging) used."""
    c = MagicMock()
    c.id = uuid4()
    return c


def _stub_scalars_two_pools(captured: list, followed: list, backfill: list):
    """`session.scalars` returning the followed pool for the two-phase query and
    the backfill pool for the curated `NOT IN` query (distinguished by SQL)."""

    def _result(items):
        r = MagicMock()
        r.all.return_value = items
        return r

    async def _scalars(stmt):
        sql = str(stmt.compile(compile_kwargs={"literal_binds": False}))
        captured.append(sql)
        if " not in " in sql.lower():
            return _result(backfill)
        return _result(followed)

    return _scalars


@pytest.mark.asyncio
async def test_personalized_theme_filters_to_followed_sources():
    """personalized=True + theme + followed → SQL restricts to followed sources."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    followed = {uuid4(), uuid4()}

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids=followed,
        ),
        timeout=5.0,
    )

    assert captured, "expected at least one SQL statement to be issued"
    sql = captured[0].lower()
    # Two-phase path → followed-only WHERE clause.
    assert "sources.id in" in sql or "source.id in" in sql, (
        "personalized theme mode should filter on followed sources via "
        f"two-phase. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_applies_24h_window():
    """personalized=True + theme → SQL adds Content.published_at >= now-24h."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "published_at" in sql and ">=" in sql, (
        "personalized theme mode should add a published_at >= cutoff filter."
        f" Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_subtopic_boost_in_order_by():
    """personalized=True + theme + user_subtopics → ORDER BY includes overlap."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
            user_subtopics={"ai", "startups"},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    # `Content.topics.overlap([...])` compiles to the `&&` operator on
    # Postgres dialect; on the default SA dialect it emits "overlap".
    assert "overlap" in sql or "&&" in sql, (
        "subtopic boost should add an overlap-based ORDER BY tie-breaker. "
        f"Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_no_followed_falls_back_to_curated():
    """personalized=True + theme + no followed sources → curated fallback,
    not two-phase. Section never empty just because user follows nothing."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids=set(),
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "is_curated" in sql, (
        "personalized theme mode with zero followed sources must fall back "
        f"to the curated query. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_explicit_filter_unchanged_when_personalized_false():
    """Regression guard for the exploration chip path.

    theme set + personalized=False → existing behavior: no source
    restriction (all active sources), no 24h window, no subtopic ORDER BY.
    """
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=False,
            followed_source_ids={uuid4()},
            user_subtopics={"ai"},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    # Exploration mode must NOT restrict on followed sources or curated:
    # neither the followed-source IN-list nor the curated filter applies.
    assert "sources.id in" not in sql and "source.id in" not in sql, (
        "exploration (personalized=False) must not restrict on followed "
        f"sources. Got:\n{captured[0]}"
    )
    # No 24h window either.
    assert ">= " not in sql or "published_at" not in sql, (
        f"exploration must not add a 24h published_at filter. Got:\n{captured[0]}"
    )
    # No overlap-based ORDER BY.
    assert "overlap" not in sql and "&&" not in sql, (
        f"exploration must not add a subtopic overlap ORDER BY. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_relaxes_seen_consumed_filter():
    """Régression : personalized=True + theme ne doit PAS re-filtrer les
    articles seen/consumed — il doit tomber dans la branche explicit_filter=True
    (identique à Flâner thème) et n'exclure que is_hidden.

    Avant le fix : personalized_theme_mode=True → explicit_filter=False
    → les articles seen/consumed disparaissaient des sections thématiques
    de la Tournée alors qu'ils restaient visibles dans le Flâner filtré.
    Après le fix : theme is not None → explicit_filter=True toujours.
    """
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert captured, "expected at least one SQL statement"
    sql = captured[0].lower()

    # La branche explicit_filter=True n'inclut ni is_saved, ni
    # last_impressed_at, ni manually_impressed dans le NOT EXISTS.
    # Ces colonnes n'apparaissent que dans la branche default (explicit_filter=False).
    assert "is_saved" not in sql, (
        "personalized_theme_mode doit utiliser explicit_filter=True : "
        "is_saved ne doit pas apparaître dans le NOT EXISTS.\n"
        f"SQL:\n{captured[0]}"
    )
    assert "last_impressed_at" not in sql, (
        "personalized_theme_mode ne doit pas filtrer last_impressed_at.\n"
        f"SQL:\n{captured[0]}"
    )
    assert "manually_impressed" not in sql, (
        "personalized_theme_mode ne doit pas filtrer manually_impressed.\n"
        f"SQL:\n{captured[0]}"
    )


# ---------------------------------------------------------------------------
# Sections SOURCE de la Tournée (PR « Sources dans la Tournée »).
# source_id + personalized=true ⇒ chemin scoré (fenêtre 24h) restreint à la
# source ; le filtre source_id court-circuite la stratification two-phase, et
# source_id SANS personalized reste chronologique (non-régression Flâner).
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_personalized_source_filters_and_scores():
    """source_id + personalized=True → pool restreint à la source ET fenêtre
    24h (branche scoring), sans la restriction two-phase sources suivies."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    src = uuid4()
    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            source_id=src,
            personalized=True,
            followed_source_ids={uuid4(), uuid4()},
        ),
        timeout=5.0,
    )

    assert captured, "expected at least one SQL statement"
    sql = captured[0].lower()
    # Pool restreint à la source unique.
    assert "source_id = " in sql or "source_id =" in sql, (
        f"source section must filter on the single source_id. Got:\n{captured[0]}"
    )
    # Fenêtre de fraîcheur appliquée → preuve qu'on est dans le chemin scoré
    # (personalized_theme_mode True), pas l'early-return chrono.
    assert "published_at" in sql and ">=" in sql, (
        "source section + personalized must add the adaptive freshness window."
        f" Got:\n{captured[0]}"
    )
    # La stratification two-phase (sources suivies) est inerte : le filtre
    # source_id gagne la première branche du if/elif.
    assert "sources.id in" not in sql and "source.id in" not in sql, (
        "source mode must NOT apply the followed-source two-phase restriction."
        f" Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_source_alone_stays_chronological():
    """source_id SANS personalized → filtre source seul, AUCUNE fenêtre 24h
    (early-return chrono, non-régression Flâner épingle-source)."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    src = uuid4()
    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            source_id=src,
            personalized=False,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "source_id = " in sql or "source_id =" in sql, (
        f"Flâner source filter must still apply source_id. Got:\n{captured[0]}"
    )
    # Pas de fenêtre de fraîcheur en mode non-personnalisé.
    assert ">= " not in sql or "published_at" not in sql, (
        "source alone (personalized=False) must not add the 24h window."
        f" Got:\n{captured[0]}"
    )


# ---------------------------------------------------------------------------
# `followed_only` — onglets de découverte Flâner (sujet / thème / entité).
#
# Le bloc principal de chaque onglet ne charge que les sources suivies → requête
# rapide. Contrairement à `personalized`, le tri reste CHRONOLOGIQUE (pas de
# scoring piliers ni de fenêtre adaptative). Le bloc « Explorer » charge les
# sources non-suivies via un appel séparé SANS `followed_only` (chemin existant).
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_followed_only_topic_restricts_to_followed_chronological():
    """topic + followed_only=True + sources suivies → restriction aux sources
    suivies (contents.source_id IN) SANS fenêtre de fraîcheur (chronologique)."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    followed = {uuid4(), uuid4()}
    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            topic="startups",
            personalized=False,
            followed_only=True,
            followed_source_ids=followed,
        ),
        timeout=5.0,
    )

    assert captured, "expected at least one SQL statement"
    sql = captured[0].lower()
    # Restriction directe aux sources suivies (pas le two-phase sources.id IN).
    assert "source_id in" in sql, (
        "followed_only topic must restrict to followed sources via "
        f"contents.source_id IN. Got:\n{captured[0]}"
    )
    # Tri chronologique conservé : aucune fenêtre published_at >= cutoff.
    assert ">= " not in sql or "published_at" not in sql, (
        "followed_only must stay chronological (no freshness window)."
        f" Got:\n{captured[0]}"
    )
    # Pas de boost subtopic (réservé à personalized).
    assert "overlap" not in sql and "&&" not in sql, (
        f"followed_only must not add a subtopic overlap ORDER BY. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_followed_only_entity_restricts_to_followed():
    """entity + followed_only=True → même restriction aux sources suivies."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            entity="OpenAI",
            personalized=False,
            followed_only=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "source_id in" in sql, (
        f"followed_only entity must restrict to followed sources. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_followed_only_zero_followed_falls_back_to_curated():
    """topic + followed_only=True + zéro source suivie → repli curé pour ne pas
    vider le bloc principal (même sémantique que personalized_theme_mode)."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            topic="startups",
            personalized=False,
            followed_only=True,
            followed_source_ids=set(),
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "is_curated" in sql, (
        "followed_only with zero followed sources must fall back to curated."
        f" Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_topic_without_followed_only_unchanged():
    """Régression : topic + followed_only=False → comportement actuel inchangé
    (toutes sources, aucune restriction suivie ni curée)."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            topic="startups",
            personalized=False,
            followed_only=False,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    # Branche fourre-tout : ni restriction sources suivies, ni filtre curé.
    assert "source_id in" not in sql, (
        "topic without followed_only must not restrict to followed sources."
        f" Got:\n{captured[0]}"
    )
    assert "is_curated" not in sql, (
        f"topic without followed_only must not apply curated filter. Got:\n{captured[0]}"
    )


# ---------------------------------------------------------------------------
# Backfill curé NON-suivi : garantit ≥ THEMATIC_HARD_FLOOR articles par section
# thématique quand le pool des sources suivies est trop maigre (même au palier
# 72h). On complète avec des sources curées non-suivies (comme Flâner), marquées
# « Suivre + » côté client. Décisions PO : compléter par du curé non-suivi,
# profondeur 72h, pas de palier 7 jours.
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_thematic_backfill_reaches_floor():
    """Pool suivi = 3 (< plancher 5) → une requête curée non-suivie est émise et
    le résultat fusionné a ≥5, les articles suivis d'abord."""
    from app.services.recommendation.scoring_config import ScoringWeights

    service, session = _make_service()
    captured: list[str] = []
    followed = [_mock_content() for _ in range(3)]
    backfill = [_mock_content() for _ in range(5)]
    session.scalars = _stub_scalars_two_pools(captured, followed, backfill)

    result = await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="science",
            personalized=True,
            followed_source_ids={uuid4(), uuid4()},
        ),
        timeout=5.0,
    )

    # Plancher atteint, suivies d'abord puis backfill.
    assert len(result) >= ScoringWeights.THEMATIC_HARD_FLOOR
    assert result[: len(followed)] == followed, "followed sources must come first"
    assert result[len(followed) :] == backfill, "backfill appended after followed"

    # La requête de backfill : curée, fenêtre 72h, exclut les sources suivies.
    backfill_sql = next((s for s in captured if " not in " in s.lower()), None)
    assert backfill_sql is not None, "expected a curated NOT IN backfill query"
    low = backfill_sql.lower()
    assert "is_curated" in low
    assert "published_at" in low and ">=" in low
    # Filtre thème hérité du `query` (chemin (1) ou (2) du theme focus filter).
    assert "contents.theme = " in low or "sources.theme = " in low


@pytest.mark.asyncio
async def test_thematic_backfill_carries_serein_filter():
    """En mode serein, le backfill réutilise le `query` déjà filtré serein →
    la requête curée porte la condition is_serene."""
    service, session = _make_service()
    captured: list[str] = []
    followed = [_mock_content() for _ in range(2)]
    backfill = [_mock_content() for _ in range(5)]
    session.scalars = _stub_scalars_two_pools(captured, followed, backfill)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="science",
            personalized=True,
            followed_source_ids={uuid4()},
            serein=True,
        ),
        timeout=5.0,
    )

    backfill_sql = next((s for s in captured if " not in " in s.lower()), None)
    assert backfill_sql is not None
    assert "is_serene" in backfill_sql.lower(), (
        "serein backfill must carry the is_serene filter inherited from query"
    )


@pytest.mark.asyncio
async def test_thematic_backfill_skipped_when_followed_pool_sufficient():
    """Pool suivi ≥ plancher → aucune requête de backfill (pas de NOT IN)."""
    service, session = _make_service()
    captured: list[str] = []
    # 6 ≥ THEMATIC_HARD_FLOOR (5) mais < THEMATIC_MIN_POOL_SIZE (8) : la fenêtre
    # adaptative tourne, mais le plancher est dépassé → pas de backfill.
    followed = [_mock_content() for _ in range(6)]
    session.scalars = _stub_scalars_two_pools(captured, followed, [])

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert not any(" not in " in s.lower() for s in captured), (
        "no curated backfill query should be issued when the followed pool "
        "already meets the floor"
    )


@pytest.mark.asyncio
async def test_thematic_backfill_skipped_zero_followed():
    """Zéro source suivie → branche curée directe, pas de backfill (pas de
    NOT IN sur les sources suivies)."""
    service, session = _make_service()
    captured: list[str] = []
    followed = [_mock_content() for _ in range(2)]
    session.scalars = _stub_scalars_two_pools(captured, followed, [])

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids=set(),
        ),
        timeout=5.0,
    )

    assert not any(" not in " in s.lower() for s in captured), (
        "zero-followed case is already curated-only; no backfill expected"
    )


# ---------------------------------------------------------------------------
# `is_personalized_theme_mode` flag : utilisé pour activer la fenêtre de
# fraîcheur (adaptative 24/48/72h — Fix #2), la restriction aux sources suivies
# et le boost ORDER BY user_subtopics dans `_get_candidates`. Décision PO
# 2026-06-01 : ce mode route vers le PillarScoringEngine (chemin scoré) — il
# saute l'early-return chrono pur ET la compression regroupement/diversification.
# Supersede l'approche top-3 "essentiel-grade" (#710). Le routage et le
# reclassement sont couverts par tests/test_thematic_curation.py +
# scripts/prove_thematic_scoring.py.
# ---------------------------------------------------------------------------


class TestPersonalizedThemeModeDispatch:
    """Verify the dispatch flag governing the 24h+followed+subtopic-boost path."""

    def test_personalized_with_theme_activates_personalized_mode(self):
        assert (
            is_personalized_theme_mode(
                personalized=True, theme="tech", topic=None, source_uuid=None
            )
            is True
        )

    def test_personalized_with_topic_activates_personalized_mode(self):
        # Story 22.1: custom-topic favorites send `topic=<UUID>` and must
        # also benefit from the 24h+followed+subtopic-boost restrictions.
        assert (
            is_personalized_theme_mode(
                personalized=True, theme=None, topic="some-uuid", source_uuid=None
            )
            is True
        )

    def test_explicit_chip_without_personalized_stays_chronological(self):
        # The exploration / "tout voir" path keeps pure-recency ordering.
        assert (
            is_personalized_theme_mode(
                personalized=False, theme="tech", topic=None, source_uuid=None
            )
            is False
        )

    def test_default_feed_without_theme_is_not_personalized_theme(self):
        # The home /feed (no theme/topic) goes through the standard
        # chronological-diversified or pour_vous scoring path — not this dispatch.
        assert (
            is_personalized_theme_mode(
                personalized=True, theme=None, topic=None, source_uuid=None
            )
            is False
        )

    def test_personalized_source_activates_personalized_mode(self):
        # PR « Sources dans la Tournée » : une section source favorite
        # (?source_id=… &personalized=true) est désormais classée par les mêmes
        # piliers que les thèmes (fenêtre adaptative 24→48→72h), donc le mode
        # personnalisé doit s'activer pour source seule.
        assert (
            is_personalized_theme_mode(
                personalized=True,
                theme=None,
                topic=None,
                source_uuid="some-source-uuid",
            )
            is True
        )

    def test_source_without_personalized_stays_chronological(self):
        # Flâner épingle une source SANS personalized → reste chronologique
        # (le filtre source_id court-circuite vers l'early-return chrono).
        assert (
            is_personalized_theme_mode(
                personalized=False,
                theme=None,
                topic=None,
                source_uuid="some-source-uuid",
            )
            is False
        )


# ---------------------------------------------------------------------------
# `apply_theme_focus_filter` — bug curation 2026-05-31.
#
# Un article frais NON classifié (`Content.theme IS NULL`) d'une source
# généraliste (ex: Le Monde, theme="international", secondary_themes incluant
# "tech"/"science") ne doit PAS apparaître dans les sections Technologie/Science.
# Le chemin "bénéfice du doute" ne s'appuie désormais que sur le thème PRINCIPAL
# de la source, jamais sur ses `secondary_themes`.
# ---------------------------------------------------------------------------


class TestThemeFocusFilterUnclassified:
    """Le filtre thématique ne fuit plus via les `secondary_themes`."""

    def _compiled_sql(self, theme_slug: str) -> str:
        from sqlalchemy import select

        from app.models.content import Content
        from app.services.recommendation.filter_presets import (
            apply_theme_focus_filter,
        )

        query = apply_theme_focus_filter(select(Content), theme_slug)
        return str(query.compile(compile_kwargs={"literal_binds": False}))

    def test_unclassified_path_uses_source_primary_theme_only(self):
        sql = self._compiled_sql("tech")
        # Chemin (1) : article classifié dans le thème.
        assert "contents.theme = " in sql
        # Chemin (2) : sous-requête sur le thème PRINCIPAL de la source.
        assert "sources.theme = " in sql
        # Garde la borne "non classifié" sur le chemin (2).
        assert "contents.theme IS NULL" in sql

    def test_secondary_themes_no_longer_referenced(self):
        sql = self._compiled_sql("tech")
        # Régression : les secondary_themes déversaient les articles non
        # classifiés des sources généralistes dans des sections sans rapport.
        assert "secondary_themes" not in sql


# ── Repli « pas d'article récent » sur les sections SOURCE ───────────────────


def _stub_scalars_by_call(captured: list, per_call: list):
    """`session.scalars` retournant un résultat différent par appel successif.

    `per_call[i]` = la liste d'items renvoyée au i-ème appel (le dernier élément
    est réutilisé si plus d'appels sont émis). Permet de simuler « les paliers
    24/48/72h ne ramènent rien, mais la fenêtre 30 j (4ᵉ appel) ramène des
    articles anciens »."""

    state = {"i": 0}

    async def _scalars(stmt):
        captured.append(str(stmt.compile(compile_kwargs={"literal_binds": False})))
        idx = min(state["i"], len(per_call) - 1)
        state["i"] += 1
        r = MagicMock()
        r.all.return_value = per_call[idx]
        return r

    return _scalars


@pytest.mark.asyncio
async def test_source_stale_fallback_when_no_recent_article():
    """source + personalized : aucun article ≤72h (3 paliers vides) mais des
    articles ≤30 j → la 4ᵉ requête (repli 720h) remplit la section et lève le
    flag `source_no_recent_source`."""
    service, session = _make_service()
    captured: list[str] = []
    stale = [_mock_content()]
    # Paliers 24/48/72h vides, puis la fenêtre 30 j ramène un article ancien.
    session.scalars = _stub_scalars_by_call(captured, [[], [], [], stale])

    result = await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            source_id=uuid4(),
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert result, "le repli 30 j doit remplir la section avec des articles anciens"
    assert service.source_no_recent_source is True
    # 3 paliers adaptatifs + 1 requête de repli.
    assert len(captured) == 4, f"attendu 4 requêtes, vu {len(captured)}"


@pytest.mark.asyncio
async def test_source_no_stale_fallback_when_fresh_article():
    """source + personalized : un article frais (≤72h) → pas de repli, flag à
    False."""
    service, session = _make_service()
    captured: list[str] = []
    fresh = [_mock_content() for _ in range(8)]
    session.scalars = _stub_scalars_by_call(captured, [fresh])

    result = await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            source_id=uuid4(),
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert result, "section non vide avec un article frais"
    assert service.source_no_recent_source is False
    # Le pool ≥ seuil dès le 1er palier → pas de requête de repli.
    assert len(captured) == 1


@pytest.mark.asyncio
async def test_source_no_fallback_flag_when_totally_empty():
    """source + personalized : aucun article même > 30 j → section vide, flag à
    False (l'empty-state « aucun article » s'affichera, pas « Pas d'article
    récent. »)."""
    service, session = _make_service()
    captured: list[str] = []
    # Tous les paliers ET le repli 30 j sont vides.
    session.scalars = _stub_scalars_by_call(captured, [[]])

    result = await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            source_id=uuid4(),
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert result == []
    assert service.source_no_recent_source is False
    # 3 paliers vides + 1 repli vide.
    assert len(captured) == 4
