"""Garantit l'invariant "tout content_id appartenant à un digest editorial_v1
récent → fast path stored snapshot, jamais live recompute".

Bug fixé : `_load_stored_perspectives_for_representative` ne matchait pas
`deep_article.content_id`. Un tap sur la card "pas de recul" tombait alors en
live path → count diverge du badge preview.
"""

from __future__ import annotations

from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest

from app.models.daily_digest import DailyDigest
from app.routers.contents import _load_stored_perspectives_for_representative


def _make_digest(subjects: list[dict]) -> DailyDigest:
    digest = DailyDigest()
    digest.id = uuid4()
    digest.user_id = uuid4()
    digest.target_date = date(2026, 5, 20)
    digest.format_version = "editorial_v1"
    digest.is_serene = False
    digest.items = {"subjects": subjects}
    return digest


def _make_subject(
    representative_id: UUID,
    actu_id: UUID,
    extra_ids: list[UUID],
    deep_id: UUID | None,
    perspective_count: int = 5,
    *,
    omit_snapshot: bool = False,
) -> dict:
    """Build a subject dict matching the pipeline persistence shape."""
    snapshot = [
        {
            "title": f"Perspective {i}",
            "url": f"https://example.com/p{i}",
            "source_name": f"Source {i}",
            "source_domain": f"src{i}.com",
            "bias_stance": "center",
            "published_at": None,
            "description": None,
        }
        for i in range(perspective_count)
    ]
    return {
        "topic_id": "topic-1",
        "representative_content_id": str(representative_id),
        "actu_article": {"content_id": str(actu_id)},
        "extra_actu_articles": [{"content_id": str(eid)} for eid in extra_ids],
        "deep_article": {"content_id": str(deep_id)} if deep_id else None,
        "perspective_articles": None if omit_snapshot else snapshot,
        "bias_distribution": {
            "left": 0,
            "center-left": 0,
            "center": perspective_count,
            "center-right": 0,
            "right": 0,
        },
        "perspective_count": perspective_count,
    }


def _mock_db_returning(digest: DailyDigest) -> AsyncMock:
    db = AsyncMock()
    result = MagicMock()
    scalars = MagicMock()
    scalars.all.return_value = [digest] if digest else []
    result.scalars.return_value = scalars
    db.execute = AsyncMock(return_value=result)
    return db


@pytest.mark.asyncio
async def test_fast_path_matches_representative():
    representative = uuid4()
    actu = uuid4()
    extra = uuid4()
    deep = uuid4()
    subject = _make_subject(representative, actu, [extra], deep, perspective_count=5)
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=representative, user_id=digest.user_id
    )

    assert result is not None
    perspectives, bias = result
    assert len(perspectives) == 5
    assert bias["center"] == 5


@pytest.mark.asyncio
async def test_fast_path_matches_actu():
    representative = uuid4()
    actu = uuid4()
    deep = uuid4()
    subject = _make_subject(representative, actu, [], deep, perspective_count=5)
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=actu, user_id=digest.user_id
    )
    assert result is not None
    assert len(result[0]) == 5


@pytest.mark.asyncio
async def test_fast_path_matches_extra_actu():
    representative = uuid4()
    actu = uuid4()
    extra = uuid4()
    deep = uuid4()
    subject = _make_subject(representative, actu, [extra], deep, perspective_count=4)
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=extra, user_id=digest.user_id
    )
    assert result is not None
    assert len(result[0]) == 4


@pytest.mark.asyncio
async def test_fast_path_matches_deep_article():
    """Régression principale : tap sur card 'pas de recul' (deep_article)
    doit hit fast path et retourner le même snapshot que les autres IDs.
    """
    representative = uuid4()
    actu = uuid4()
    deep = uuid4()
    subject = _make_subject(representative, actu, [], deep, perspective_count=5)
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=deep, user_id=digest.user_id
    )
    assert result is not None
    perspectives, bias = result
    assert len(perspectives) == 5
    assert bias["center"] == 5


@pytest.mark.asyncio
async def test_fast_path_all_five_ids_return_same_snapshot():
    """Tous les content_ids rattachés au même sujet doivent retourner
    exactement le même snapshot."""
    representative = uuid4()
    actu = uuid4()
    extras = [uuid4(), uuid4()]
    deep = uuid4()
    subject = _make_subject(
        representative, actu, extras, deep, perspective_count=5
    )
    digest = _make_digest([subject])

    all_ids = [representative, actu, *extras, deep]
    snapshots = []
    for cid in all_ids:
        db = _mock_db_returning(digest)
        result = await _load_stored_perspectives_for_representative(
            db=db, content_id=cid, user_id=digest.user_id
        )
        assert result is not None, f"content_id {cid} should hit fast path"
        snapshots.append(result[0])

    # Toutes les listes doivent être identiques (même nombre, mêmes urls).
    urls = [tuple(p["url"] for p in s) for s in snapshots]
    assert len(set(urls)) == 1, "All matched IDs must return the same snapshot"


@pytest.mark.asyncio
async def test_fast_path_returns_empty_when_snapshot_missing():
    """Invariant A.2 : si le sujet est trouvé mais perspective_articles is None
    (legacy / bug pipeline), retourner ([], bias) plutôt que None, pour
    empêcher le fallback live qui divergerait du badge."""
    representative = uuid4()
    actu = uuid4()
    deep = uuid4()
    subject = _make_subject(
        representative, actu, [], deep, perspective_count=5, omit_snapshot=True
    )
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=representative, user_id=digest.user_id
    )

    assert result is not None, "must NOT fall back to live path"
    perspectives, _ = result
    assert perspectives == []


@pytest.mark.asyncio
async def test_fast_path_returns_none_for_unrelated_content():
    """content_id hors digest récent → None → live path."""
    representative = uuid4()
    actu = uuid4()
    deep = uuid4()
    subject = _make_subject(representative, actu, [], deep)
    digest = _make_digest([subject])
    db = _mock_db_returning(digest)

    unrelated = uuid4()
    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=unrelated, user_id=digest.user_id
    )
    assert result is None


@pytest.mark.asyncio
async def test_fast_path_returns_none_when_no_digest():
    db = _mock_db_returning(None)
    result = await _load_stored_perspectives_for_representative(
        db=db, content_id=uuid4(), user_id=uuid4()
    )
    assert result is None
