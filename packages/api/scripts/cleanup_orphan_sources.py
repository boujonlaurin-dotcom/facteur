#!/usr/bin/env python3
"""Nettoyage des sources : junk, doublons, sources mortes (Composant 2).

Buckets disjoints, **dry-run par défaut**, `--apply` gardé (prod-guard +
backup JSON dans `.context/`). Remplace l'anti-pattern SQL Editor
`fix_stale_rss_sources.sql` (cf. règle CLAUDE.md anti-drift Alembic : aucun
SQL manuel — tout DDL/DML de prod passe par un script Python gardé).

Buckets :
  - TEST_JUNK          : `name='Test Source'` + url example.com + 0 ref  -> hard delete
  - TRUE_DUPLICATE     : paires hardcodées (résolues par feed_url)        -> merge perdant->winner puis delete
  - GENUINELY_DEAD     : inactive + 0 content/follow/fav/veille           -> hard delete
  - BROKEN_FEED_LEGIT  : grand média actif curated 0 content (allowlist)  -> RAPPORT seulement (jamais touché)
  - KEEP               : tout le reste                                     -> no-op

Garde-fou critique : le script **abort** si une source `is_active ∧ is_curated`
tombe dans un bucket de suppression par prédicat (TEST_JUNK / GENUINELY_DEAD).
Le merge TRUE_DUPLICATE (qui peut supprimer une source curated, ex. Le Point
rss.xml) est exempté : suppression intentionnelle qui transfère l'éval au winner.

Usage :
    cd packages/api
    python3 scripts/cleanup_orphan_sources.py                 # dry-run (défaut)
    python3 scripts/cleanup_orphan_sources.py --apply         # DB de test
    python3 scripts/cleanup_orphan_sources.py --apply --allow-prod   # prod (gated PO)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session_maker, engine

# --------------------------------------------------------------------------- #
# Spécifications hardcodées (auditées en prod le 2026-06-13, cf.
# .context/source-cleanup-diagnostic-2026-06-13.md). Les feed_url ne servent qu'à
# *identifier* la paire — robuste si des UUID changent.
#
# Winner par paire (décision PO verrouillée, surface A) :
#   - `winner` explicite -> **web préféré** (Le Point=/rss, Élucid + Pascal
#     Boniface = feed web articles, même si < contenu YT). Robuste : ne dépend
#     plus du sort-key contenu.
#   - sans `winner` -> sort-key dynamique (max content) : paires YouTube-only
#     (Monsieur Bidouille, Science4All) -> on garde le feed au max de contenu.
# --------------------------------------------------------------------------- #

TEST_SOURCE_NAME = "Test Source"

DUPLICATE_PAIRS: list[dict] = [
    {
        "media": "Le Point",
        "winner": "https://www.lepoint.fr/rss",  # /rss (200c) reçoit l'éval curated du /rss.xml
        "feed_urls": [
            "https://www.lepoint.fr/rss",
            "https://www.lepoint.fr/rss.xml",
        ],
    },
    {
        "media": "Monsieur Bidouille",  # YouTube-only -> max content
        "feed_urls": [
            "https://www.youtube.com/feeds/videos.xml?channel_id=UCSULDz1yaHLVQWHpm4g_GHA",
            "https://www.youtube.com/feeds/videos.xml?user=monsieurbidouille",
        ],
    },
    {
        "media": "Science4All",  # YouTube-only -> max content
        "feed_urls": [
            "https://www.youtube.com/feeds/videos.xml?channel_id=UC0NCbj8CxzeCGIF6sODJ-7A",
            "https://www.youtube.com/feeds/videos.xml?channel_id=UCveuAeZglYzc8ah1bZi8kBA",
        ],
    },
    {
        "media": "Élucid",
        "winner": "https://elucid.media/feed",  # web articles préféré au YT
        "feed_urls": [
            "https://elucid.media/feed",
            "https://www.youtube.com/feeds/videos.xml?channel_id=UCkgO4A3Fzm5D9Xu1Y_4vCKQ",
        ],
    },
    {
        "media": "Pascal Boniface",
        "winner": "https://www.pascalboniface.com/feed/",  # web préféré au YT (PO, malgré < contenu)
        "feed_urls": [
            "https://www.youtube.com/feeds/videos.xml?channel_id=UC4VOE8jQPWUPp4PpNK8zhIg",
            "https://www.pascalboniface.com/feed/",
        ],
    },
]

# Grands médias à flux cassé — JAMAIS supprimés (réparés par repair_broken_feeds.py).
# Allowlist par feed_url exact (audit prod 2026-06-13).
BROKEN_FEED_ALLOWLIST: set[str] = {
    "https://www.alternatives-economiques.fr/flux-rss",
    "https://www.brut.media/fr/flux-rss",
    "https://feeds.megaphone.fm/WWS2399238883",
    "https://services.lesechos.fr/rss/les-echos-une.xml",
    "https://www.liberation.fr/rss/",
    "https://www.radiofrance.fr/franceculture/podcasts/mecaniques-du-complot.rss",
    "https://feeds.360.audion.fm/EZqjvOzZXgWIKWg0EETBQ",
}


class CleanupAbort(RuntimeError):
    """Garde-fou déclenché : une source protégée tombe dans un bucket delete."""


@dataclass
class SourceRow:
    id: UUID
    name: str
    url: str
    feed_url: str
    type: str
    is_active: bool
    is_curated: bool
    bias_stance: str
    reliability_score: str
    bias_origin: str
    score_independence: float | None
    score_rigor: float | None
    score_ux: float | None
    description: str | None
    recommended_by: str | None
    recommendation_reason: str | None
    n_content: int
    n_follow: int
    n_fav: int
    n_veille: int

    @property
    def n_refs(self) -> int:
        return self.n_content + self.n_follow + self.n_fav + self.n_veille

    def to_dict(self) -> dict:
        d = {k: getattr(self, k) for k in self.__dataclass_fields__}
        d["id"] = str(self.id)
        return d


@dataclass
class Merge:
    media: str
    winner: SourceRow
    loser: SourceRow

    @property
    def winner_updates(self) -> dict:
        """Champs à transférer du perdant vers le winner (s'il en manque)."""
        w, loser = self.winner, self.loser
        updates: dict = {}
        if loser.is_curated and not w.is_curated:
            updates["is_curated"] = True
        # Éval éditoriale : on transfère uniquement si le winner n'a PAS déjà
        # une éval curated (jamais écraser). Cas Le Point : winner rss=unknown,
        # perdant rss.xml=curated center-right -> transfert.
        if w.bias_origin != "curated" and loser.bias_origin == "curated":
            updates["bias_stance"] = loser.bias_stance
            updates["reliability_score"] = loser.reliability_score
            updates["bias_origin"] = loser.bias_origin
            for col in ("score_independence", "score_rigor", "score_ux"):
                if getattr(w, col) is None and getattr(loser, col) is not None:
                    updates[col] = getattr(loser, col)
        if w.description is None and loser.description:
            updates["description"] = loser.description
        if w.recommended_by is None and loser.recommended_by:
            updates["recommended_by"] = loser.recommended_by
            updates["recommendation_reason"] = loser.recommendation_reason
        return updates


@dataclass
class CleanupPlan:
    test_junk: list[SourceRow] = field(default_factory=list)
    genuinely_dead: list[SourceRow] = field(default_factory=list)
    broken_feed_legit: list[SourceRow] = field(default_factory=list)
    merges: list[Merge] = field(default_factory=list)
    keep_count: int = 0

    @property
    def predicate_delete(self) -> list[SourceRow]:
        """Sources supprimées par prédicat (hors merge)."""
        return [*self.test_junk, *self.genuinely_dead]

    @property
    def deleted_ids(self) -> list[UUID]:
        return [s.id for s in self.predicate_delete] + [m.loser.id for m in self.merges]


# --------------------------------------------------------------------------- #
# Lecture (read-only)
# --------------------------------------------------------------------------- #

_STATS_SQL = text(
    """
    SELECT s.id, s.name, s.url, s.feed_url, s.type, s.is_active, s.is_curated,
           s.bias_stance, s.reliability_score, s.bias_origin,
           s.score_independence, s.score_rigor, s.score_ux, s.description,
           s.recommended_by, s.recommendation_reason,
           (SELECT count(*) FROM contents c WHERE c.source_id = s.id) AS n_content,
           (SELECT count(*) FROM user_sources us WHERE us.source_id = s.id) AS n_follow,
           (SELECT count(*) FROM user_favorite_sources uf WHERE uf.source_id = s.id) AS n_fav,
           (SELECT count(*) FROM veille_sources v WHERE v.source_id = s.id) AS n_veille
    FROM sources s
    """
)


async def gather_stats(session: AsyncSession) -> dict[UUID, SourceRow]:
    result = await session.execute(_STATS_SQL)
    rows: dict[UUID, SourceRow] = {}
    for m in result.mappings():
        rows[m["id"]] = SourceRow(**m)
    return rows


# --------------------------------------------------------------------------- #
# Catégorisation (pure)
# --------------------------------------------------------------------------- #


def _winner_sort_key(s: SourceRow) -> tuple:
    # Fallback (sans `winner` explicite) : max content, puis actif, curated, follows.
    return (s.n_content, int(s.is_active), int(s.is_curated), s.n_follow)


def _resolve_winner(
    spec: dict, present: list[SourceRow]
) -> tuple[SourceRow, list[SourceRow]]:
    """Winner explicite (`spec['winner']` feed_url, web préféré) sinon max content."""
    explicit = spec.get("winner")
    if explicit:
        winner = next((s for s in present if s.feed_url == explicit), None)
        if winner is not None:
            losers = [s for s in present if s.id != winner.id]
            return winner, losers
    ranked = sorted(present, key=_winner_sort_key, reverse=True)
    return ranked[0], ranked[1:]


def _is_test_junk(s: SourceRow) -> bool:
    return (
        s.name == TEST_SOURCE_NAME
        and ("example.com" in (s.url or "") or "example.com" in (s.feed_url or ""))
        and s.n_refs == 0
    )


def _is_genuinely_dead(s: SourceRow) -> bool:
    return (
        not s.is_active
        and s.n_refs == 0
        and s.name != TEST_SOURCE_NAME
        and s.feed_url not in BROKEN_FEED_ALLOWLIST
    )


def build_plan(rows: dict[UUID, SourceRow]) -> CleanupPlan:
    """Catégorise les sources en buckets disjoints. Pur (pas d'IO)."""
    by_feed: dict[str, SourceRow] = {s.feed_url: s for s in rows.values()}
    plan = CleanupPlan()
    consumed: set[UUID] = set()

    # 1) Doublons (priorité haute : déterminent winner/loser avant les prédicats)
    for spec in DUPLICATE_PAIRS:
        present = [by_feed[f] for f in spec["feed_urls"] if f in by_feed]
        if len(present) < 2:
            continue  # déjà fusionné / partiellement présent -> idempotent no-op
        winner, losers = _resolve_winner(spec, present)
        for loser in losers:
            plan.merges.append(Merge(media=spec["media"], winner=winner, loser=loser))
            consumed.add(loser.id)
        consumed.add(winner.id)

    # 2) Prédicats sur le reste
    for s in rows.values():
        if s.id in consumed:
            continue
        if s.feed_url in BROKEN_FEED_ALLOWLIST:
            plan.broken_feed_legit.append(s)
        elif _is_test_junk(s):
            plan.test_junk.append(s)
        elif _is_genuinely_dead(s):
            plan.genuinely_dead.append(s)
        else:
            plan.keep_count += 1

    # 3) Garde-fou abort : aucune source active+curated dans un bucket delete-prédicat
    protected = [s for s in plan.predicate_delete if s.is_active and s.is_curated]
    if protected:
        names = ", ".join(f"{s.name} ({s.feed_url})" for s in protected)
        raise CleanupAbort(
            "ABORT : source(s) active+curated dans un bucket de suppression par "
            f"prédicat — refus de supprimer : {names}"
        )
    return plan


# --------------------------------------------------------------------------- #
# Backup
# --------------------------------------------------------------------------- #


async def _fetch_muted_map(session: AsyncSession, ids: list[UUID]) -> list[dict]:
    if not ids:
        return []
    result = await session.execute(
        text(
            "SELECT user_id, muted_sources FROM user_personalization "
            "WHERE muted_sources && :ids"
        ),
        {"ids": ids},
    )
    return [
        {
            "user_id": str(m["user_id"]),
            "muted_sources": [str(u) for u in m["muted_sources"]],
        }
        for m in result.mappings()
    ]


async def build_backup(session: AsyncSession, plan: CleanupPlan) -> dict:
    """Snapshot restaurable des lignes affectées (avant mutation)."""
    muted = await _fetch_muted_map(session, plan.deleted_ids)
    return {
        "generated_at": datetime.now(UTC).isoformat(),
        "test_junk": [s.to_dict() for s in plan.test_junk],
        "genuinely_dead": [s.to_dict() for s in plan.genuinely_dead],
        "broken_feed_legit": [s.to_dict() for s in plan.broken_feed_legit],
        "merges": [
            {
                "media": m.media,
                "winner": m.winner.to_dict(),
                "loser": m.loser.to_dict(),
                "winner_updates": m.winner_updates,
            }
            for m in plan.merges
        ],
        "muted_sources_touched": muted,
        "keep_count": plan.keep_count,
    }


# --------------------------------------------------------------------------- #
# Application (mutation)
# --------------------------------------------------------------------------- #


async def _array_remove_muted(session: AsyncSession, source_id: UUID) -> None:
    # muted_sources est un ARRAY uuid sans FK : CASCADE ne le nettoie pas (R6).
    await session.execute(
        text(
            "UPDATE user_personalization "
            "SET muted_sources = array_remove(muted_sources, :sid) "
            "WHERE :sid = ANY(muted_sources)"
        ),
        {"sid": source_id},
    )


async def _merge_one(session: AsyncSession, merge: Merge) -> None:
    loser, winner = merge.loser.id, merge.winner.id
    p = {"loser": loser, "winner": winner}

    # 1) Contents : dédup guid (pré-supprime les doublons), puis re-pointe.
    await session.execute(
        text(
            "DELETE FROM contents WHERE source_id = :loser "
            "AND guid IN (SELECT guid FROM contents WHERE source_id = :winner)"
        ),
        p,
    )
    await session.execute(
        text("UPDATE contents SET source_id = :winner WHERE source_id = :loser"), p
    )

    # 2) user_sources : UNIQUE(user_id, source_id) -> supprime collisions puis re-pointe.
    await session.execute(
        text(
            "DELETE FROM user_sources WHERE source_id = :loser "
            "AND user_id IN (SELECT user_id FROM user_sources WHERE source_id = :winner)"
        ),
        p,
    )
    await session.execute(
        text("UPDATE user_sources SET source_id = :winner WHERE source_id = :loser"), p
    )

    # 3) user_favorite_sources : UNIQUE(user_id, source_id).
    await session.execute(
        text(
            "DELETE FROM user_favorite_sources WHERE source_id = :loser "
            "AND user_id IN (SELECT user_id FROM user_favorite_sources WHERE source_id = :winner)"
        ),
        p,
    )
    await session.execute(
        text(
            "UPDATE user_favorite_sources SET source_id = :winner WHERE source_id = :loser"
        ),
        p,
    )

    # 4) veille_sources : RESTRICT + UNIQUE(veille_config_id, source_id).
    await session.execute(
        text(
            "DELETE FROM veille_sources WHERE source_id = :loser "
            "AND veille_config_id IN "
            "(SELECT veille_config_id FROM veille_sources WHERE source_id = :winner)"
        ),
        p,
    )
    await session.execute(
        text("UPDATE veille_sources SET source_id = :winner WHERE source_id = :loser"),
        p,
    )

    # 5) Transfert éval/curated au winner (s'il en manque).
    updates = merge.winner_updates
    if updates:
        set_clause = ", ".join(f"{col} = :{col}" for col in updates)
        params = {**updates, "winner": winner}
        await session.execute(
            text(f"UPDATE sources SET {set_clause} WHERE id = :winner"), params
        )

    # 6) muted_sources + 7) delete perdant (libère feed_url UNIQUE).
    await _array_remove_muted(session, loser)
    await session.execute(
        text("DELETE FROM sources WHERE id = :loser"), {"loser": loser}
    )


async def _delete_predicate(session: AsyncSession, s: SourceRow) -> bool:
    # Re-vérifie veille (RESTRICT) dans la tx : skip propre si référencé.
    cnt = await session.execute(
        text("SELECT count(*) FROM veille_sources WHERE source_id = :sid"),
        {"sid": s.id},
    )
    if cnt.scalar_one() > 0:
        print(f"  ! SKIP {s.name} ({s.id}) — référencé par veille_sources (RESTRICT)")
        return False
    await _array_remove_muted(session, s.id)
    # contents / user_sources / user_favorite_sources cascadent automatiquement.
    await session.execute(text("DELETE FROM sources WHERE id = :sid"), {"sid": s.id})
    return True


async def apply_plan(session: AsyncSession, plan: CleanupPlan) -> dict:
    """Applique merges + suppressions. Le commit/rollback est géré par l'appelant."""
    counts = {"merged": 0, "deleted": 0, "skipped": 0}
    for merge in plan.merges:
        await _merge_one(session, merge)
        counts["merged"] += 1
    for s in plan.predicate_delete:
        if await _delete_predicate(session, s):
            counts["deleted"] += 1
        else:
            counts["skipped"] += 1
    return counts


# --------------------------------------------------------------------------- #
# Rapport
# --------------------------------------------------------------------------- #


def render_report(plan: CleanupPlan) -> str:
    lines: list[str] = []
    lines.append("=" * 78)
    lines.append("RAPPORT NETTOYAGE SOURCES (dry-run)")
    lines.append("=" * 78)
    lines.append(
        f"TEST_JUNK (delete)        : {len(plan.test_junk)}\n"
        f"TRUE_DUPLICATE (merge)    : {len(plan.merges)}\n"
        f"GENUINELY_DEAD (delete)   : {len(plan.genuinely_dead)}\n"
        f"BROKEN_FEED_LEGIT (garder): {len(plan.broken_feed_legit)}\n"
        f"KEEP                      : {plan.keep_count}"
    )
    lines.append("-" * 78)
    lines.append("FUSIONS (perdant -> winner ; web préféré sinon max content) :")
    for m in plan.merges:
        survives = m.winner.type
        stops = m.loser.type
        consequence = (
            f"  [R5 feed {survives} survit, {stops} cesse d'ingérer]"
            if m.winner.type != m.loser.type
            else ""
        )
        upd = ", ".join(m.winner_updates) or "(rien)"
        lines.append(
            f"  • {m.media}: garder {m.winner.feed_url} ({m.winner.n_content}c) "
            f"<- supprimer {m.loser.feed_url} ({m.loser.n_content}c, "
            f"{m.loser.n_follow} follows){consequence}"
        )
        lines.append(f"      transfert au winner : {upd}")
    lines.append("-" * 78)
    lines.append("GENUINELY_DEAD :")
    for s in plan.genuinely_dead:
        lines.append(f"  • {s.name} ({s.feed_url})")
    lines.append("-" * 78)
    lines.append("BROKEN_FEED_LEGIT (rapport seulement -> repair_broken_feeds.py) :")
    for s in plan.broken_feed_legit:
        lines.append(f"  • {s.name} ({s.n_follow} follows) — {s.feed_url}")
    lines.append("=" * 78)
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def _is_test_db(url: str) -> bool:
    url = url or ""
    return any(t in url for t in (":54322", "facteur_test", "localhost", "127.0.0.1"))


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    root = Path(__file__).resolve().parents[3]
    return root / ".context" / f"cleanup_sources_backup_{ts}.json"


async def run(apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    target = db_url.split("@")[-1] if "@" in db_url else db_url
    print(f"DB cible : {target}  (test={is_test})")

    if apply and not is_test and not allow_prod:
        print(
            "\nABORT : --apply contre une DB non-test sans --allow-prod.\n"
            "L'écriture en prod est gated (creds write + GO PO). "
            "Relance avec --allow-prod en toute connaissance de cause."
        )
        return 2

    async with async_session_maker() as session:
        try:
            rows = await gather_stats(session)
            plan = build_plan(rows)
            backup = await build_backup(session, plan)

            bpath = _backup_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(json.dumps(backup, indent=2, ensure_ascii=False))
            print(f"Backup écrit : {bpath}")

            print(render_report(plan))

            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            counts = await apply_plan(session, plan)
            await session.commit()
            print(
                f"\nAPPLIQUÉ : {counts['merged']} fusions, "
                f"{counts['deleted']} suppressions, {counts['skipped']} skips."
            )
            return 0
        except CleanupAbort as exc:
            await session.rollback()
            print(f"\n{exc}")
            return 3
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod",
        action="store_true",
        help="autorise --apply contre une DB non-test (prod, gated PO)",
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(run(apply=args.apply, allow_prod=args.allow_prod)))


if __name__ == "__main__":
    main()
