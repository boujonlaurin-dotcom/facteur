#!/usr/bin/env python3
"""Dry-run du score mixte sujet (PR 4) — READ-ONLY contre la prod.

Re-trie les snapshots `daily_digest` (format `editorial_v3`+) avec la vraie clé
v4 (`digest_selector.mixed_subject_rank_score` — importée, jamais réimplémentée)
pour mesurer, par poids perso `w`, l'effet du mélange
`(1-w)·importance + w·perso` sur M1-M4 (mêmes définitions que
`docs/qa/scripts/baseline_curation.sql`) et le churn du top-5 vs l'ordre v3.

⚠️ Écart assumé vs un « vrai » rejeu : rejouer `_project_editorial_for_user`
sur des jours passés est impossible (`global_ctx` n'est pas persisté — cache
mémoire process-local, gated LLM). Mais tout l'amont du `sorted` (matching,
scoring pilier, gate solo) est invariant en `w` et matérialisé dans chaque
snapshot (`source_count`, `divergence_level`, `is_a_la_une`,
`actu_article.{published_at, score}`, `generated_at`). On re-trie donc le seul
étage qui change, restreint au pool top-10 persisté.

Caveats de lecture (docstring = contrat) :
- Pool tronqué à ~10 sujets/digest : un sujet jamais entré dans le top-10 v3
  ne peut pas apparaître ici, même si v4 l'aurait retenu. M2 plafonne donc
  ~25-30 % sans la PR 5 (pool perso rebranché).
- Lignes antérieures à la persistance du `score` → perso traitée comme 0.0
  (neutre) ; elles diluent l'effet mesuré, jamais ne l'inventent.
- Horloge du re-tri = `generated_at` du digest (naïf → UTC) : les paliers de
  récence sont rejoués à l'identique du batch d'origine.
- M1 est le levier principal à lire ; M5 (CTR suivie vs non) est illisible à
  ±5 pp sur cette fenêtre, ne rien arbitrer dessus.

Sanity check du harnais : `SUBJECT_PERSO_WEIGHT=0.0` + `SUBJECT_SOLO_MALUS=1000.0`
doit reproduire ≈ l'ordre v3 persisté (≥ 80 % des top-5 user·jour identiques en
ensembles), sinon exit 1 — on ne lit pas le tableau d'un harnais faux.

Usage:
    cd packages/api && source .venv/bin/activate
    PYTHONPATH=. python scripts/dryrun_subject_mix.py --days 7 --tag pr4-mix
    PYTHONPATH=. python scripts/dryrun_subject_mix.py --days 7 --compare

Sorties (comme dryrun_coverage_fold.py) :
    ../../.context/dryrun_subject_mix_<tag>.json  (machine)
    ../../.context/dryrun_subject_mix_<tag>.md    (lisible)

Exit : 0 = OK · 1 = sanity KO ou churn au w défaut > seuil · 2 = pas de données.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

# packages/api sur sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

# Seuils M1 (mêmes définitions que baseline_curation.sql).
QUASI_UNIVERSAL_SHARE = 0.50
PERSONAL_SHARE = 0.10
SANITY_MIN_IDENTICAL = 0.80

parser = argparse.ArgumentParser(
    description="Dry-run du score mixte sujet PR 4 (read-only prod)"
)
parser.add_argument(
    "--days", type=int, default=7, help="Fenêtre de digests (défaut: 7 jours)"
)
parser.add_argument(
    "--max-users",
    type=int,
    default=0,
    help="Cap de users échantillonnés (0 = tous, défaut)",
)
parser.add_argument(
    "--weights",
    default="0,0.25,0.40,0.55,0.70",
    help="Valeurs de SUBJECT_PERSO_WEIGHT balayées (défaut: 0,0.25,0.40,0.55,0.70)",
)
parser.add_argument("--tag", default="pr4-mix", help="Nom du run (défaut: pr4-mix)")
parser.add_argument(
    "--churn-threshold",
    type=float,
    default=0.60,
    help="Churn moyen max toléré au w défaut (défaut: 0.60)",
)
parser.add_argument(
    "--compare",
    action="store_true",
    help="Affiche le détail par poids en plus du résumé",
)
args = parser.parse_args()

# Aucun LLM n'est appelé ; on neutralise la clé par précaution.
os.environ["MISTRAL_API_KEY"] = ""

from sqlalchemy import select  # noqa: E402

from app.database import async_session_maker, engine  # noqa: E402
from app.models.content import UserContentStatus  # noqa: E402
from app.models.daily_digest import DailyDigest  # noqa: E402
from app.models.enums import ContentStatus  # noqa: E402
from app.services.digest_selector import mixed_subject_rank_score  # noqa: E402
from app.services.recommendation.scoring_config import ScoringWeights  # noqa: E402


def _as_utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=UTC) if dt.tzinfo is None else dt


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return _as_utc(datetime.fromisoformat(value))
    except ValueError:
        return None


def _editorial_version(fmt: str | None) -> int:
    """`editorial_v3` → 3 ; tout format non-editorial → 0."""
    prefix = "editorial_v"
    if not fmt or not fmt.startswith(prefix):
        return 0
    try:
        return int(fmt[len(prefix) :])
    except ValueError:
        return 0


class DigestSnapshot(SimpleNamespace):
    """Un daily_digest reconstruit : sujets triables + score_map + baseline v3."""


def _load_snapshot(digest: DailyDigest) -> DigestSnapshot | None:
    items = digest.items if isinstance(digest.items, dict) else {}
    raw_subjects = items.get("subjects") or []
    subjects: list[SimpleNamespace] = []
    score_map: dict[str, float] = {}
    for s in raw_subjects:
        if not isinstance(s, dict):
            continue
        actu = s.get("actu_article")
        actu_ns = None
        if isinstance(actu, dict) and actu.get("content_id"):
            actu_ns = SimpleNamespace(
                content_id=actu["content_id"],
                published_at=_parse_dt(actu.get("published_at")),
            )
            if actu.get("score") is not None:
                score_map[actu["content_id"]] = float(actu["score"])
        subjects.append(
            SimpleNamespace(
                rank=int(s.get("rank") or 0),
                source_count=int(s.get("source_count") or 0),
                divergence_level=s.get("divergence_level"),
                is_a_la_une=bool(s.get("is_a_la_une")),
                is_user_source=bool((actu or {}).get("is_user_source")),
                theme=s.get("theme"),
                source_name=(actu or {}).get("source_name"),
                actu_article=actu_ns,
            )
        )
    if not subjects:
        return None
    baseline_top5 = {
        s.actu_article.content_id
        for s in subjects
        if s.actu_article is not None and 1 <= s.rank <= 5
    }
    return DigestSnapshot(
        user_id=str(digest.user_id),
        target_date=digest.target_date,
        mode=digest.mode or "pour_vous",
        now=_as_utc(digest.generated_at),
        subjects=subjects,
        score_map=score_map,
        baseline_top5=baseline_top5,
    )


async def _load_snapshots(days: int, max_users: int) -> list[DigestSnapshot]:
    since = date.today() - timedelta(days=days)
    stmt = (
        select(DailyDigest)
        .where(
            DailyDigest.format_version.startswith("editorial_v", autoescape=True),
            DailyDigest.target_date >= since,
        )
        .order_by(DailyDigest.user_id, DailyDigest.generated_at)
    )
    async with async_session_maker() as session:
        result = await session.execute(stmt)
        digests = [
            d
            for d in result.scalars().all()
            if _editorial_version(d.format_version) >= 3
        ]

    if max_users > 0:
        kept_users = sorted({str(d.user_id) for d in digests})[:max_users]
        digests = [d for d in digests if str(d.user_id) in kept_users]

    snapshots = [snap for d in digests if (snap := _load_snapshot(d)) is not None]
    return snapshots


def _resort_top(snapshot: DigestSnapshot) -> list[SimpleNamespace]:
    """Rejoue le seul étage qui change : à-la-une épinglé + tri stable par clé v4."""
    une = [s for s in snapshot.subjects if s.is_a_la_une]
    rest = [s for s in snapshot.subjects if not s.is_a_la_une]
    rest_sorted = sorted(
        rest,
        key=lambda s: mixed_subject_rank_score(
            s, score_map=snapshot.score_map, now=snapshot.now
        ),
        reverse=True,
    )
    return [s for s in une + rest_sorted if s.actu_article is not None]


def _top5_ids(ordered: list[SimpleNamespace]) -> set[str]:
    return {s.actu_article.content_id for s in ordered[:5]}


async def _load_consumed_pairs(
    snapshots: list[DigestSnapshot],
) -> set[tuple[str, str]]:
    """Paires (user_id, content_id) consommées, pour le CTR de M4."""
    from uuid import UUID

    content_ids: set[str] = set()
    user_ids: set[str] = set()
    for snap in snapshots:
        user_ids.add(snap.user_id)
        for s in snap.subjects:
            if s.actu_article is not None:
                content_ids.add(s.actu_article.content_id)
    if not content_ids:
        return set()
    stmt = select(UserContentStatus.user_id, UserContentStatus.content_id).where(
        UserContentStatus.status == ContentStatus.CONSUMED,
        UserContentStatus.user_id.in_([UUID(u) for u in user_ids]),
        UserContentStatus.content_id.in_([UUID(c) for c in content_ids]),
    )
    async with async_session_maker() as session:
        rows = await session.execute(stmt)
        return {(str(u), str(c)) for u, c in rows.all()}


def _metrics_for_weight(
    snapshots: list[DigestSnapshot],
    consumed: set[tuple[str, str]],
) -> dict:
    """M1-M4 + churn sur l'ordre re-trié courant (poids déjà `setattr`)."""
    # slot rows: (user_id, target_date, mode, position, subject)
    top5_by_day: dict[tuple[date, str], list[tuple[str, str]]] = defaultdict(list)
    zone_slots = {"1-5": [], "6-10": []}
    theme_counter: Counter[str] = Counter()
    source_counter: Counter[str] = Counter()
    source_reads: Counter[str] = Counter()
    churns: list[float] = []

    for snap in snapshots:
        ordered = _resort_top(snap)
        for pos, s in enumerate(ordered[:10], start=1):
            zone = "1-5" if pos <= 5 else "6-10"
            zone_slots[zone].append((s.is_user_source, s.source_count == 1))
        for s in ordered[:5]:
            cid = s.actu_article.content_id
            top5_by_day[(snap.target_date, snap.mode)].append((snap.user_id, cid))
            theme_counter[s.theme or "(null)"] += 1
            name = s.source_name or "(inconnu)"
            source_counter[name] += 1
            if (snap.user_id, cid) in consumed:
                source_reads[name] += 1
        if snap.baseline_top5:
            new_top5 = _top5_ids(ordered)
            denom = max(len(snap.baseline_top5), 1)
            churns.append(len(snap.baseline_top5 - new_top5) / denom)

    # M1 — quasi-universels / personnels, par mode.
    m1: dict[str, dict[str, float]] = {}
    per_mode_slots: dict[str, list[float]] = defaultdict(list)
    for (target_date, mode), pairs in top5_by_day.items():
        users_total = len({u for u, _ in pairs})
        if users_total == 0:
            continue
        share_by_content = Counter()
        for _, cid in pairs:
            share_by_content[cid] += 1
        by_users: dict[str, int] = defaultdict(int)
        for cid in {c for _, c in pairs}:
            by_users[cid] = len({u for u, c in pairs if c == cid})
        for _, cid in pairs:
            per_mode_slots[mode].append(by_users[cid] / users_total)
    for mode, shares in per_mode_slots.items():
        total = len(shares)
        m1[mode] = {
            "slots": total,
            "pct_quasi_universels": round(
                100.0 * sum(s >= QUASI_UNIVERSAL_SHARE for s in shares) / total, 1
            ),
            "pct_personnels": round(
                100.0 * sum(s < PERSONAL_SHARE for s in shares) / total, 1
            ),
        }

    # M2 — zone 1-5 vs 6-10.
    m2 = {}
    for zone, rows in zone_slots.items():
        if not rows:
            continue
        m2[zone] = {
            "slots": len(rows),
            "pct_source_suivie": round(100.0 * sum(f for f, _ in rows) / len(rows), 1),
            "pct_mono_source": round(100.0 * sum(m for _, m in rows) / len(rows), 1),
        }

    total_top5 = sum(source_counter.values()) or 1
    m3 = [
        {"theme": t, "slots": n, "pct_top5": round(100.0 * n / total_top5, 1)}
        for t, n in theme_counter.most_common(12)
    ]
    m4 = [
        {
            "source_name": name,
            "slots": n,
            "pct_top5": round(100.0 * n / total_top5, 2),
            "lus": source_reads.get(name, 0),
            "ctr_pct": round(100.0 * source_reads.get(name, 0) / n, 2),
        }
        for name, n in source_counter.most_common(15)
    ]
    churn_mean = round(sum(churns) / len(churns), 4) if churns else 0.0
    return {"M1": m1, "M2": m2, "M3": m3, "M4": m4, "churn_vs_v3": churn_mean}


