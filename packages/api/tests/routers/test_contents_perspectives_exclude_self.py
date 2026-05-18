"""Regression tests for excluding the reference article from its own
perspectives list (PO refinement R3, post PR #619).

Covers three layers:
- ``_normalize_url_for_match`` — URL canonicalisation used as the equality
  key for stripping the reference from snapshot perspectives.
- ``_recompute_bias_distribution`` — keeps the bias counters in sync with
  the filtered list returned to the front.
- ``_load_cluster_articles_for_representative`` — must drop the reference
  ``content_id`` from the cluster pool so the live path can never surface
  the open article as one of its alternatives.
"""

from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.content import Content
from app.models.daily_digest import DailyDigest
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.routers.contents import (
    _load_cluster_articles_for_representative,
    _normalize_url_for_match,
    _recompute_bias_distribution,
)

# --- Helper unit tests ------------------------------------------------------


def test_normalize_url_strips_scheme_www_and_trailing_slash():
    base = _normalize_url_for_match("https://www.lemonde.fr/article/abc/")
    assert base == "lemonde.fr/article/abc"
    assert _normalize_url_for_match("http://lemonde.fr/article/abc") == base
    assert _normalize_url_for_match("https://LEMONDE.fr/article/abc") == base


def test_normalize_url_empty_inputs():
    assert _normalize_url_for_match(None) == ""
    assert _normalize_url_for_match("") == ""


def test_recompute_bias_distribution_tallies_known_stances_only():
    perspectives = [
        {"bias_stance": "left"},
        {"bias_stance": "left"},
        {"bias_stance": "center"},
        {"bias_stance": "right"},
        {"bias_stance": "unknown"},  # ignored
        {"bias_stance": None},  # ignored
        {"no_stance_field": True},  # ignored
    ]
    assert _recompute_bias_distribution(perspectives) == {
        "left": 2,
        "center-left": 0,
        "center": 1,
        "center-right": 0,
        "right": 1,
    }


# --- Integration test for the cluster loader --------------------------------


@pytest_asyncio.fixture
async def digest_with_subject(db_session):
    """Build a Source + 3 Content rows + 1 editorial DailyDigest snapshot.

    The subject references the same 3 content_ids in both ``actu_article``
    and ``extra_actu_articles`` so the cluster loader treats them as
    carousel siblings. The loader is asked for the cluster of ``ref`` — it
    must return the two siblings and *not* the reference itself.
    """
    user_id = uuid4()

    source = Source(
        id=uuid4(),
        name="Le Monde",
        url="https://lemonde.fr",
        feed_url=f"https://lemonde.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()

    ref = Content(
        id=uuid4(),
        source_id=source.id,
        title="Article courant",
        url="https://lemonde.fr/ref",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"ref-{uuid4()}",
    )
    sib_a = Content(
        id=uuid4(),
        source_id=source.id,
        title="Sibling A",
        url="https://lemonde.fr/sib-a",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"sib-a-{uuid4()}",
    )
    sib_b = Content(
        id=uuid4(),
        source_id=source.id,
        title="Sibling B",
        url="https://lemonde.fr/sib-b",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"sib-b-{uuid4()}",
    )
    db_session.add_all([ref, sib_a, sib_b])
    await db_session.commit()

    digest = DailyDigest(
        id=uuid4(),
        user_id=user_id,
        target_date=date.today(),
        format_version="editorial_v1",
        is_serene=False,
        items={
            "subjects": [
                {
                    "representative_content_id": str(ref.id),
                    "actu_article": {"content_id": str(ref.id)},
                    "extra_actu_articles": [
                        {"content_id": str(sib_a.id)},
                        {"content_id": str(sib_b.id)},
                    ],
                }
            ]
        },
    )
    db_session.add(digest)
    await db_session.commit()
    return {
        "user_id": user_id,
        "ref": ref,
        "sib_a": sib_a,
        "sib_b": sib_b,
    }


@pytest.mark.asyncio
async def test_load_cluster_articles_excludes_reference_content_id(
    db_session, digest_with_subject
):
    cluster = await _load_cluster_articles_for_representative(
        db=db_session,
        content_id=digest_with_subject["ref"].id,
        user_id=digest_with_subject["user_id"],
    )
    returned_ids = {c.id for c in cluster}
    assert digest_with_subject["ref"].id not in returned_ids
    assert returned_ids == {
        digest_with_subject["sib_a"].id,
        digest_with_subject["sib_b"].id,
    }
