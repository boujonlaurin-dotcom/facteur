"""Tests du job nocturne de pré-génération des lettres Essentiel (9.6)."""

from __future__ import annotations

import datetime
from contextlib import asynccontextmanager
from datetime import UTC
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from app.jobs.essentiel_letter_job import run_essentiel_letter_generation
from app.schemas.content import SourceMini
from app.schemas.essentiel import EssentielArticle, EssentielResponse
from app.schemas.essentiel_letter import EssentielLetter

TARGET = datetime.date(2026, 7, 13)


def _article(rank: int) -> EssentielArticle:
    return EssentielArticle(
        content_id=uuid4(),
        title=f"Titre {rank}",
        url=f"https://example.org/{rank}",
        published_at=datetime.datetime.now(UTC),
        source=SourceMini(
            id=uuid4(), name="Le Monde", logo_url=None, type="rss", theme=None
        ),
        source_letter="L",
        section_label=f"Sujet {rank}",
        rank=rank,
        theme="politique",
    )


def _response(n: int = 5) -> EssentielResponse:
    return EssentielResponse(
        target_date=TARGET,
        generated_at=datetime.datetime.now(UTC),
        articles=[_article(i + 1) for i in range(n)],
    )


def _letter() -> EssentielLetter:
    return EssentielLetter(
        generated_at=datetime.datetime.now(UTC), model="mistral-small-latest"
    )


def _scalars_result(values):
    result = MagicMock()
    result.scalars.return_value.all.return_value = values
    return result


def _digest(stale: bool = False):
    digest = MagicMock()
    digest.is_stale_fallback = stale
    return digest


def _run_with_mocks(
    *,
    user_ids,
    existing,
    digest,
    response,
    letter,
):
    """Prépare les patches communs et renvoie le context-manager patché."""
    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(
        side_effect=[_scalars_result(user_ids), _scalars_result(existing)]
    )

    @asynccontextmanager
    async def fake_session():
        yield mock_session

    ctx = MagicMock()
    ctx.topic_weights = {"culture": 1.0}

    return (
        patch(
            "app.jobs.essentiel_letter_job.safe_async_session",
            side_effect=lambda: fake_session(),
        ),
        patch(
            "app.jobs.essentiel_letter_job.purge_old_letters",
            new=AsyncMock(return_value=0),
        ),
        patch(
            "app.jobs.essentiel_letter_job.read_digest_or_fallback",
            new=AsyncMock(return_value=digest),
        ),
        patch(
            "app.jobs.essentiel_letter_job.fetch_user_essentiel_context",
            new=AsyncMock(return_value=ctx),
        ),
        patch(
            "app.jobs.essentiel_letter_job.build_essentiel_response_with_supplements",
            new=AsyncMock(return_value=response),
        ),
        patch(
            "app.jobs.essentiel_letter_job.generate_letter",
            new=AsyncMock(return_value=letter),
        ),
        patch(
            "app.jobs.essentiel_letter_job.store_letter",
            new=AsyncMock(),
        ),
        patch(
            "app.jobs.essentiel_letter_job.EditorialLLMClient",
            return_value=MagicMock(close=AsyncMock()),
        ),
    )


async def test_job_generates_and_skips_existing():
    user_a, user_b = uuid4(), uuid4()
    patches = _run_with_mocks(
        user_ids=[user_a, user_b],
        existing=[user_b],
        digest=_digest(),
        response=_response(),
        letter=_letter(),
    )
    with (
        patches[0],
        patches[1],
        patches[2],
        patches[3],
        patches[4],
        patches[5] as mock_generate,
        patches[6] as mock_store,
        patches[7],
    ):
        stats = await run_essentiel_letter_generation(target_date=TARGET)

    assert stats == {
        "total_users": 2,
        "generated": 1,
        "skipped": 1,
        "failed": 0,
    }
    assert mock_generate.await_count == 1
    assert mock_store.await_count == 1
    assert mock_store.await_args.kwargs["user_id"] == user_a
    assert mock_store.await_args.kwargs["is_serene"] is False


async def test_job_counts_failed_when_llm_rejects():
    patches = _run_with_mocks(
        user_ids=[uuid4()],
        existing=[],
        digest=_digest(),
        response=_response(),
        letter=None,
    )
    with (
        patches[0],
        patches[1],
        patches[2],
        patches[3],
        patches[4],
        patches[5],
        patches[6] as mock_store,
        patches[7],
    ):
        stats = await run_essentiel_letter_generation(target_date=TARGET)

    assert stats["failed"] == 1
    assert stats["generated"] == 0
    assert mock_store.await_count == 0


async def test_job_skips_when_no_digest_or_stale():
    patches = _run_with_mocks(
        user_ids=[uuid4(), uuid4()],
        existing=[],
        digest=None,
        response=_response(),
        letter=_letter(),
    )
    with (
        patches[0],
        patches[1],
        patches[2],
        patches[3],
        patches[4],
        patches[5] as mock_generate,
        patches[6],
        patches[7],
    ):
        stats = await run_essentiel_letter_generation(target_date=TARGET)

    assert stats["skipped"] == 2
    assert mock_generate.await_count == 0


async def test_job_skips_thin_essentiel():
    # < 3 articles : jamais de lettre sur une carte pauvre.
    patches = _run_with_mocks(
        user_ids=[uuid4()],
        existing=[],
        digest=_digest(),
        response=_response(n=2),
        letter=_letter(),
    )
    with (
        patches[0],
        patches[1],
        patches[2],
        patches[3],
        patches[4],
        patches[5] as mock_generate,
        patches[6],
        patches[7],
    ):
        stats = await run_essentiel_letter_generation(target_date=TARGET)

    assert stats["skipped"] == 1
    assert mock_generate.await_count == 0


async def test_job_runs_purge_with_retention():
    patches = _run_with_mocks(
        user_ids=[],
        existing=[],
        digest=_digest(),
        response=_response(),
        letter=_letter(),
    )
    with (
        patches[0],
        patches[1] as mock_purge,
        patches[2],
        patches[3],
        patches[4],
        patches[5],
        patches[6],
        patches[7],
    ):
        await run_essentiel_letter_generation(target_date=TARGET)

    assert mock_purge.await_count == 1
    assert mock_purge.await_args.kwargs["older_than_days"] == 30