def _sanity_check(snapshots: list[DigestSnapshot]) -> float:
    """Part des digests dont le top-5 re-trié (w=0, malus 1000) == top-5 persisté."""
    identical = 0
    total = 0
    for snap in snapshots:
        if not snap.baseline_top5:
            continue
        total += 1
        if _top5_ids(_resort_top(snap)) == snap.baseline_top5:
            identical += 1
    return identical / total if total else 0.0


async def run() -> int:
    weights = [float(w.strip()) for w in args.weights.split(",") if w.strip()]
    default_w = float(ScoringWeights.SUBJECT_PERSO_WEIGHT)
    if default_w not in weights:
        weights.append(default_w)
    weights.sort()

    snapshots = await _load_snapshots(args.days, args.max_users)
    if not snapshots:
        print("⚠ Aucun digest editorial_v3+ chargé — vérifier DATABASE_URL et --days.")
        return 2
    consumed = await _load_consumed_pairs(snapshots)

    orig_w = ScoringWeights.SUBJECT_PERSO_WEIGHT
    orig_malus = ScoringWeights.SUBJECT_SOLO_MALUS
    results: dict[str, dict] = {}
    try:
        # Sanity : la mécanique setattr est la même que SCORING_OVERRIDES — le
        # harnais teste au passage la lecture des poids au call time.
        ScoringWeights.SUBJECT_PERSO_WEIGHT = 0.0
        ScoringWeights.SUBJECT_SOLO_MALUS = 1000.0
        sanity = _sanity_check(snapshots)

        ScoringWeights.SUBJECT_SOLO_MALUS = 0.0
        for w in weights:
            ScoringWeights.SUBJECT_PERSO_WEIGHT = w
            results[f"{w:.2f}"] = _metrics_for_weight(snapshots, consumed)
    finally:
        ScoringWeights.SUBJECT_PERSO_WEIGHT = orig_w
        ScoringWeights.SUBJECT_SOLO_MALUS = orig_malus

    churn_at_default = results[f"{default_w:.2f}"]["churn_vs_v3"]
    sanity_ok = sanity >= SANITY_MIN_IDENTICAL
    churn_ok = churn_at_default <= args.churn_threshold

    payload = {
        "tag": args.tag,
        "days": args.days,
        "max_users": args.max_users,
        "generated_at": datetime.now(UTC).isoformat(),
        "digests_loaded": len(snapshots),
        "users": len({s.user_id for s in snapshots}),
        "consumed_pairs": len(consumed),
        "sanity_v3_identical_pct": round(sanity, 4),
        "sanity_min": SANITY_MIN_IDENTICAL,
        "sanity_ok": sanity_ok,
        "default_weight": default_w,
        "churn_threshold": args.churn_threshold,
        "churn_at_default": churn_at_default,
        "churn_ok": churn_ok,
        "results_by_weight": results,
    }

    CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = CONTEXT_DIR / f"dryrun_subject_mix_{args.tag}.json"
    md_path = CONTEXT_DIR / f"dryrun_subject_mix_{args.tag}.md"
    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8",
    )
    md_path.write_text(_render_md(payload), encoding="utf-8")

    _print_summary(payload)

    if not sanity_ok:
        print(
            f"\n❌ SANITY KO : {sanity:.0%} des top-5 identiques à v3 "
            f"(< {SANITY_MIN_IDENTICAL:.0%}) — harnais faux, tableau illisible."
        )
        return 1
    if not churn_ok:
        print(
            f"\n❌ CHURN : {churn_at_default:.0%} au w défaut {default_w} "
            f"(> {args.churn_threshold:.0%}). Revoir le poids avant de merger."
        )
        return 1
    print(
        f"\n✅ OK — sanity {sanity:.0%}, churn @ w={default_w} : {churn_at_default:.0%}."
    )
    print(f"   JSON : {json_path}")
    print(f"   MD   : {md_path}")
    return 0


