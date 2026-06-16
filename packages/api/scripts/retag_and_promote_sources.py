#!/usr/bin/env python3
"""Re-tag `granular_topics` (vocab 51-slugs) + promotion catalogue (Epic 12).

Aligne la taxonomie des **sources** sur celle des **users/articles** (les 51
slugs de `classification_service.VALID_TOPIC_SLUGS`) pour que le recommender
d'onboarding matche enfin les spécialités, et élargit le catalogue curé.

Deux composants, un seul rapport :

  A1. **Dérivation `granular_topics`** — pour chaque source active, sur
      `WINDOW_DAYS` jours : agrège `unnest(contents.topics)` par topic ;
      `share = n_topic / n_total_source`. Retient un topic comme spécialité si
      `n_topic >= MIN_COUNT` **et** `share >= MIN_SHARE`, capé au top `TOP_K`
      par share décroissant. Écrit `granular_topics` **ordonné par share desc**
      (le 1er = spécialité dominante, pour le badge). Si la dérivation est vide,
      on **conserve** les slugs déjà valides (51-slugs) et on **purge** seulement
      l'ancien vocab — jamais de wipe d'un vrai spécialiste mince.

  A2. **Promotion catalogue** — `is_active AND NOT is_curated` avec
      `bias_stance <> 'unknown'` **et** `reliability_score IN {medium,high}`
      **et** `articles_30d >= MIN_VOLUME` -> `is_curated = true`.

Sorties : (a) mutation DB gatée + backup JSON ; (b) `--write-csv` régénère les
colonnes `granular_topics`/`Status` de `sources/sources_master.csv` (relisible
par le PO, ajoute les lignes des communautaires promues) ; (c) **audit de
couverture** : pour les 51 subtopics, nb de sources curées spécialistes
(doit être >=1 partout).

**`secondary_themes` n'est JAMAIS touché** (vocab macro-thème, consommé par le
digest). Pas de DDL -> pas de migration Alembic (backfill data, expand-contract).

Usage :
    cd packages/api
    python3 scripts/retag_and_promote_sources.py                       # dry-run
    python3 scripts/retag_and_promote_sources.py --write-csv            # + diff CSV
    python3 scripts/retag_and_promote_sources.py --apply --allow-prod   # prod (gated PO)
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.config import get_settings
from app.database import async_session_maker, engine
from app.services.ml.classification_service import VALID_TOPIC_SLUGS
from scripts.cleanup_orphan_sources import _is_test_db

# --------------------------------------------------------------------------- #
# Seuils (tunables — calibrés via l'audit de couverture).
# --------------------------------------------------------------------------- #
WINDOW_DAYS = 90  # fenêtre d'agrégation des articles classés
MIN_COUNT = 4  # nb mini d'articles taggés d'un topic pour le retenir
MIN_SHARE = 0.10  # part mini de la production de la source sur ce topic
TOP_K = 6  # nb max de spécialités gardées (par share desc)

PROMO_WINDOW_DAYS = 30  # fenêtre du volume pour la promotion
PROMO_MIN_VOLUME = 20  # articles_30d mini pour promouvoir
PROMO_RELIABILITY = {"medium", "high"}

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CSV = PROJECT_ROOT / "sources" / "sources_master.csv"

# DB enum value -> libellé colonne CSV "Type"
_TYPE_TO_CSV = {
    "article": "Site",
    "podcast": "Podcast",
    "youtube": "YouTube",
    "video": "YouTube",
    "reddit": "Site",
}


# --------------------------------------------------------------------------- #
# Données chargées (thin DB layer)
# --------------------------------------------------------------------------- #
@dataclass
class SourceMeta:
    source_id: str
    name: str
    url: str
    theme: str | None
    type: str
    is_curated: bool
    bias_stance: str
    reliability_score: str
    description: str | None
    score_independence: float | None
    score_rigor: float | None
    score_ux: float | None
    source_tier: str
    granular_topics: list[str] | None
    articles_30d: int


@dataclass
class TopicChange:
    source_id: str
    name: str
    url: str
    old: list[str] | None
    new: list[str] | None


@dataclass
class Promotion:
    source_id: str
    name: str
    url: str
    theme: str | None
    type: str
    bias_stance: str
    reliability_score: str
    description: str | None
    score_independence: float | None
    score_rigor: float | None
    score_ux: float | None
    source_tier: str
    granular_topics: list[str] | None
    articles_30d: int


@dataclass
class RetagPlan:
    topic_changes: list[TopicChange]
    promotions: list[Promotion]
    # source_id -> état après plan (pour CSV / audit)
    granular_after: dict[str, list[str] | None] = field(default_factory=dict)
    curated_after: dict[str, bool] = field(default_factory=dict)
    coverage_contains: dict[str, int] = field(default_factory=dict)
    coverage_dominant: dict[str, int] = field(default_factory=dict)
    coverage_gaps: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Logique pure (testable sans DB)
# --------------------------------------------------------------------------- #
def derive_granular_topics(
    topic_counts: dict[str, int],
    total: int,
    *,
    min_count: int = MIN_COUNT,
    min_share: float = MIN_SHARE,
    top_k: int = TOP_K,
    valid_slugs: set[str] = VALID_TOPIC_SLUGS,
) -> list[str]:
    """Spécialités d'une source dérivées de la part de production par topic.

    Retient `topic` si `n >= min_count` ET `n/total >= min_share`. Trie par
    share décroissant (départage par compte puis alpha), cape au top K. Ignore
    les slugs hors taxonomie 51 (défensif contre l'ancien vocab résiduel).
    """
    if total <= 0:
        return []
    ranked: list[tuple[str, float, int]] = []
    for topic, n in topic_counts.items():
        if topic not in valid_slugs:
            continue
        share = n / total
        if n >= min_count and share >= min_share:
            ranked.append((topic, share, n))
    ranked.sort(key=lambda x: (-x[1], -x[2], x[0]))
    return [t for t, _, _ in ranked[:top_k]]


def resolve_new_topics(
    derived: list[str],
    existing: list[str] | None,
    *,
    valid_slugs: set[str] = VALID_TOPIC_SLUGS,
) -> list[str] | None:
    """Décide la valeur `granular_topics` finale, conservatrice.

    - Dérivation non vide -> elle gagne (data-driven, ordonnée par share).
    - Dérivation vide -> on **garde** les slugs déjà valides et on **purge**
      l'ancien vocab (slug hors 51). Jamais de wipe d'un vrai spécialiste mince.
      Renvoie None quand il ne reste rien.
    """
    if derived:
        return derived
    cleaned = [t for t in (existing or []) if t in valid_slugs]
    return cleaned or None


def is_promotable(
    m: SourceMeta,
    *,
    min_volume: int = PROMO_MIN_VOLUME,
    reliability_set: set[str] = PROMO_RELIABILITY,
) -> bool:
    """Source évaluée + productive, non encore curée : candidate à la promotion."""
    return (
        not m.is_curated
        and m.bias_stance != "unknown"
        and m.reliability_score in reliability_set
        and m.articles_30d >= min_volume
    )


def compute_plan(
    metas: list[SourceMeta],
    topic_stats: dict[str, dict[str, int]],
    totals: dict[str, int],
    *,
    min_count: int = MIN_COUNT,
    min_share: float = MIN_SHARE,
    top_k: int = TOP_K,
    min_volume: int = PROMO_MIN_VOLUME,
    reliability_set: set[str] = PROMO_RELIABILITY,
    valid_slugs: set[str] = VALID_TOPIC_SLUGS,
) -> RetagPlan:
    """Construit le plan complet (changes + promotions + audit) sans I/O."""
    topic_changes: list[TopicChange] = []
    promotions: list[Promotion] = []
    granular_after: dict[str, list[str] | None] = {}
    curated_after: dict[str, bool] = {}

    for m in metas:
        derived = derive_granular_topics(
            topic_stats.get(m.source_id, {}),
            totals.get(m.source_id, 0),
            min_count=min_count,
            min_share=min_share,
            top_k=top_k,
            valid_slugs=valid_slugs,
        )
        new_topics = resolve_new_topics(
            derived, m.granular_topics, valid_slugs=valid_slugs
        )
        granular_after[m.source_id] = new_topics
        if new_topics != m.granular_topics:
            topic_changes.append(
                TopicChange(
                    source_id=m.source_id,
                    name=m.name,
                    url=m.url,
                    old=m.granular_topics,
                    new=new_topics,
                )
            )

        promote = is_promotable(
            m, min_volume=min_volume, reliability_set=reliability_set
        )
        curated_after[m.source_id] = m.is_curated or promote
        if promote:
            promotions.append(
                Promotion(
                    source_id=m.source_id,
                    name=m.name,
                    url=m.url,
                    theme=m.theme,
                    type=m.type,
                    bias_stance=m.bias_stance,
                    reliability_score=m.reliability_score,
                    description=m.description,
                    score_independence=m.score_independence,
                    score_rigor=m.score_rigor,
                    score_ux=m.score_ux,
                    source_tier=m.source_tier,
                    granular_topics=new_topics,
                    articles_30d=m.articles_30d,
                )
            )

    coverage_contains, coverage_dominant = _coverage_audit(
        metas, granular_after, curated_after, valid_slugs
    )
    gaps = sorted(s for s in valid_slugs if coverage_contains.get(s, 0) == 0)

    return RetagPlan(
        topic_changes=topic_changes,
        promotions=promotions,
        granular_after=granular_after,
        curated_after=curated_after,
        coverage_contains=coverage_contains,
        coverage_dominant=coverage_dominant,
        coverage_gaps=gaps,
    )


def _coverage_audit(
    metas: list[SourceMeta],
    granular_after: dict[str, list[str] | None],
    curated_after: dict[str, bool],
    valid_slugs: set[str],
) -> tuple[dict[str, int], dict[str, int]]:
    """Pour chaque slug : nb de sources curées (après plan) qui le portent.

    `contains` = slug dans `granular_topics` (le recommender peut le surfacer via
    la garantie de couverture). `dominant` = slug en 1re position (badge naturel).
    """
    contains = dict.fromkeys(valid_slugs, 0)
    dominant = dict.fromkeys(valid_slugs, 0)
    for m in metas:
        if not curated_after.get(m.source_id):
            continue
        gt = granular_after.get(m.source_id) or []
        for slug in set(gt):
            if slug in contains:
                contains[slug] += 1
        if gt and gt[0] in dominant:
            dominant[gt[0]] += 1
    return contains, dominant


# --------------------------------------------------------------------------- #
# Régénération CSV (pure — testable avec des lignes synthétiques)
# --------------------------------------------------------------------------- #
def _norm_url(u: str | None) -> str:
    return (u or "").strip().rstrip("/").lower()


def _is_source_row(row: dict) -> bool:
    name = (row.get("Name") or "").strip()
    url = (row.get("URL") or "").strip()
    return bool(name) and name != "Name" and not name.startswith("#") and bool(url)


def regenerate_csv_rows(
    rows: list[dict],
    fieldnames: list[str],
    granular_by_url: dict[str, list[str] | None],
    curated_by_url: dict[str, bool],
    promotions: list[Promotion],
) -> list[dict]:
    """Met à jour `granular_topics`/`Status` des lignes existantes (match URL) et
    ajoute les lignes des sources promues absentes du CSV. Préserve l'ordre, les
    lignes de commentaire et toutes les autres colonnes.
    """
    present: set[str] = set()
    out: list[dict] = []
    for row in rows:
        new_row = dict(row)
        if _is_source_row(row):
            key = _norm_url(row.get("URL"))
            present.add(key)
            if key in granular_by_url:
                gt = granular_by_url[key]
                new_row["granular_topics"] = (
                    json.dumps(gt, ensure_ascii=False) if gt else ""
                )
            # On ne fait que *promouvoir* (jamais downgrade), et on ne touche
            # pas les lignes ARCHIVED.
            status = (row.get("Status") or "").strip().upper()
            if curated_by_url.get(key) and status not in ("CURATED", "ARCHIVED"):
                new_row["Status"] = "CURATED"
        out.append(new_row)

    for p in promotions:
        if _norm_url(p.url) in present:
            continue
        out.append(_promotion_to_csv_row(p, fieldnames))
    return out


def _promotion_to_csv_row(p: Promotion, fieldnames: list[str]) -> dict:
    def _fmt(v: float | None) -> str:
        return "" if v is None else f"{v:g}"

    base = dict.fromkeys(fieldnames, "")
    base.update(
        {
            "Name": p.name,
            "URL": p.url,
            "Type": _TYPE_TO_CSV.get(p.type, "Site"),
            "Thème": p.theme or "",
            "Status": "CURATED",
            "Rationale": p.description or "",
            "Bias": p.bias_stance,
            "Reliability": p.reliability_score,
            "Score_Independence": _fmt(p.score_independence),
            "Score_Rigor": _fmt(p.score_rigor),
            "Score_UX": _fmt(p.score_ux),
            "granular_topics": json.dumps(p.granular_topics, ensure_ascii=False)
            if p.granular_topics
            else "",
            "source_tier": p.source_tier or "mainstream",
        }
    )
    return {fn: base.get(fn, "") for fn in fieldnames}


def write_csv(path: Path, plan: RetagPlan, metas: list[SourceMeta]) -> int:
    """Régénère le CSV depuis le plan. Renvoie le nb de lignes écrites."""
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)

    url_for = {m.source_id: m.url for m in metas}
    granular_by_url = {
        _norm_url(url_for[sid]): gt for sid, gt in plan.granular_after.items()
    }
    curated_by_url = {
        _norm_url(url_for[sid]): cur for sid, cur in plan.curated_after.items()
    }

    new_rows = regenerate_csv_rows(
        rows, fieldnames, granular_by_url, curated_by_url, plan.promotions
    )
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_MINIMAL)
        writer.writeheader()
        writer.writerows(new_rows)
    return len(new_rows)


# --------------------------------------------------------------------------- #
# DB layer (thin)
# --------------------------------------------------------------------------- #
async def load_metas(session) -> list[SourceMeta]:
    sql = text(
        f"""
        SELECT s.id, s.name, s.url, s.theme, s.type, s.is_curated,
               s.bias_stance, s.reliability_score, s.description,
               s.score_independence, s.score_rigor, s.score_ux,
               s.source_tier, s.granular_topics,
               COALESCE(a30.n, 0) AS articles_30d
        FROM sources s
        LEFT JOIN (
            SELECT source_id, COUNT(*) AS n
            FROM contents
            WHERE published_at >= now() - interval '{PROMO_WINDOW_DAYS} days'
            GROUP BY source_id
        ) a30 ON a30.source_id = s.id
        WHERE s.is_active
        """
    )
    result = await session.execute(sql)
    metas: list[SourceMeta] = []
    for r in result.mappings():
        metas.append(
            SourceMeta(
                source_id=str(r["id"]),
                name=r["name"],
                url=r["url"],
                theme=r["theme"],
                type=str(r["type"]),
                is_curated=bool(r["is_curated"]),
                bias_stance=str(r["bias_stance"]),
                reliability_score=str(r["reliability_score"]),
                description=r["description"],
                score_independence=r["score_independence"],
                score_rigor=r["score_rigor"],
                score_ux=r["score_ux"],
                source_tier=r["source_tier"] or "mainstream",
                granular_topics=list(r["granular_topics"])
                if r["granular_topics"]
                else None,
                articles_30d=int(r["articles_30d"]),
            )
        )
    return metas


async def load_topic_stats(
    session,
) -> tuple[dict[str, dict[str, int]], dict[str, int]]:
    counts_sql = text(
        f"""
        SELECT c.source_id AS sid, topic, COUNT(*) AS n
        FROM contents c
        JOIN sources s ON s.id = c.source_id AND s.is_active
        CROSS JOIN LATERAL unnest(c.topics) AS topic
        WHERE c.published_at >= now() - interval '{WINDOW_DAYS} days'
          AND c.topics IS NOT NULL
        GROUP BY c.source_id, topic
        """
    )
    totals_sql = text(
        f"""
        SELECT c.source_id AS sid, COUNT(*) AS n
        FROM contents c
        JOIN sources s ON s.id = c.source_id AND s.is_active
        WHERE c.published_at >= now() - interval '{WINDOW_DAYS} days'
          AND c.topics IS NOT NULL
          AND array_length(c.topics, 1) > 0
        GROUP BY c.source_id
        """
    )
    topic_stats: dict[str, dict[str, int]] = {}
    for r in (await session.execute(counts_sql)).mappings():
        topic_stats.setdefault(str(r["sid"]), {})[str(r["topic"])] = int(r["n"])
    totals = {
        str(r["sid"]): int(r["n"])
        for r in (await session.execute(totals_sql)).mappings()
    }
    return topic_stats, totals


async def write_plan(session, plan: RetagPlan) -> None:
    topic_stmt = text("UPDATE sources SET granular_topics = :gt WHERE id = :id")
    for c in plan.topic_changes:
        await session.execute(topic_stmt, {"gt": c.new, "id": UUID(c.source_id)})
    promote_stmt = text("UPDATE sources SET is_curated = true WHERE id = :id")
    for p in plan.promotions:
        await session.execute(promote_stmt, {"id": UUID(p.source_id)})


# --------------------------------------------------------------------------- #
# Rapport
# --------------------------------------------------------------------------- #
def render_report(plan: RetagPlan, *, total_sources: int) -> str:
    lines = [
        "=" * 78,
        "RE-TAG granular_topics + PROMOTION CATALOGUE (dry-run)",
        "=" * 78,
    ]
    lines.append(
        f"Sources actives : {total_sources} | re-tag : {len(plan.topic_changes)} | "
        f"promotions : {len(plan.promotions)}"
    )

    lines.append("-" * 78)
    lines.append(f"A1. RE-TAG granular_topics ({len(plan.topic_changes)})")
    for c in plan.topic_changes[:60]:
        lines.append(f"  • {c.name}: {c.old or []} -> {c.new or []}")
    if len(plan.topic_changes) > 60:
        lines.append(f"  … (+{len(plan.topic_changes) - 60} autres)")

    lines.append("-" * 78)
    lines.append(f"A2. PROMOTIONS -> is_curated=true ({len(plan.promotions)})")
    for p in plan.promotions[:80]:
        lines.append(
            f"  • {p.name} [{p.bias_stance}/{p.reliability_score}, "
            f"{p.articles_30d} art/30j] {p.granular_topics or []}"
        )
    if len(plan.promotions) > 80:
        lines.append(f"  … (+{len(plan.promotions) - 80} autres)")

    lines.append("-" * 78)
    n_ok = sum(1 for s in VALID_TOPIC_SLUGS if plan.coverage_contains.get(s, 0) >= 1)
    lines.append(
        f"C. AUDIT COUVERTURE : {n_ok}/{len(VALID_TOPIC_SLUGS)} subtopics avec "
        f">=1 source curée spécialiste"
    )
    if plan.coverage_gaps:
        lines.append(
            f"  ⚠️ TROUS ({len(plan.coverage_gaps)}) : {', '.join(plan.coverage_gaps)}"
        )
        lines.append(
            "  (baisser MIN_COUNT/MIN_SHARE, promouvoir un spécialiste, ou sourcer un flux)"
        )
    else:
        lines.append("  ✅ Couverture complète (>=1 spécialiste par subtopic).")
    # Spécialistes *dominants* (badge naturel sans gap-fill mobile) vs simples
    # porteurs (couverts via la garantie de couverture du recommander).
    n_dom = sum(1 for s in VALID_TOPIC_SLUGS if plan.coverage_dominant.get(s, 0) >= 1)
    lines.append(
        f"  dont {n_dom}/{len(VALID_TOPIC_SLUGS)} avec un spécialiste *dominant* "
        "(badge naturel, sans gap-fill)"
    )
    # Les 8 plus minces, pour calibrer.
    thin = sorted(plan.coverage_contains.items(), key=lambda kv: kv[1])[:8]
    lines.append("  Plus minces : " + ", ".join(f"{s}={n}" for s, n in thin))
    lines.append("=" * 78)
    return "\n".join(lines)


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return PROJECT_ROOT / ".context" / f"retag_promote_backup_{ts}.json"


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
async def run(
    *,
    apply: bool,
    allow_prod: bool,
    write_csv_flag: bool,
    csv_path: Path,
) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    async with async_session_maker() as session:
        try:
            metas = await load_metas(session)
            topic_stats, totals = await load_topic_stats(session)
            plan = compute_plan(metas, topic_stats, totals)

            bpath = _backup_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(
                json.dumps(
                    {
                        "generated_at": datetime.now(UTC).isoformat(),
                        "topic_changes": [
                            {"source_id": c.source_id, "name": c.name, "old": c.old}
                            for c in plan.topic_changes
                        ],
                        "promotions": [
                            {"source_id": p.source_id, "name": p.name}
                            for p in plan.promotions
                        ],
                    },
                    indent=2,
                    ensure_ascii=False,
                )
            )
            print(f"Backup écrit : {bpath}")
            print(render_report(plan, total_sources=len(metas)))

            if write_csv_flag:
                # Garde-fou : ne pas régénérer le CSV sur une DB sans données
                # (sinon on viderait granular_topics de tout le seed).
                non_empty = sum(1 for v in plan.granular_after.values() if v)
                if non_empty < 10:
                    print(
                        f"\n⚠️ --write-csv ignoré : seules {non_empty} sources ont des "
                        "granular_topics dérivés (DB sans articles ?). Lance contre la DB "
                        "de prod en lecture pour produire un diff CSV utile."
                    )
                else:
                    n = write_csv(csv_path, plan, metas)
                    print(f"\nCSV régénéré : {csv_path} ({n} lignes)")

            if not apply:
                print("\n(dry-run — aucune mutation DB. Relance avec --apply.)")
                return 0

            await write_plan(session, plan)
            await session.commit()
            print(
                f"\nAPPLIQUÉ : {len(plan.topic_changes)} re-tags + "
                f"{len(plan.promotions)} promotions."
            )
            return 0
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
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    parser.add_argument(
        "--write-csv",
        action="store_true",
        help="régénère sources_master.csv (diff relisible PO) — sûr, fichier local",
    )
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    args = parser.parse_args()
    sys.exit(
        asyncio.run(
            run(
                apply=args.apply,
                allow_prod=args.allow_prod,
                write_csv_flag=args.write_csv,
                csv_path=args.csv,
            )
        )
    )


if __name__ == "__main__":
    main()
