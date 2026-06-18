from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.enums import BiasOrigin, BiasStance, ReliabilityScore, SourceType
from app.models.source import Source
from scripts.backfill_source_catalog_adjustments import apply_catalog_adjustments

pytestmark = pytest.mark.asyncio


def make_source(**kw) -> Source:
    defaults = {
        "id": uuid4(),
        "name": "Generic Source",
        "url": "https://generic.test",
        "feed_url": f"https://generic.test/{uuid4()}.xml",
        "type": SourceType.ARTICLE,
        "theme": "economy",
        "is_active": True,
        "is_curated": True,
        "bias_stance": BiasStance.UNKNOWN,
        "reliability_score": ReliabilityScore.UNKNOWN,
        "bias_origin": BiasOrigin.UNKNOWN,
    }
    defaults.update(kw)
    return Source(**defaults)


async def _source_row(session, sid):
    result = await session.execute(
        text("SELECT name, is_active, is_curated FROM sources WHERE id = :sid"),
        {"sid": sid},
    )
    return result.mappings().one()


async def test_dry_run_reports_without_mutating(db_session):
    dead = make_source(
        name="Les Échos",
        url="https://www.lesechos.fr/",
        feed_url="https://services.lesechos.fr/rss/les-echos-une.xml",
    )
    bfm = make_source(
        name="Home Fil actu",
        url="https://www.bfmtv.com/",
        feed_url="https://www.bfmtv.com/rss/news-24-7/",
        theme="society",
    )
    db_session.add_all([dead, bfm])
    await db_session.commit()

    result = await apply_catalog_adjustments(db_session, apply=False)

    assert result.deactivated == 1
    assert result.renamed_bfm == 1
    assert dict(await _source_row(db_session, dead.id)) == {
        "name": "Les Échos",
        "is_active": True,
        "is_curated": True,
    }
    assert (await _source_row(db_session, bfm.id))["name"] == "Home Fil actu"


async def test_apply_deactivates_dead_sources_and_renames_bfm_idempotently(db_session):
    dead_by_name = make_source(
        name="Alternatives Économiques",
        url="https://example.test/alt-eco",
        feed_url="https://example.test/alt-eco.xml",
    )
    dead_by_feed = make_source(
        name="Old Wondery Label",
        url="https://example.test/wondery",
        feed_url="https://feeds.megaphone.fm/WWS2399238883",
    )
    bfm = make_source(
        name="Home Fil actu",
        url="https://rmc.bfmtv.com/",
        feed_url="https://rmc.bfmtv.com/rss/info/flux-rss/flux-toutes-les-actualites/",
        theme="society",
    )
    db_session.add_all([dead_by_name, dead_by_feed, bfm])
    await db_session.commit()

    first = await apply_catalog_adjustments(db_session, apply=True)
    second = await apply_catalog_adjustments(db_session, apply=True)

    assert first.deactivated == 2
    assert first.renamed_bfm == 1
    assert second.deactivated == 0
    assert second.renamed_bfm == 0

    row = await _source_row(db_session, dead_by_name.id)
    assert row["is_active"] is False
    assert row["is_curated"] is False
    row = await _source_row(db_session, dead_by_feed.id)
    assert row["is_active"] is False
    assert row["is_curated"] is False
    assert (await _source_row(db_session, bfm.id))["name"] == "BFM"


async def test_bfm_rename_requires_bfmtv_domain(db_session):
    unrelated = make_source(
        name="Home Fil actu",
        url="https://example.test/",
        feed_url="https://example.test/feed.xml",
        theme="society",
    )
    db_session.add(unrelated)
    await db_session.commit()

    result = await apply_catalog_adjustments(db_session, apply=True)

    assert result.renamed_bfm == 0
    assert (await _source_row(db_session, unrelated.id))["name"] == "Home Fil actu"
