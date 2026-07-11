"""Tests for digest_generation_job — editorial pipeline result handling."""

import datetime
from unittest.mock import AsyncMock, MagicMock, Mock, patch
from uuid import uuid4

import pytest

from app.jobs.digest_generation_job import (
    _extract_editorial_actu_ids_from_items,
)
from app.services.editorial.schemas import (
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
)


def _make_editorial_result(n_subjects=2):
    """Build a minimal EditorialPipelineResult for testing."""
    now = datetime.datetime.now(datetime.UTC)
    subjects = []
    for i in range(n_subjects):
        subjects.append(
            EditorialSubject(
                rank=i + 1,
                topic_id=f"topic_{i}",
                label=f"Subject {i}",
                selection_reason="trending",
                deep_angle="angle",
                actu_article=MatchedActuArticle(
                    content_id=uuid4(),
                    title=f"Actu {i}",
                    source_name="Source",
                    source_id=uuid4(),
                    is_user_source=True,
                    published_at=now,
                ),
                deep_article=MatchedDeepArticle(
                    content_id=uuid4(),
                    title=f"Deep {i}",
                    source_name="Source Deep",
                    source_id=uuid4(),
                    match_reason="semantic",
                    published_at=now,
                ),
            )
        )
    return EditorialPipelineResult(
        subjects=subjects,
        metadata={"timing": 1.0},
    )


@pytest.fixture
def mock_session():
    session = AsyncMock()
    session.flush = AsyncMock()
    session.add = Mock()
    session.scalar = AsyncMock(return_value=None)
    # Default execute result: empty .all() and empty .scalars().all() so that
    # load_serein_preferences / other queries don't blow up on coroutine
    # auto-generated children of AsyncMock.
    _default_result = MagicMock()
    _default_result.all = Mock(return_value=[])
    _default_scalars = MagicMock()
    _default_scalars.all = Mock(return_value=[])
    _default_result.scalars = Mock(return_value=_default_scalars)
    session.execute = AsyncMock(return_value=_default_result)
    session.commit = AsyncMock()
    return session


@pytest.fixture
def job():
    from app.jobs.digest_generation_job import DigestGenerationJob

    return DigestGenerationJob(batch_size=10)


