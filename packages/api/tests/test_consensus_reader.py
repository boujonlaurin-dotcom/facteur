"""Exposition Reader de l'analyse des angles 6C (Story 35.2).

Ce qui est testé ici est ce que la PR 2 promet au front : la résolution
`content_id → analyse` (1:N assumé, fraîcheur, tie-break), l'état dérivé à la
lecture, la copie cache-safe (l'attribution par user ne contamine jamais le
corps partagé), et le write-through du chemin paresseux.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.coverage_analysis import (
    CONSENSUS_STATE_AVAILABLE,
    CONSENSUS_STATE_UNAVAILABLE,
    CoverageAnalysis,
    CoverageAnalysisArticle,
)
from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.services import consensus_reader
from app.services.consensus_reader import (
    attach_consensus_blocks,
    get_domain_notoriety,
    get_followed_domains,
    load_analysis_for_content,
    pick_analysis_row,
    write_through_analysis,
)


@pytest.fixture(autouse=True)
def _clear_attribution_caches():
    consensus_reader.invalidate_caches()
    yield
    consensus_reader.invalidate_caches()


def _row(state: str, generated_at: datetime, consensus: dict | None = None):
    return SimpleNamespace(
        state=state,
        generated_at=generated_at,
        consensus=consensus if consensus is not None else {"agreements": []},
        qualifier=None,
    )


NOW = datetime(2026, 8, 21, 12, 0, tzinfo=UTC)


class TestPickAnalysisRow:
    def test_empty_returns_none(self):
        assert pick_analysis_row([]) is None

    def test_prefers_available_over_newer_unavailable(self):
        """La ligne du matin (pipeline, corpus complet) est bonne ; un recompute
        on-demand raté plus tard ne doit pas la masquer."""
        morning = _row(CONSENSUS_STATE_AVAILABLE, NOW - timedelta(hours=5))
        failed_recompute = _row(CONSENSUS_STATE_UNAVAILABLE, NOW)

        assert pick_analysis_row([failed_recompute, morning]) is morning

    def test_among_available_rows_newest_wins(self):
        old = _row(CONSENSUS_STATE_AVAILABLE, NOW - timedelta(hours=30))
        fresh = _row(CONSENSUS_STATE_AVAILABLE, NOW)

        assert pick_analysis_row([old, fresh]) is fresh

    def test_only_unavailable_rows_still_resolve(self):
        """Un échec définitif persisté se sert (le Reader ne doit pas promettre
        « en cours » pour toujours)."""
        failed = _row(CONSENSUS_STATE_UNAVAILABLE, NOW)
        assert pick_analysis_row([failed]) is failed


def _body(perspectives_count: int = 3, coverage_count: int | None = None) -> dict:
    return {
        "content_id": str(uuid4()),
        "perspectives": [
            {
                "source_domain": f"src{i}.fr",
                "bias_stance": "left" if i % 2 else "right",
            }
            for i in range(perspectives_count)
        ],
        "coverage_count": (
            coverage_count if coverage_count is not None else perspectives_count + 1
        ),
        "source_bias_stance": "center-right",
    }


class TestAttachConsensusBlocks:
    @pytest.mark.asyncio
    async def test_available_row_is_served_and_body_stays_untouched(self):
        """Le corps vit dans `_perspectives_cache` (partagé entre users) :
        l'attribution par user ne doit jamais y entrer."""
        body = _body()
        stored = {
            "qualifier": "varied",
            "agreements": [
                {
                    "text": "Un accord servi tel quel au Reader.",
                    "source_domains": ["src0.fr", "src1.fr", "src2.fr"],
                    "support_count": 3,
                }
            ],
            "disagreements": [],
            "cta": {"agreement": None, "disagreement": None},
        }
        row = _row(CONSENSUS_STATE_AVAILABLE, NOW, consensus=stored)
        db = AsyncMock()
        with (
            patch.object(
                consensus_reader,
                "load_analysis_for_content",
                AsyncMock(return_value=row),
            ),
            patch.object(
                consensus_reader,
                "get_followed_domains",
                AsyncMock(return_value=frozenset({"src2.fr"})),
            ),
            patch.object(
                consensus_reader, "get_domain_notoriety", AsyncMock(return_value={})
            ),
        ):
            served = await attach_consensus_blocks(
                db, body, content_id=uuid4(), user_id=uuid4()
            )

        assert served is not body
        assert "consensus" not in body and "display" not in body
        assert served["consensus"]["state"] == "available"
        assert served["consensus"]["qualifier"] == "varied"
        # La source suivie passe en tête des logos pour CET utilisateur.
        agreement = served["consensus"]["agreements"][0]
        assert agreement["display_domains"][0] == "src2.fr"
        assert agreement["plus_count"] == 1
        assert served["display"]["has_ai_card"] is True

    @pytest.mark.asyncio
    async def test_unavailable_row_serves_definitive_failure(self):
        row = _row(CONSENSUS_STATE_UNAVAILABLE, NOW)
        with patch.object(
            consensus_reader, "load_analysis_for_content", AsyncMock(return_value=row)
        ):
            served = await attach_consensus_blocks(
                AsyncMock(), _body(), content_id=uuid4(), user_id=uuid4()
            )

        assert served["consensus"]["state"] == "unavailable"
        assert served["consensus"]["agreements"] == []

    @pytest.mark.asyncio
    async def test_missing_row_with_enough_corpus_is_pending(self):
        with patch.object(
            consensus_reader, "load_analysis_for_content", AsyncMock(return_value=None)
        ):
            served = await attach_consensus_blocks(
                AsyncMock(),
                _body(perspectives_count=2),
                content_id=uuid4(),
                user_id=uuid4(),
            )

        assert served["consensus"]["state"] == "pending"
        assert served["consensus"]["qualifier"] is None

    @pytest.mark.asyncio
    async def test_solo_subject_is_unavailable_not_pending(self):
        """1 média : ni le pipeline ni le chemin paresseux ne généreront —
        « analyse en cours » serait une promesse jamais tenue."""
        with patch.object(
            consensus_reader, "load_analysis_for_content", AsyncMock(return_value=None)
        ):
            served = await attach_consensus_blocks(
                AsyncMock(),
                _body(perspectives_count=0, coverage_count=1),
                content_id=uuid4(),
                user_id=uuid4(),
            )

        assert served["consensus"]["state"] == "unavailable"
        assert served["display"]["is_solo"] is True
        assert served["display"]["has_cta"] is False

    @pytest.mark.asyncio
    async def test_db_error_degrades_to_derived_state_never_500(self):
        db = AsyncMock()
        with patch.object(
            consensus_reader,
            "load_analysis_for_content",
            AsyncMock(side_effect=RuntimeError("db down")),
        ):
            served = await attach_consensus_blocks(
                db, _body(), content_id=uuid4(), user_id=uuid4()
            )

        assert served["consensus"]["state"] == "pending"
        assert served["display"]["has_cards"] is True
        db.rollback.assert_awaited()

    @pytest.mark.asyncio
    async def test_pivot_domain_inherits_the_pivot_bias(self):
        """Un domaine de constat absent des alternatives est le média lu :
        son biais est `source_bias_stance`, pas « unknown »."""
        body = _body(perspectives_count=2)  # src0.fr (right), src1.fr (left)
        stored = {
            "agreements": [],
            "disagreements": [
                {
                    "text": "Un désaccord porté aussi par le média lu.",
                    "source_domains": ["pivot.fr", "src1.fr"],
                    "support_count": 2,
                }
            ],
        }
        row = _row(CONSENSUS_STATE_AVAILABLE, NOW, consensus=stored)
        captured = {}

        def _spy_serve(stored_arg, **kwargs):
            captured.update(kwargs)
            return consensus_reader.serve_consensus_block(stored_arg, **kwargs)

        with (
            patch.object(
                consensus_reader,
                "load_analysis_for_content",
                AsyncMock(return_value=row),
            ),
            patch.object(
                consensus_reader,
                "get_followed_domains",
                AsyncMock(return_value=frozenset()),
            ),
            patch.object(
                consensus_reader, "get_domain_notoriety", AsyncMock(return_value={})
            ),
            patch.object(consensus_reader, "serve_consensus_block", _spy_serve),
        ):
            await attach_consensus_blocks(
                AsyncMock(), body, content_id=uuid4(), user_id=uuid4()
            )

        assert captured["bias_by_domain"]["pivot.fr"] == "center-right"
        assert captured["bias_by_domain"]["src1.fr"] == "left"


