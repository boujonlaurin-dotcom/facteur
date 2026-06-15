"""Tests for digest_generation_job — editorial pipeline result handling."""

import datetime
from unittest.mock import AsyncMock, MagicMock, Mock, patch
from uuid import uuid4

import pytest

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
        from app.models.source import Source

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