class TestEditorialBatchHandling:
    """Batch job correctly handles EditorialPipelineResult from select_for_user."""

    @pytest.mark.asyncio
    async def test_editorial_pipeline_result_stored_successfully(
        self, job, mock_session
    ):
        """When select_for_user returns EditorialPipelineResult, store via editorial path."""
        user_id = uuid4()
        target_date = datetime.date.today()
        editorial_result = _make_editorial_result()

        mock_digest = Mock()
        mock_digest.id = uuid4()

        # Mock: no existing digest (UserProfile + 2x DailyDigest checks)
        mock_session.scalar = AsyncMock(return_value=None)

        with (
            patch("app.jobs.digest_generation_job.DigestSelector") as mock_selector_cls,
            patch("app.services.digest_service.DigestService") as mock_svc_cls,
            patch("app.jobs.digest_generation_job.select"),
        ):
            mock_selector = AsyncMock()
            mock_selector.select_for_user = AsyncMock(return_value=editorial_result)
            mock_selector_cls.return_value = mock_selector

            mock_svc = AsyncMock()
            mock_svc._create_digest_record_editorial = AsyncMock(
                return_value=mock_digest
            )
            mock_svc_cls.return_value = mock_svc

            await job._generate_digest_for_user(
                mock_session, user_id, target_date, None
            )

        # Loop runs for both is_serene=False and is_serene=True → 2 calls
        assert mock_svc._create_digest_record_editorial.await_count == 2
        assert job.stats["success"] == 2
        assert job.stats["failed"] == 0

    @pytest.mark.asyncio
    async def test_generate_digest_returns_persisted_editorial_actu_ids(
        self, job, mock_session
    ):
        """Pas de recul precompute uses the actu ids actually served to readers."""
        user_id = uuid4()
        target_date = datetime.date.today()
        editorial_result = _make_editorial_result()

        mock_digest = Mock()
        mock_digest.id = uuid4()
        mock_session.scalar = AsyncMock(return_value=None)

        with (
            patch("app.jobs.digest_generation_job.DigestSelector") as mock_selector_cls,
            patch("app.services.digest_service.DigestService") as mock_svc_cls,
            patch("app.jobs.digest_generation_job.select"),
        ):
            mock_selector = AsyncMock()
            mock_selector.select_for_user = AsyncMock(return_value=editorial_result)
            mock_selector_cls.return_value = mock_selector

            mock_svc = AsyncMock()
            mock_svc._create_digest_record_editorial = AsyncMock(
                return_value=mock_digest
            )
            mock_svc_cls.return_value = mock_svc

            result = await job._generate_digest_for_user(
                mock_session, user_id, target_date, None
            )

        expected = {
            subject.actu_article.content_id
            for subject in editorial_result.subjects
            if subject.actu_article is not None
        }
        assert result == expected

    @pytest.mark.asyncio
    async def test_editorial_pipeline_result_empty_subjects_fails(
        self, job, mock_session
    ):
        """When _create_digest_record_editorial returns None (empty subjects), count as failed."""
        user_id = uuid4()
        target_date = datetime.date.today()
        editorial_result = _make_editorial_result()

        mock_session.scalar = AsyncMock(return_value=None)

        with (
            patch("app.jobs.digest_generation_job.DigestSelector") as mock_selector_cls,
            patch("app.services.digest_service.DigestService") as mock_svc_cls,
            patch("app.jobs.digest_generation_job.select"),
        ):
            mock_selector = AsyncMock()
            mock_selector.select_for_user = AsyncMock(return_value=editorial_result)
            mock_selector_cls.return_value = mock_selector

            mock_svc = AsyncMock()
            mock_svc._create_digest_record_editorial = AsyncMock(return_value=None)
            mock_svc_cls.return_value = mock_svc

            await job._generate_digest_for_user(
                mock_session, user_id, target_date, None
            )

        # Loop runs for both is_serene=False and is_serene=True → 2 failures
        assert job.stats["failed"] == 2
        assert job.stats["success"] == 0


class TestVariantIsolation:
    """One variant failing should not kill the other for the same user."""

    @pytest.mark.asyncio
    async def test_serein_failure_does_not_block_pour_vous(self, job, mock_session):
        """When the serein variant raises, the normal variant still records success."""
        user_id = uuid4()
        target_date = datetime.date.today()
        editorial_result = _make_editorial_result()

        mock_session.scalar = AsyncMock(return_value=None)

        call_log = []

        async def flaky_create(*args, **kwargs):
            is_serene = kwargs.get("is_serene", False)
            call_log.append(is_serene)
            if is_serene:
                raise RuntimeError("serein blew up")
            mock_digest = Mock()
            mock_digest.id = uuid4()
            return mock_digest

        with (
            patch("app.jobs.digest_generation_job.DigestSelector") as mock_selector_cls,
            patch("app.services.digest_service.DigestService") as mock_svc_cls,
            patch("app.jobs.digest_generation_job.select"),
        ):
            mock_selector = AsyncMock()
            mock_selector.select_for_user = AsyncMock(return_value=editorial_result)
            mock_selector_cls.return_value = mock_selector

            mock_svc = AsyncMock()
            mock_svc._create_digest_record_editorial = AsyncMock(
                side_effect=flaky_create
            )
            mock_svc_cls.return_value = mock_svc

            # Must NOT raise — variant isolation contains the error
            await job._generate_digest_for_user(
                mock_session, user_id, target_date, None
            )

        assert False in call_log, "pour_vous variant should have been attempted"
        assert True in call_log, "serein variant should have been attempted"
        assert job.stats["success"] == 1
        assert job.stats["failed"] == 1