def _scalars_result(values):
    result = MagicMock()
    scalars = MagicMock()
    scalars.all.return_value = values
    result.scalars.return_value = scalars
    return result


class TestAttributionCaches:
    @pytest.mark.asyncio
    async def test_followed_domains_cached_per_user(self):
        db = AsyncMock()
        db.execute = AsyncMock(
            return_value=_scalars_result(["https://www.lemonde.fr/rss"])
        )
        user_id = uuid4()

        first = await get_followed_domains(db, user_id)
        second = await get_followed_domains(db, user_id)

        assert first == frozenset({"lemonde.fr"})
        assert second is first
        db.execute.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_notoriety_cached_globally_and_keeps_best_per_domain(self):
        rows = MagicMock()
        rows.all.return_value = [
            ("https://lemonde.fr/rss", True, 12),
            # Second flux du même domaine, moins suivi : le meilleur gagne.
            ("https://www.lemonde.fr/une", False, 3),
            ("https://autre.fr", False, 5),
        ]
        db = AsyncMock()
        db.execute = AsyncMock(return_value=rows)

        first = await get_domain_notoriety(db)
        second = await get_domain_notoriety(db)

        assert first["lemonde.fr"] == (12, True)
        assert first["autre.fr"] == (5, False)
        assert second is first
        db.execute.assert_awaited_once()