def _render_md(p: dict) -> str:
    lines = [
        f"# Dry-run score mixte sujet (PR 4) — `{p['tag']}`",
        "",
        f"- Généré : {p['generated_at']}",
        f"- Fenêtre : {p['days']} j — {p['digests_loaded']} digests, {p['users']} users",
        f"- Sanity v3 (w=0, malus 1000) : **{p['sanity_v3_identical_pct']:.0%}** "
        f"(seuil {p['sanity_min']:.0%}) — {'OK ✅' if p['sanity_ok'] else 'KO ❌'}",
        f"- Churn @ w défaut {p['default_weight']} : "
        f"**{p['churn_at_default']:.0%}** (seuil {p['churn_threshold']:.0%})",
        "",
        "## M1 — % quasi-universels / personnels (top-5) et M2 par poids",
        "",
        "| w | M1 quasi-univ (pour_vous) | M1 personnels | M2 suivie 1-5 | "
        "M2 suivie 6-10 | churn vs v3 |",
        "|---|---|---|---|---|---|",
    ]
    for w, r in p["results_by_weight"].items():
        m1 = r["M1"].get("pour_vous") or next(iter(r["M1"].values()), {})
        m2a = r["M2"].get("1-5", {})
        m2b = r["M2"].get("6-10", {})
        lines.append(
            f"| {w} | {m1.get('pct_quasi_universels', '—')} % "
            f"| {m1.get('pct_personnels', '—')} % "
            f"| {m2a.get('pct_source_suivie', '—')} % "
            f"| {m2b.get('pct_source_suivie', '—')} % "
            f"| {r['churn_vs_v3']:.0%} |"
        )
    lines += [
        "",
        "Lecture : M1 quasi-universels doit ↓ et M2 (1-5, suivie) ↑ quand w ↑.",
        "M2 plafonne ~25-30 % sans la PR 5 (pool top-10 tronqué). M3/M4 dans le JSON.",
        "",
    ]
    return "\n".join(lines)