class TestGrilleSessionIsolation:
    """Le mot du jour s'isole dans sa propre session (régression PYTHON-5G).

    Avant le fix, `_match_grille_featured_article` réutilisait la session batch
    partagée. Si une pré-étape (trending / editorial precompute) échouait sans
    rollback, la session restait en PENDING_ROLLBACK et `ensure_daily_puzzle`
    levait un PendingRollbackError. Désormais l'étape ouvre sa propre session
    courte → totalement isolée de l'état de la session batch.
    """

    @pytest.mark.asyncio
    async def test_match_grille_uses_own_session_and_commits(self, job):
        target_date = datetime.date.today()

        grille_session = AsyncMock()
        grille_session.commit = AsyncMock()
        cm = MagicMock()
        cm.__aenter__ = AsyncMock(return_value=grille_session)
        cm.__aexit__ = AsyncMock(return_value=False)
        mock_safe_session = MagicMock(return_value=cm)

        with (
            patch(
                "app.jobs.digest_generation_job.safe_async_session",
                mock_safe_session,
            ),
            patch(
                "app.services.grille_seed.ensure_daily_puzzle",
                new=AsyncMock(),
            ) as mock_ensure,
            patch(
                "app.services.grille_matcher.apply_hybrid_word",
                new=AsyncMock(return_value=True),
            ) as mock_apply,
        ):
            await job._match_grille_featured_article(target_date, None)

        # Une session dédiée a été ouverte puis committée (jamais la batch).
        mock_safe_session.assert_called_once()
        grille_session.commit.assert_awaited_once()
        # ensure_daily_puzzle / apply_hybrid_word opèrent sur CETTE session.
        assert mock_ensure.await_args.args[0] is grille_session
        assert mock_apply.await_args.args[0] is grille_session

    @pytest.mark.asyncio
    async def test_match_grille_swallows_errors_best_effort(self, job):
        """Une erreur du matcher ne remonte jamais : le digest prime."""
        target_date = datetime.date.today()
        cm = MagicMock()
        cm.__aenter__ = AsyncMock(return_value=AsyncMock())
        cm.__aexit__ = AsyncMock(return_value=False)

        with (
            patch(
                "app.jobs.digest_generation_job.safe_async_session",
                MagicMock(return_value=cm),
            ),
            patch(
                "app.services.grille_seed.ensure_daily_puzzle",
                new=AsyncMock(side_effect=RuntimeError("boom")),
            ),
            patch("app.services.grille_matcher.apply_hybrid_word", new=AsyncMock()),
            patch("app.jobs.digest_generation_job.sentry_sdk") as mock_sentry,
        ):
            # Ne doit PAS lever.
            await job._match_grille_featured_article(target_date, None)

        mock_sentry.capture_exception.assert_called_once()


class TestDeepPrecomputeIdExtraction:
    """Extract real reader lookup ids from persisted editorial digest JSON."""

    def test_extracts_only_subject_actu_ids(self):
        actu_id = uuid4()
        extra_id = uuid4()

        result = _extract_editorial_actu_ids_from_items(
            {
                "format_version": "editorial_v2",
                "subjects": [
                    {
                        "actu_article": {"content_id": str(actu_id)},
                        "extra_actu_articles": [{"content_id": str(extra_id)}],
                    },
                    {"actu_article": None},
                ],
            }
        )

        assert result == {actu_id}

    def test_ignores_non_editorial_or_bad_payloads(self):
        assert (
            _extract_editorial_actu_ids_from_items([{"content_id": str(uuid4())}])
            == set()
        )
        assert _extract_editorial_actu_ids_from_items({"subjects": "bad"}) == set()
        assert (
            _extract_editorial_actu_ids_from_items(
                {"subjects": [{"actu_article": {"content_id": "not-a-uuid"}}]}
            )
            == set()
        )