# --- DB de test : requêtes réelles ------------------------------------------


async def _seed_analysis(db_session, content_id, *, state="available", age_hours=1):
    row = CoverageAnalysis(
        id=uuid4(),
        subject_key=f"key-{uuid4()}",
        consensus={"state": state, "agreements": [], "disagreements": []},
        state=state,
        corpus_domains=["a.fr"],
        coverage_count=3,
        generated_at=datetime.now(UTC) - timedelta(hours=age_hours),
    )
    db_session.add(row)
    await db_session.flush()
    db_session.add(
        CoverageAnalysisArticle(coverage_analysis_id=row.id, content_id=content_id)
    )
    await db_session.commit()
    return row


async def _make_content_row(db_session, source):
    from app.models.content import Content
    from app.models.enums import ContentType

    content = Content(
        id=uuid4(),
        source_id=source.id,
        title="Article",
        url=f"https://example.com/{uuid4()}",
        guid=f"guid-{uuid4()}",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
    )
    db_session.add(content)
    await db_session.commit()
    return content


class TestLoadAnalysisForContent:
    @pytest.mark.asyncio
    async def test_fresh_row_resolves_stale_row_does_not(self, db_session, test_source):
        content = await _make_content_row(db_session, test_source)
        stale_content = await _make_content_row(db_session, test_source)
        fresh = await _seed_analysis(db_session, content.id, age_hours=1)
        await _seed_analysis(db_session, stale_content.id, age_hours=100)

        resolved = await load_analysis_for_content(db_session, content.id)
        stale = await load_analysis_for_content(db_session, stale_content.id)

        assert resolved is not None and resolved.id == fresh.id
        assert stale is None

    @pytest.mark.asyncio
    async def test_one_to_many_resolves_available_first(self, db_session, test_source):
        """La dette 1:N de la PR 1 : deux lignes pour le même article, la
        `available` gagne même si l'`unavailable` est plus récente."""
        content = await _make_content_row(db_session, test_source)
        good = await _seed_analysis(
            db_session, content.id, state="available", age_hours=6
        )
        await _seed_analysis(db_session, content.id, state="unavailable", age_hours=1)

        resolved = await load_analysis_for_content(db_session, content.id)

        assert resolved is not None and resolved.id == good.id


