#!/usr/bin/env python3
"""Application des évaluations LLM en base (Composant 1, étape 1e) — SANS LLM.

Lit l'artefact relu `sources/source_evaluations_llm.json`, valide chaque ligne
(schéma Pydantic), puis upsert `description, bias_stance, reliability_score,
score_*` avec **`bias_origin='llm'`**. La `reliability_score` écrite est
**dérivée** des scores (`derive_reliability`, rubrique §2), pas la valeur LLM.
Les justifs par dimension + `sources_consulted` sont ignorés à l'écriture (revue
only). **Dry-run par défaut** (diff vieux -> proposé), `--apply` gardé (prod-guard
+ backup JSON), idempotent.

Règles :
  - **N'écrase JAMAIS** une ligne `bias_origin='curated'** sauf `--refresh-curated`.
  - **Gate de confiance** (`--confidence-threshold`, défaut 0.5) : sous le seuil
    -> `bias_stance/reliability='unknown'` + scores NULL, **description conservée**,
    `bias_origin='llm'`.
  - `recommended_by`/`recommendation_reason` ne sont **jamais** touchés.

Usage :
    cd packages/api
    python3 scripts/apply_source_evaluations.py                       # dry-run
    python3 scripts/apply_source_evaluations.py --apply --allow-prod  # prod (gated PO)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.config import get_settings
from app.database import async_session_maker, engine
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.source_eval_schema import EvaluationArtifact, SourceEvaluation

DEFAULT_ARTIFACT = (
    Path(__file__).resolve().parents[3] / "sources" / "source_evaluations_llm.json"
)
_WRITE_FIELDS = (
    "description",
    "bias_stance",
    "reliability_score",
    "score_independence",
    "score_rigor",
    "score_ux",
)


@dataclass
class Change:
    source_id: str
    name: str | None
    old: dict
    new: dict


@dataclass
class ApplyResult:
    writes: list[Change]
    skipped_curated: list[str]
    skipped_missing: list[str]


async def load_current(session, ids: list[str]) -> dict[str, dict]:
    if not ids:
        return {}
    result = await session.execute(
        text(
            "SELECT id, name, bias_origin, bias_stance, reliability_score, description, "
            "score_independence, score_rigor, score_ux FROM sources WHERE id = ANY(:ids)"
        ),
        {"ids": [UUID(i) for i in ids]},
    )
    return {str(m["id"]): dict(m) for m in result.mappings()}


def compute_changes(
    artifact: EvaluationArtifact,
    current: dict[str, dict],
    *,
    threshold: float,
    refresh_curated: bool,
) -> ApplyResult:
    """Pur : calcule les écritures, gère gate de confiance + garde curated."""
    writes: list[Change] = []
    skipped_curated: list[str] = []
    skipped_missing: list[str] = []

    for raw in artifact.evaluations:
        cur = current.get(raw.source_id)
        if cur is None:
            skipped_missing.append(raw.source_id)
            continue
        if cur["bias_origin"] == "curated" and not refresh_curated:
            skipped_curated.append(raw.source_id)
            continue

        ev: SourceEvaluation = raw.gated(threshold)
        new = {
            "description": ev.description,
            "bias_stance": ev.bias_stance,
            # reliability est DÉRIVÉE des scores (rubrique §2), pas la valeur LLM.
            # Après gate (scores null) -> derive renvoie "unknown" automatiquement.
            "reliability_score": ev.derived_reliability(),
            "score_independence": ev.score_independence,
            "score_rigor": ev.score_rigor,
            "score_ux": ev.score_ux,
            "bias_origin": "llm",
        }
        old = {f: cur[f] for f in _WRITE_FIELDS} | {"bias_origin": cur["bias_origin"]}
        if old != new:
            writes.append(
                Change(source_id=raw.source_id, name=cur["name"], old=old, new=new)
            )

    return ApplyResult(writes, skipped_curated, skipped_missing)


async def write_changes(session, writes: list[Change]) -> None:
    stmt = text(
        "UPDATE sources SET description = :description, bias_stance = :bias_stance, "
        "reliability_score = :reliability_score, score_independence = :score_independence, "
        "score_rigor = :score_rigor, score_ux = :score_ux, bias_origin = :bias_origin "
        "WHERE id = :id"
    )
    for c in writes:
        await session.execute(stmt, {**c.new, "id": UUID(c.source_id)})


def render_report(res: ApplyResult) -> str:
    lines = ["=" * 78, "APPLY ÉVALUATIONS LLM (dry-run)", "=" * 78]
    lines.append(
        f"À écrire : {len(res.writes)} | curated protégés (skip) : "
        f"{len(res.skipped_curated)} | introuvables : {len(res.skipped_missing)}"
    )
    lines.append("-" * 78)
    for c in res.writes:
        lines.append(f"• {c.name} ({c.source_id})")
        lines.append(
            f"    bias    : {c.old['bias_stance']} -> {c.new['bias_stance']}\n"
            f"    fiab    : {c.old['reliability_score']} -> {c.new['reliability_score']}\n"
            f"    origin  : {c.old['bias_origin']} -> {c.new['bias_origin']}\n"
            f"    desc    : {'(vide)' if not c.old['description'] else 'présente'} -> "
            f"{(c.new['description'] or '')[:80]}…"
        )
    lines.append("=" * 78)
    return "\n".join(lines)


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return (
        Path(__file__).resolve().parents[3]
        / ".context"
        / f"apply_evals_backup_{ts}.json"
    )


async def run(
    artifact_path: Path,
    apply: bool,
    allow_prod: bool,
    threshold: float,
    refresh_curated: bool,
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

    artifact = EvaluationArtifact.model_validate_json(artifact_path.read_text())
    ids = [e.source_id for e in artifact.evaluations]

    async with async_session_maker() as session:
        try:
            current = await load_current(session, ids)
            res = compute_changes(
                artifact, current, threshold=threshold, refresh_curated=refresh_curated
            )

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
            print(
                f"\nAPPLIQUÉ : {len(res.writes)} évaluations écrites (bias_origin=llm)."
            )
            return 0
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, default=DEFAULT_ARTIFACT)
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    parser.add_argument(
        "--confidence-threshold",
        type=float,
        default=0.5,
        help="sous ce seuil -> unknown + scores NULL (défaut 0.5)",
    )
    parser.add_argument(
        "--refresh-curated",
        action="store_true",
        help="autorise l'écrasement des lignes bias_origin='curated'",
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(
            run(
                args.artifact,
                apply=args.apply,
                allow_prod=args.allow_prod,
                threshold=args.confidence_threshold,
                refresh_curated=args.refresh_curated,
            )
        )
    )


if __name__ == "__main__":
    main()
