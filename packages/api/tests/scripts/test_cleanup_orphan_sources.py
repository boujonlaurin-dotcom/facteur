"""Tests pour scripts/cleanup_orphan_sources.py (Composant 2).

Fixtures reproduisant chaque bucket. Vérifie : catégorisation dry-run sans
mutation, merge correct (éval transférée, follows re-pointés + dédupés,
muted nettoyé, veille géré sans crash), suppressions, garde-fou abort,
et re-run idempotent.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.content import Content
from app.models.enums import (
    BiasOrigin,
    BiasStance,
    ContentType,
    ReliabilityScore,
    SourceType,
)
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_personalization import UserPersonalization
from app.models.veille import VeilleConfig, VeilleSource
from scripts.cleanup_orphan_sources import (
    CleanupAbort,
    _delete_predicate,
    apply_plan,
    build_backup,
    build_plan,
    gather_stats,
)

pytestmark = pytest.mark.asyncio


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def make_source(**kw) -> Source:
    defaults = {
        "id": uuid4(),
        "name": "Generic Source",
        "url": "https://generic.test",
        "feed_url": f"https://generic.test/{uuid4()}.xml",
        "type": SourceType.ARTICLE,
        "theme": "society",
        "is_active": True,
        "is_curated": False,
        "bias_stance": BiasStance.UNKNOWN,
        "reliability_score": ReliabilityScore.UNKNOWN,
        "bias_origin": BiasOrigin.UNKNOWN,
    }
    defaults.update(kw)
    return Source(**defaults)


def make_content(source_id, guid: str) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="t",
        url=f"https://generic.test/{guid}",
        guid=guid,
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
    )


async def make_user(session) -> object:
    uid = uuid4()
    session.add(UserProfile(user_id=uid))
    return uid


async def _count_sources(session, sid) -> int:
    r = await session.execute(
        text("SELECT count(*) FROM sources WHERE id = :sid"), {"sid": sid}
    )
    return r.scalar_one()


async def _count_contents(session, sid) -> int:
    r = await session.execute(
        text("SELECT count(*) FROM contents WHERE source_id = :sid"), {"sid": sid}
    )
    return r.scalar_one()


async def _follow(session, sid) -> int:
    r = await session.execute(
        text("SELECT count(*) FROM user_sources WHERE source_id = :sid"), {"sid": sid}
    )
    return r.scalar_one()


# Feed URLs réels des paires hardcodées (cf. cleanup_orphan_sources.DUPLICATE_PAIRS)
LP_WINNER = "https://www.lepoint.fr/rss"
LP_LOSER = "https://www.lepoint.fr/rss.xml"
S4A_WINNER = (
    "https://www.youtube.com/feeds/videos.xml?channel_id=UC0NCbj8CxzeCGIF6sODJ-7A"
)
S4A_LOSER = (
    "https://www.youtube.com/feeds/videos.xml?channel_id=UCveuAeZglYzc8ah1bZi8kBA"
)
# Paires à winner WEB EXPLICITE (surface A) — le web gagne même avec moins de contenu.
PB_WEB = "https://www.pascalboniface.com/feed/"
PB_YT = "https://www.youtube.com/feeds/videos.xml?channel_id=UC4VOE8jQPWUPp4PpNK8zhIg"
EL_WEB = "https://elucid.media/feed"
EL_YT = "https://www.youtube.com/feeds/videos.xml?channel_id=UCkgO4A3Fzm5D9Xu1Y_4vCKQ"


# --------------------------------------------------------------------------- #
# Catégorisation (dry-run, aucune mutation)
# --------------------------------------------------------------------------- #


async def test_categorize_buckets_disjoint(db_session):
    junk = make_source(
        name="Test Source",
        url="https://example.com",
        feed_url="https://example.com/junk.xml",
        is_active=False,
    )
    dead = make_source(name="Dead Blog", is_active=False)
    broken = make_source(
        name="Libération",
        feed_url="https://www.liberation.fr/rss/",
        is_active=True,
        is_curated=True,
        bias_origin=BiasOrigin.CURATED,
    )
    keep = make_source(name="Le Monde")
    lp_w = make_source(name="Le Point", feed_url=LP_WINNER)
    lp_l = make_source(
        name="Le Point",
        feed_url=LP_LOSER,
        is_curated=True,
        bias_stance=BiasStance.CENTER_RIGHT,
        bias_origin=BiasOrigin.CURATED,
    )
    for s in (junk, dead, broken, keep, lp_w, lp_l):
        db_session.add(s)
    db_session.add(make_content(keep.id, "k1"))
    db_session.add(make_content(lp_w.id, "lp1"))  # winner a + de content
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)

    assert [s.name for s in plan.test_junk] == ["Test Source"]
    assert [s.name for s in plan.genuinely_dead] == ["Dead Blog"]
    assert [s.feed_url for s in plan.broken_feed_legit] == [
        "https://www.liberation.fr/rss/"
    ]
    assert len(plan.merges) == 1
    assert plan.merges[0].winner.feed_url == LP_WINNER
    assert plan.merges[0].loser.feed_url == LP_LOSER
    # keep = Le Monde (le winner Le Point est "consumed", pas keep)
    assert plan.keep_count == 1

    # Dry-run : rien n'a été supprimé
    assert await _count_sources(db_session, junk.id) == 1
    assert await _count_sources(db_session, lp_l.id) == 1


async def test_abort_when_active_curated_in_delete_bucket(db_session):
    # Un "Test Source" actif + curated (anormal) -> TEST_JUNK -> doit ABORT.
    db_session.add(
        make_source(
            name="Test Source",
            url="https://example.com",
            feed_url="https://example.com/x.xml",
            is_active=True,
            is_curated=True,
        )
    )
    await db_session.commit()
    rows = await gather_stats(db_session)
    with pytest.raises(CleanupAbort):
        build_plan(rows)


# --------------------------------------------------------------------------- #
# Merge
# --------------------------------------------------------------------------- #


async def test_merge_lepoint_transfers_eval_and_repoints_follows(db_session):
    winner = make_source(name="Le Point", feed_url=LP_WINNER)
    loser = make_source(
        name="Le Point",
        feed_url=LP_LOSER,
        is_curated=True,
        bias_stance=BiasStance.CENTER_RIGHT,
        reliability_score=ReliabilityScore.HIGH,
        bias_origin=BiasOrigin.CURATED,
        description="Quotidien hebdomadaire.",
    )
    db_session.add_all([winner, loser])
    db_session.add(make_content(winner.id, "w1"))
    await db_session.commit()

    u_loser_only = await make_user(db_session)  # suit seulement le perdant
    u_both = await make_user(db_session)  # suit les deux -> collision
    u_muted = await make_user(db_session)  # a muté le perdant
    await db_session.commit()

    db_session.add(UserSource(user_id=u_loser_only, source_id=loser.id))
    db_session.add(UserSource(user_id=u_both, source_id=loser.id))
    db_session.add(UserSource(user_id=u_both, source_id=winner.id))
    db_session.add(UserPersonalization(user_id=u_muted, muted_sources=[loser.id]))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    # build_backup exerce la requête array-overlap muted_sources && :ids
    backup = await build_backup(db_session, plan)
    assert backup["merges"][0]["media"] == "Le Point"
    assert any(m["muted_sources"] for m in backup["muted_sources_touched"])

    await apply_plan(db_session, plan)

    # Perdant supprimé, winner conservé
    assert await _count_sources(db_session, loser.id) == 0
    assert await _count_sources(db_session, winner.id) == 1

    # Éval transférée au winner (winner était unknown)
    r = await db_session.execute(
        text(
            "SELECT bias_stance, reliability_score, bias_origin, is_curated, description "
            "FROM sources WHERE id = :id"
        ),
        {"id": winner.id},
    )
    w = r.mappings().one()
    assert w["bias_stance"] == "center-right"
    assert w["reliability_score"] == "high"
    assert w["bias_origin"] == "curated"
    assert w["is_curated"] is True
    assert w["description"] == "Quotidien hebdomadaire."

    # Follows re-pointés + dédupés : u_loser_only + u_both -> 1 ligne chacun sur winner
    assert await _follow(db_session, loser.id) == 0
    assert await _follow(db_session, winner.id) == 2
    dup = await db_session.execute(
        text("SELECT count(*) FROM user_sources WHERE user_id = :u AND source_id = :s"),
        {"u": u_both, "s": winner.id},
    )
    assert dup.scalar_one() == 1  # pas de doublon malgré la collision

    # muted_sources nettoyé (R6 : array sans FK)
    m = await db_session.execute(
        text("SELECT muted_sources FROM user_personalization WHERE user_id = :u"),
        {"u": u_muted},
    )
    assert loser.id not in m.scalar_one()


async def test_merge_dedups_colliding_guids(db_session):
    # winner = max content (4 > 3) -> S4A_WINNER reste le winner.
    winner = make_source(name="Science4All", feed_url=S4A_WINNER)
    loser = make_source(name="Science4All", feed_url=S4A_LOSER)
    db_session.add_all([winner, loser])
    for g in ("g1", "g2", "g3", "g4"):
        db_session.add(make_content(winner.id, g))
    # perdant : 2 guids distincts + 1 collision (g1)
    for g in ("g5", "g6", "g1"):
        db_session.add(make_content(loser.id, g))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    assert plan.merges[0].winner.feed_url == S4A_WINNER
    await apply_plan(db_session, plan)

    # winner = g1,g2,g3,g4 + g5,g6 re-pointés (g1 collision pré-supprimée) = 6
    assert await _count_contents(db_session, winner.id) == 6
    assert await _count_sources(db_session, loser.id) == 0


async def test_merge_keeps_existing_winner_eval(db_session):
    # Bidouille : winner déjà curated specialized -> ne PAS écraser avec l'éval perdant.
    bid_w = (
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCSULDz1yaHLVQWHpm4g_GHA"
    )
    bid_l = "https://www.youtube.com/feeds/videos.xml?user=monsieurbidouille"
    winner = make_source(
        name="Monsieur Bidouille",
        feed_url=bid_w,
        type=SourceType.YOUTUBE,
        is_curated=True,
        bias_stance=BiasStance.SPECIALIZED,
        bias_origin=BiasOrigin.CURATED,
    )
    loser = make_source(
        name="Monsieur Bidouille",
        feed_url=bid_l,
        type=SourceType.YOUTUBE,
        is_active=False,
        is_curated=True,
        bias_stance=BiasStance.LEFT,
        bias_origin=BiasOrigin.CURATED,
    )
    db_session.add_all([winner, loser])
    db_session.add(make_content(winner.id, "b1"))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    await apply_plan(db_session, plan)

    r = await db_session.execute(
        text("SELECT bias_stance FROM sources WHERE id = :id"), {"id": winner.id}
    )
    assert r.scalar_one() == "specialized"  # éval winner intacte (pas "left")


async def test_pascal_boniface_web_wins_despite_less_content(db_session):
    # Surface A : winner WEB explicite, même si le YT a plus de contenu.
    web = make_source(name="Pascal Boniface", feed_url=PB_WEB, type=SourceType.ARTICLE)
    yt = make_source(name="Pascal Boniface", feed_url=PB_YT, type=SourceType.YOUTUBE)
    db_session.add_all([web, yt])
    db_session.add(make_content(web.id, "pb_web1"))  # web = 1 content
    db_session.add(make_content(yt.id, "pb_yt1"))  # yt = 2 contents (plus que web)
    db_session.add(make_content(yt.id, "pb_yt2"))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    assert len(plan.merges) == 1
    assert plan.merges[0].winner.feed_url == PB_WEB  # web gagne malgré moins de contenu
    assert plan.merges[0].loser.feed_url == PB_YT


async def test_elucid_web_wins(db_session):
    # Surface A : Élucid garde le feed web (ici aussi le plus fourni, mais explicite).
    web = make_source(name="Élucid", feed_url=EL_WEB, type=SourceType.ARTICLE)
    yt = make_source(name="Élucid", feed_url=EL_YT, type=SourceType.YOUTUBE)
    db_session.add_all([web, yt])
    db_session.add(make_content(web.id, "el1"))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    assert plan.merges[0].winner.feed_url == EL_WEB


async def test_broken_feed_never_deleted_even_if_deactivated(db_session):
    # Un flux cassé désactivé (is_active=false, surface B) reste protégé par
    # l'allowlist : broken_feed_legit, jamais dans deleted_ids.
    echos = make_source(
        name="Les Échos",
        feed_url="https://services.lesechos.fr/rss/les-echos-une.xml",
        is_active=False,  # désactivé par repair_broken_feeds.py
        is_curated=True,
        bias_origin=BiasOrigin.CURATED,
    )
    db_session.add(echos)
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    assert echos.id in [s.id for s in plan.broken_feed_legit]
    assert echos.id not in plan.deleted_ids
    assert echos.id not in [s.id for s in plan.genuinely_dead]


# --------------------------------------------------------------------------- #
# Suppressions par prédicat
# --------------------------------------------------------------------------- #


async def test_delete_junk_and_dead(db_session):
    junk = make_source(
        name="Test Source",
        url="https://example.com",
        feed_url="https://example.com/j.xml",
        is_active=False,
    )
    dead = make_source(name="Dead", is_active=False)
    keep = make_source(name="Alive")
    db_session.add_all([junk, dead, keep])
    db_session.add(make_content(keep.id, "a1"))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    counts = await apply_plan(db_session, plan)

    assert counts["deleted"] == 2
    assert await _count_sources(db_session, junk.id) == 0
    assert await _count_sources(db_session, dead.id) == 0
    assert await _count_sources(db_session, keep.id) == 1


async def test_delete_predicate_cascades_contents_and_follows(db_session):
    # Suppression d'une source -> contents/user_sources cascadent (FK CASCADE).
    from scripts.cleanup_orphan_sources import SourceRow

    src = make_source(name="Dead With Refs", is_active=False)
    db_session.add(src)
    db_session.add(make_content(src.id, "d1"))
    uid = await make_user(db_session)
    await db_session.commit()
    db_session.add(UserSource(user_id=uid, source_id=src.id))
    await db_session.commit()

    row = SourceRow(
        id=src.id,
        name=src.name,
        url=src.url,
        feed_url=src.feed_url,
        type="article",
        is_active=False,
        is_curated=False,
        bias_stance="unknown",
        reliability_score="unknown",
        bias_origin="unknown",
        score_independence=None,
        score_rigor=None,
        score_ux=None,
        description=None,
        recommended_by=None,
        recommendation_reason=None,
        n_content=1,
        n_follow=1,
        n_fav=0,
        n_veille=0,
    )
    deleted = await _delete_predicate(db_session, row)
    assert deleted is True
    assert await _count_sources(db_session, src.id) == 0
    assert await _count_contents(db_session, src.id) == 0
    assert await _follow(db_session, src.id) == 0


# --------------------------------------------------------------------------- #
# Garde veille (RESTRICT)
# --------------------------------------------------------------------------- #


async def test_veille_referenced_source_is_kept(db_session):
    # inactive + 0 content/follow/fav MAIS référencée par veille -> n_refs>0 -> KEEP
    src = make_source(name="In Veille", is_active=False)
    db_session.add(src)
    uid = await make_user(db_session)
    await db_session.commit()
    cfg = VeilleConfig(id=uuid4(), user_id=uid, theme_id="tech", theme_label="Tech")
    db_session.add(cfg)
    await db_session.commit()
    db_session.add(
        VeilleSource(
            id=uuid4(), veille_config_id=cfg.id, source_id=src.id, kind="primary"
        )
    )
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    assert src.id not in [s.id for s in plan.genuinely_dead]


async def test_delete_predicate_skips_on_veille(db_session):
    src = make_source(name="Veille Dead", is_active=False)
    db_session.add(src)
    uid = await make_user(db_session)
    await db_session.commit()
    cfg = VeilleConfig(id=uuid4(), user_id=uid, theme_id="tech", theme_label="Tech")
    db_session.add(cfg)
    await db_session.commit()
    db_session.add(
        VeilleSource(
            id=uuid4(), veille_config_id=cfg.id, source_id=src.id, kind="primary"
        )
    )
    await db_session.commit()

    from scripts.cleanup_orphan_sources import SourceRow

    row = SourceRow(
        id=src.id,
        name=src.name,
        url=src.url,
        feed_url=src.feed_url,
        type="article",
        is_active=False,
        is_curated=False,
        bias_stance="unknown",
        reliability_score="unknown",
        bias_origin="unknown",
        score_independence=None,
        score_rigor=None,
        score_ux=None,
        description=None,
        recommended_by=None,
        recommendation_reason=None,
        n_content=0,
        n_follow=0,
        n_fav=0,
        n_veille=1,
    )
    deleted = await _delete_predicate(db_session, row)
    assert deleted is False
    assert await _count_sources(db_session, src.id) == 1  # toujours là (RESTRICT)


# --------------------------------------------------------------------------- #
# Idempotence
# --------------------------------------------------------------------------- #


async def test_rerun_is_noop(db_session):
    junk = make_source(
        name="Test Source",
        url="https://example.com",
        feed_url="https://example.com/i.xml",
        is_active=False,
    )
    winner = make_source(name="Le Point", feed_url=LP_WINNER)
    loser = make_source(
        name="Le Point",
        feed_url=LP_LOSER,
        is_curated=True,
        bias_origin=BiasOrigin.CURATED,
    )
    db_session.add_all([junk, winner, loser])
    db_session.add(make_content(winner.id, "w1"))
    await db_session.commit()

    rows = await gather_stats(db_session)
    plan = build_plan(rows)
    await apply_plan(db_session, plan)

    # 2e passe : plus rien à faire
    rows2 = await gather_stats(db_session)
    plan2 = build_plan(rows2)
    assert plan2.test_junk == []
    assert plan2.merges == []  # une seule source Le Point restante -> pas de paire
    counts2 = await apply_plan(db_session, plan2)
    assert counts2 == {"merged": 0, "deleted": 0, "skipped": 0}