class TestGlobalCandidatePool:
    """The batch job should fetch a user-agnostic candidate pool for editorial ctx."""

    @pytest.mark.asyncio
    async def test_get_global_candidates_returns_empty_on_error(self, job):
        """DB failure should return empty list rather than raise."""
        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(side_effect=Exception("db down"))

        result = await job._get_global_candidates(mock_session)
        assert result == []

    @pytest.mark.asyncio
    async def test_get_global_candidates_returns_list(self, job):
        """Happy path returns a list of Content objects from the query."""
        mock_session = AsyncMock()
        scalars_mock = MagicMock()
        fake_content = [Mock(), Mock(), Mock()]
        scalars_mock.all = MagicMock(return_value=fake_content)
        result_mock = MagicMock()
        result_mock.scalars = MagicMock(return_value=scalars_mock)
        mock_session.execute = AsyncMock(return_value=result_mock)

        result = await job._get_global_candidates(mock_session)
        assert len(result) == 3

    @pytest.mark.asyncio
    async def test_get_global_candidates_serein_applies_filter(self, job):
        """Serein mode applies the hard `is_good_news` filter.

        Replaces the legacy theme/keyword fallback : the bonnes-nouvelles
        rebrand introduced `Content.is_good_news` as the single signal, with
        no keyword fallback (we accept a partial digest rather than ship a
        false positive).
        """
        mock_session = AsyncMock()
        scalars_mock = MagicMock()
        scalars_mock.all = MagicMock(return_value=[])
        result_mock = MagicMock()
        result_mock.scalars = MagicMock(return_value=scalars_mock)
        mock_session.execute = AsyncMock(return_value=result_mock)

        await job._get_global_candidates(mock_session, mode="serein")

        stmt = mock_session.execute.call_args.args[0]
        compiled = str(stmt.compile(compile_kwargs={"literal_binds": False})).lower()
        assert "contents.is_good_news = true" in compiled, (
            f"serein pool must filter on is_good_news=True; got:\n{compiled}"
        )

    @pytest.mark.asyncio
    async def test_get_global_candidates_pour_vous_no_source_join(self, job):
        """Pour-vous mode keeps the historical (no-filter) SQL shape."""
        mock_session = AsyncMock()
        scalars_mock = MagicMock()
        scalars_mock.all = MagicMock(return_value=[])
        result_mock = MagicMock()
        result_mock.scalars = MagicMock(return_value=scalars_mock)
        mock_session.execute = AsyncMock(return_value=result_mock)

        await job._get_global_candidates(mock_session, mode="pour_vous")

        stmt = mock_session.execute.call_args.args[0]
        compiled = str(stmt.compile(compile_kwargs={"literal_binds": False})).lower()
        # No good-news filter applied — historical behaviour preserved
        assert "is_good_news = true" not in compiled


class TestFollowedSourceSlice:
    """P1: followed sources are unioned into the clustering pool."""

    @pytest.mark.asyncio
    async def test_followed_slice_unioned_and_deduped(self, job):
        """A followed-source article past the top-200 cut is added, deduped."""

        followed_src = uuid4()
        # recency slice: c1 (other source), c2 (followed, already present)
        c1 = Mock(id=uuid4(), source_id=uuid4())
        c2 = Mock(id=uuid4(), source_id=followed_src)
        # followed slice query returns c2 (dup) + c3 (new, older niche article)
        c3 = Mock(id=uuid4(), source_id=followed_src)

        def _result(items):
            scalars = MagicMock()
            scalars.all = MagicMock(return_value=items)
            res = MagicMock()
            res.scalars = MagicMock(return_value=scalars)
            return res

        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(
            side_effect=[_result([c1, c2]), _result([c2, c3])]
        )

        result = await job._get_global_candidates(
            mock_session, followed_source_ids={followed_src}
        )

        ids = [c.id for c in result]
        # c1, c2 from recency + c3 from followed slice (c2 deduped).
        assert ids == [c1.id, c2.id, c3.id]
        assert mock_session.execute.await_count == 2
        # Second query (followed slice) filters on source_id and keeps cutoff.
        followed_stmt = mock_session.execute.await_args_list[1].args[0]
        compiled = str(
            followed_stmt.compile(compile_kwargs={"literal_binds": False})
        ).lower()
        assert "contents.source_id in" in compiled
        assert "contents.published_at >=" in compiled

    @pytest.mark.asyncio
    async def test_no_followed_slice_when_empty(self, job):
        """Without followed sources, only the recency slice query runs."""
        scalars = MagicMock()
        scalars.all = MagicMock(return_value=[Mock(id=uuid4(), source_id=uuid4())])
        res = MagicMock()
        res.scalars = MagicMock(return_value=scalars)
        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(return_value=res)

        result = await job._get_global_candidates(
            mock_session, followed_source_ids=set()
        )
        assert len(result) == 1
        assert mock_session.execute.await_count == 1


