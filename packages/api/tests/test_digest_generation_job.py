"""Tests for digest_generation_job — editorial pipeline result handling."""

import datetime
from unittest.mock import AsyncMock, Mock, patch
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
    session.execute = AsyncMock()
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

        # Mock: no existing digest
        mock_session.scalar = AsyncMock(return_value=None)

        # Mock UserPreference query
        mock_pref_result = Mock()
        mock_pref_result.scalar_one_or_none = Mock(return_value="pour_vous")
        mock_session.execute = AsyncMock(return_value=mock_pref_result)

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

        mock_svc._create_digest_record_editorial.assert_awaited_once()
        assert job.stats["success"] == 1
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

        mock_pref_result = Mock()
        mock_pref_result.scalar_one_or_none = Mock(return_value="pour_vous")
        mock_session.execute = AsyncMock(return_value=mock_pref_result)

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

        assert job.stats["failed"] == 1
        assert job.stats["success"] == 0