def _print_summary(p: dict) -> None:
    print("=" * 66)
    print(f"  DRY-RUN SCORE MIXTE PR 4 — tag={p['tag']} days={p['days']}")
    print("=" * 66)
    print(f"  Digests / users   : {p['digests_loaded']} / {p['users']}")
    print(f"  Sanity v3         : {p['sanity_v3_identical_pct']:.0%}")
    print(f"  Churn @ w défaut  : {p['churn_at_default']:.0%}")
    print("  w      M1 q-univ   M1 perso   M2 suivie 1-5   churn")
    for w, r in p["results_by_weight"].items():
        m1 = r["M1"].get("pour_vous") or next(iter(r["M1"].values()), {})
        m2a = r["M2"].get("1-5", {})
        print(
            f"  {w:<6} {m1.get('pct_quasi_universels', '—'):>8} % "
            f"{m1.get('pct_personnels', '—'):>8} % "
            f"{m2a.get('pct_source_suivie', '—'):>12} % "
            f"{r['churn_vs_v3']:>7.0%}"
        )
    if args.compare:
        print("-" * 66)
        for w, r in p["results_by_weight"].items():
            top_sources = ", ".join(
                f"{row['source_name']} {row['pct_top5']}%" for row in r["M4"][:5]
            )
            print(f"  w={w} — top sources : {top_sources}")


async def _main() -> int:
    try:
        return await run()
    finally:
        await engine.dispose()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