class TestBatchFollowedSourceIds:
    """P1: the batch union of genuinely-followed source ids."""

    @pytest.mark.asyncio
    async def test_empty_user_ids_short_circuits(self, job):
        mock_session = AsyncMock()
        mock_session.execute = AsyncMock()
        result = await job._get_batch_followed_source_ids(mock_session, [])
        assert result == set()
        mock_session.execute.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_filters_on_followed_and_favorite_state(self, job):
        sid1, sid2 = uuid4(), uuid4()
        res = MagicMock()
        res.all = MagicMock(return_value=[(sid1,), (sid2,)])
        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(return_value=res)

        result = await job._get_batch_followed_source_ids(
            mock_session, [uuid4(), uuid4()]
        )
        assert result == {sid1, sid2}
        stmt = mock_session.execute.await_args.args[0]
        compiled = str(stmt.compile(compile_kwargs={"literal_binds": True})).lower()
        assert "state in" in compiled
        assert "'followed'" in compiled and "'favorite'" in compiled


class TestAntiDoubleDigestGuard:
    """S1-B in-function guard: run_digest_generation must short-circuit when a
    generation is already running, closing all 3 uncoordinated callers (cron,
    watchdog, startup catchup)."""

    @pytest.mark.asyncio
    async def test_skips_when_generation_already_running(self):
        import app.jobs.digest_generation_job as job_mod
        from app.jobs.digest_generation_job import run_digest_generation

        with (
            patch(
                "app.services.generation_state.is_generation_running",
                return_value=True,
            ),
            patch(
                "app.services.generation_state.mark_generation_started",
            ) as mock_start,
            patch.object(job_mod, "safe_async_session") as mock_safe_session,
        ):
            result = await run_digest_generation(target_date=datetime.date.today())

        assert result["skipped"] is True
        assert result["reason"] == "already_running"
        assert "stats" in result
        # Guard runs BEFORE mark_generation_started (which would clobber the
        # in-flight run's _started_at) and before opening any session.
        mock_start.assert_not_called()
        mock_safe_session.assert_not_called()

    @pytest.mark.asyncio
    async def test_proceeds_when_not_running(self):
        from contextlib import asynccontextmanager

        import app.jobs.digest_generation_job as job_mod
        from app.jobs.digest_generation_job import run_digest_generation

        mock_session = AsyncMock()

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        sentinel = {"success": True, "stats": {}}
        mock_job = MagicMock()
        mock_job.run = AsyncMock(return_value=sentinel)

        with (
            patch(
                "app.services.generation_state.is_generation_running",
                return_value=False,
            ),
            patch(
                "app.services.generation_state.mark_generation_started",
            ) as mock_start,
            patch(
                "app.services.generation_state.mark_generation_finished",
            ) as mock_finish,
            patch.object(job_mod, "DigestGenerationJob", return_value=mock_job),
            patch.object(job_mod, "safe_async_session", side_effect=lambda: fake_sm()),
        ):
            result = await run_digest_generation(target_date=datetime.date.today())

        assert result is sentinel
        mock_start.assert_called_once()
        mock_finish.assert_called_once()
        mock_job.run.assert_awaited_once()
        mock_session.commit.assert_awaited_once()


