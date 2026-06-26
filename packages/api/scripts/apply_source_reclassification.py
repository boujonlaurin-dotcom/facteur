#!/usr/bin/env python3
"""Application des reclassifications de thème de sources (Track B, sous-track 1).

Beaucoup de sources **déjà curées + évaluées** (donc déjà Tier 2 « Catalogue
évalué ») sont mal rangées : leur `theme` / `secondary_themes` ne reflète pas
leur ligne éditoriale réelle, et elles ne remontent donc pas dans la bonne
section « Étoffer [thème] » (le routeur filtre sur
`Source.theme == slug OR secondary_themes.any(slug)`). Les re-ranger **grossit
la profondeur Tier 2 des thèmes pauvres sans aucune ré-évaluation**.

Ce script lit `sources/source_reclassification.csv` (relu par le PO) et **upsert
uniquement** `theme` + `secondary_themes` (DML pure, colonnes existantes, **pas
de migration**, insensible au drift Alembic). Il ne touche JAMAIS
`bias_stance` / `reliability_score` / `score_*` / `description` (hors scope).

Garde-fous (calqués sur `apply_source_evaluations.py`) :
  - **Additif par construction** : `secondary_themes` final =
    `union(actuels, proposés)` moins le thème primaire ; on n'efface jamais un
    secondary existant (sauf `--allow-shrink`, qui force la liste proposée telle
    quelle).
  - `proposed_theme` vide -> thème primaire **inchangé** (on n'ajoute que des
    secondary).
  - **Dry-run par défaut** (diff vieux -> proposé) ; `--apply` gardé
    (prod-guard `--allow-prod` + backup JSON `.context/`).
  - **Idempotent** : re-run sans changement = no-op.

Format CSV (entête obligatoire) :
    source_id,name,current_theme,proposed_theme,proposed_secondary_themes,...
`proposed_secondary_themes` = liste **séparée par `|`** (ex. `science|environment`),
vide = aucun ajout.

Usage :
    cd packages/api
    python3 scripts/apply_source_reclassification.py                       # dry-run
    python3 scripts/apply_source_reclassification.py --apply --allow-prod   # prod (gated PO)
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

from sqlalchemy import select, update

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.source import Source
from app.services.ml.topic_theme_mapper import VALID_THEMES
from scripts.cleanup_orphan_sources import _is_test_db

DEFAULT_CSV = (
    Path(__file__).resolve().parents[3] / "sources" / "source_reclassification.csv"
)


@dataclass
class Proposal:
    source_id: str
    name: str | None
    proposed_theme: str | None  # None / "" -> thème primaire inchangé
    proposed_secondary: list[str]  # ajouts proposés (peut être vide)


@dataclass
class Change:
    source_id: str
    name: str | None
    old: dict
    new: dict


@dataclass
class ApplyResult:
    writes: list[Change] = field(default_factory=list)
    skipped_missing: list[str] = field(default_factory=list)
    invalid_theme: list[str] = field(default_factory=list)


def _split_themes(raw: str | None) -> list[str]:
    """Parse une cellule CSV `a|b|c` en liste nettoyée (ordre préservé)."""
    if not raw:
        return []
    seen: list[str] = []
    for tok in raw.split("|"):
        t = tok.strip()
        if t and t not in seen:
            seen.append(t)
    return seen


def load_proposals(path: Path) -> list[Proposal]:
    rows: list[Proposal] = []
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            sid = (r.get("source_id") or "").strip()
            if not sid:
                continue
            rows.append(
                Proposal(
                    source_id=sid,
                    name=(r.get("name") or "").strip() or None,
                    proposed_theme=(r.get("proposed_theme") or "").strip() or None,
                    proposed_secondary=_split_themes(
                        r.get("proposed_secondary_themes")
                    ),
                )
            )
    return rows


def _merge_secondary(
    current: list[str] | None,
    additions: list[str],
    primary: str,
    *,
    allow_shrink: bool,
) -> list[str]:
    """Liste secondary finale, déterministe (triée), sans le thème primaire.

    Additif par défaut (union des existants + ajouts). `allow_shrink` force la
    liste proposée seule (utile pour une correction explicite)."""
    base = [] if allow_shrink else list(current or [])
    merged = {t for t in (*base, *additions) if t and t != primary}
    return sorted(merged)


def compute_changes(
    proposals: list[Proposal],
    current: dict[str, dict],
    *,
    allow_shrink: bool = False,
) -> ApplyResult:
    """Pur : calcule les écritures (theme + secondary_themes) à partir de l'état
    courant. Valide les slugs contre la taxonomie ; additif par construction."""
    res = ApplyResult()
    for p in proposals:
        cur = current.get(p.source_id)
        if cur is None:
            res.skipped_missing.append(p.source_id)
            continue

        new_theme = p.proposed_theme or cur["theme"]
        all_proposed = {new_theme, *p.proposed_secondary}
        bad = sorted(t for t in all_proposed if t not in VALID_THEMES)
        if bad:
            res.invalid_theme.append(f"{p.name or p.source_id}: {bad}")
            continue

        new_secondary = _merge_secondary(
            cur.get("secondary_themes"),
            p.proposed_secondary,
            new_theme,
            allow_shrink=allow_shrink,
        )
        old_secondary = sorted(cur.get("secondary_themes") or [])
        if new_theme == cur["theme"] and new_secondary == old_secondary:
            continue  # no-op (idempotent)

        res.writes.append(
            Change(
                source_id=p.source_id,
                name=cur.get("name") or p.name,
                old={"theme": cur["theme"], "secondary_themes": old_secondary},
                new={"theme": new_theme, "secondary_themes": new_secondary},
            )
        )
    return res


async def load_current(session, ids: list[str]) -> dict[str, dict]:
    if not ids:
        return {}
    result = await session.execute(
        select(Source.id, Source.name, Source.theme, Source.secondary_themes).where(
            Source.id.in_([UUID(i) for i in ids])
        )
    )
    return {
        str(m.id): {
            "name": m.name,
            "theme": m.theme,
            "secondary_themes": m.secondary_themes,
        }
        for m in result
    }


async def write_changes(session, writes: list[Change]) -> None:
    for c in writes:
        await session.execute(
            update(Source)
            .where(Source.id == UUID(c.source_id))
            .values(
                theme=c.new["theme"],
                secondary_themes=c.new["secondary_themes"],
            )
        )


def render_report(res: ApplyResult) -> str:
    lines = ["=" * 78, "APPLY RECLASSIFICATION SOURCES (dry-run)", "=" * 78]
    lines.append(
        f"À écrire : {len(res.writes)} | introuvables : {len(res.skipped_missing)} "
        f"| thèmes invalides : {len(res.invalid_theme)}"
    )
    lines.append("-" * 78)
    for c in res.writes:
        lines.append(f"• {c.name} ({c.source_id})")
        lines.append(
            f"    theme     : {c.old['theme']} -> {c.new['theme']}\n"
            f"    secondary : {c.old['secondary_themes']} -> {c.new['secondary_themes']}"
        )
    for bad in res.invalid_theme:
        lines.append(f"⚠ thème hors taxonomie (ignoré) : {bad}")
    lines.append("=" * 78)
    return "\n".join(lines)


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return (
        Path(__file__).resolve().parents[3]
        / ".context"
        / f"apply_reclassification_backup_{ts}.json"
    )


async def run(csv_path: Path, apply: bool, allow_prod: bool, allow_shrink: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    proposals = load_proposals(csv_path)
    ids = [p.source_id for p in proposals]

    async with async_session_maker() as session:
        try:
            current = await load_current(session, ids)
            res = compute_changes(proposals, current, allow_shrink=allow_shrink)

            bpath = _backup_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(
                json.dumps(
                    {
                        "generated_at": datetime.now(UTC).isoformat(),
                        "before": [
                            {"source_id": c.source_id, "name": c.name, "old": c.old}
                            for c in res.writes
                        ],
                    },
                    indent=2,
                    ensure_ascii=False,
                )
            )
            print(f"Backup écrit : {bpath}")
            print(render_report(res))

            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            await write_changes(session, res.writes)
            await session.commit()
            print(f"\nAPPLIQUÉ : {len(res.writes)} reclassification(s) écrite(s).")
            return 0
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    parser.add_argument(
        "--allow-shrink",
        action="store_true",
        help="autorise le retrait de secondary_themes existants (non additif)",
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(
            run(
                args.csv,
                apply=args.apply,
                allow_prod=args.allow_prod,
                allow_shrink=args.allow_shrink,
            )
        )
    )


if __name__ == "__main__":
    main()