class TestAttributionQueries:
    @pytest.mark.asyncio
    async def test_followed_domains_reads_followed_and_favorite_only(
        self, db_session, test_source
    ):
        user_id = uuid4()
        hidden_source = Source(
            id=uuid4(),
            name="Cachée",
            url="https://cachee.fr",
            feed_url=f"https://cachee.fr/{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
        )
        db_session.add(hidden_source)
        db_session.add(
            UserSource(
                user_id=user_id,
                source_id=test_source.id,
                state=InterestState.FAVORITE,
            )
        )
        db_session.add(
            UserSource(
                user_id=user_id,
                source_id=hidden_source.id,
                state=InterestState.HIDDEN,
            )
        )
        await db_session.commit()

        domains = await get_followed_domains(db_session, user_id)

        assert domains == frozenset({"example.com"})

    @pytest.mark.asyncio
    async def test_notoriety_counts_followers(self, db_session, test_source):
        for _ in range(2):
            db_session.add(
                UserSource(
                    user_id=uuid4(),
                    source_id=test_source.id,
                    state=InterestState.FOLLOWED,
                )
            )
        await db_session.commit()

        notoriety = await get_domain_notoriety(db_session)

        assert notoriety["example.com"] == (2, False)


class TestWriteThrough:
    @pytest.mark.asyncio
    async def test_persists_row_and_links_known_articles_only(
        self, db_session, test_source
    ):
        """Les résultats Google News n'ont pas de `content_id` : pas de lien,
        c'est attendu — ils n'existent pas dans `contents`."""
        pivot = await _make_content_row(db_session, test_source)
        internal = await _make_content_row(db_session, test_source)
        raw = {
            "analysis": "Etabli.\n\n→ débat",
            "divergence_level": "medium",
            "agreements": [
                {
                    "text": "Un accord porté par le pivot et une alternative.",
                    "source_domains": ["example.com", "alt.fr"],
                }
            ],
        }
        perspectives = [
            {
                "content_id": str(internal.id),
                "source_domain": "alt.fr",
                "bias_stance": "left",
            },
            {"source_domain": "gnews.fr", "bias_stance": "unknown"},
        ]

        payload = await write_through_analysis(
            db_session,
            raw_result=raw,
            pivot_content_id=pivot.id,
            pivot_domain="example.com",
            pivot_bias="center",
            perspectives=perspectives,
            coverage_count=3,
        )
        await db_session.commit()

        assert payload.state == "available"
        assert payload.agreements[0].support_count == 2

        row = (
            await db_session.execute(
                select(CoverageAnalysis).where(CoverageAnalysis.coverage_count == 3)
            )
        ).scalar_one()
        linked = (
            (
                await db_session.execute(
                    select(CoverageAnalysisArticle.content_id).where(
                        CoverageAnalysisArticle.coverage_analysis_id == row.id
                    )
                )
            )
            .scalars()
            .all()
        )
        assert set(linked) == {pivot.id, internal.id}

    @pytest.mark.asyncio
    async def test_reposting_the_same_corpus_upserts(self, db_session, test_source):
        pivot = await _make_content_row(db_session, test_source)
        raw = {
            "agreements": [
                {
                    "text": "Un accord recevable et attribué.",
                    "source_domains": ["example.com"],
                }
            ]
        }

        for _ in range(2):
            await write_through_analysis(
                db_session,
                raw_result=raw,
                pivot_content_id=pivot.id,
                pivot_domain="example.com",
                pivot_bias="center",
                perspectives=[],
                coverage_count=2,
            )
            await db_session.commit()

        count = (
            await db_session.execute(select(func.count()).select_from(CoverageAnalysis))
        ).scalar_one()
        assert count == 1