class TestGenerationStateSafetyTimeout:
    """generation_state auto-resets the running flag after _SAFETY_TIMEOUT so a
    crashed-but-not-finished run can't block on-demand generation forever."""

    def test_is_generation_running_auto_resets_after_timeout(self, monkeypatch):
        import app.services.generation_state as gs

        try:
            monkeypatch.setattr(gs.time, "monotonic", lambda: 1000.0)
            gs.mark_generation_started()
            assert gs.is_generation_running() is True

            # Still inside the safety window.
            monkeypatch.setattr(
                gs.time, "monotonic", lambda: 1000.0 + gs._SAFETY_TIMEOUT - 1
            )
            assert gs.is_generation_running() is True

            # Past the safety window → auto-reset to False.
            monkeypatch.setattr(
                gs.time, "monotonic", lambda: 1000.0 + gs._SAFETY_TIMEOUT + 1
            )
            assert gs.is_generation_running() is False
        finally:
            gs.mark_generation_finished()


class TestAxeCBatchTxRelease:
    """S1-C: on the SUCCESS path, run() rolls back + re-applies session timeouts
    after the trending read and before the editorial LLM precompute, so the
    batch session is not left idle-in-transaction during the 3-5 min of LLM."""

    @pytest.mark.asyncio
    async def test_rollback_and_timeouts_before_editorial_precompute(
        self, mock_session
    ):
        from contextlib import asynccontextmanager

        import app.jobs.digest_generation_job as job_mod
        from app.jobs.digest_generation_job import (
            DigestGenerationJob,
            GlobalTrendingContext,
        )

        job = DigestGenerationJob(batch_size=10)
        # Empty user list keeps the editorial precompute body + per-user batch
        # loop out of the way, isolating the trending → precompute boundary.
        job._get_active_users = AsyncMock(return_value=[])
        job._prune_old_highlights = AsyncMock()
        job._match_grille_featured_article = AsyncMock()

        fake_ctx = GlobalTrendingContext(
            trending_content_ids=set(),
            une_content_ids=set(),
            computed_at=datetime.datetime.now(datetime.UTC),
        )

        # Coverage read in finalize() opens its own short session.
        cov_session = AsyncMock()
        cov_session.scalar = AsyncMock(return_value=0)

        @asynccontextmanager
        async def fake_cov_sm():
            yield cov_session

        mock_session.rollback = AsyncMock()

        with (
            patch.object(job_mod, "DigestSelector") as mock_sel_cls,
            patch.object(
                job_mod, "apply_session_timeouts", new_callable=AsyncMock
            ) as mock_apply,
            patch(
                "app.services.editorial.pipeline.EditorialPipelineService"
            ) as mock_pipe_cls,
            patch.object(
                job_mod, "safe_async_session", side_effect=lambda: fake_cov_sm()
            ),
        ):
            mock_sel = MagicMock()
            mock_sel._build_global_trending_context = AsyncMock(return_value=fake_ctx)
            mock_sel_cls.return_value = mock_sel
            # llm not ready → editorial precompute body skipped (no except path).
            mock_pipe = MagicMock()
            mock_pipe.llm.is_ready = False
            mock_pipe_cls.return_value = mock_pipe

            await job.run(mock_session, datetime.date.today())

        # On the success path the trending/editorial except blocks never fire,
        # so the single rollback + apply_session_timeouts pair IS the Axe C
        # release between trending and the LLM precompute.
        mock_session.rollback.assert_awaited_once()
        mock_apply.assert_awaited_once()
        assert mock_apply.await_args.args[0] is mock_session
