#!/usr/bin/env python3
"""Application de descriptions de sources (texte SEUL) — SANS LLM, SANS toucher au biais.

Pendant de `apply_source_evaluations.py`, mais **chirurgical** : lit un artefact
`{"descriptions": [{"source_id", "name"?, "description"}]}` et n'écrit QUE la
colonne `description`. Ne touche **jamais** `bias_stance`, `reliability_score`,
`score_*`, ni surtout `bias_origin` — donc sûr pour les sources
`bias_origin='curated'` (biais verrouillé PO) qui ont aujourd'hui une description
courte/nulle. Refuse une `description` contenant un tiret cadratin (règle PO copy
user-facing). **Dry-run par défaut**, `--apply` gardé (prod-guard + backup JSON),
idempotent (no-op si la description est déjà identique).

Usage :
    cd packages/api
    python3 scripts/apply_source_descriptions.py --artifact ../../sources/source_descriptions_curated.json
    python3 scripts/apply_source_descriptions.py --artifact ... --apply --allow-prod  # prod (gated PO)
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

_BANNED_DESC = ("—", "&mdash;", "&#8212;")  # tiret cadratin interdit (copy user)


@dataclass
class DescChange:
    source_id: str
    name: str | None
    old: str | None
    new: str


def _load_descriptions(path: Path) -> list[dict]:
    raw = json.loads(path.read_text())
    items = raw.get("descriptions", raw.get("evaluations", []))
    out: list[dict] = []
    for it in items:
        sid = it["source_id"]
        desc = it.get("description")
        if not desc or not desc.strip():
            raise ValueError(f"description vide pour {sid}")
        if any(tok in desc for tok in _BANNED_DESC):
            raise ValueError(f"tiret cadratin interdit dans description de {sid}")
        out.append({"source_id": sid, "description": desc})
    return out


async def _load_current(session, ids: list[str]) -> dict[str, dict]:
    if not ids:
        return {}
    result = await session.execute(
        text("SELECT id, name, description FROM sources WHERE id = ANY(:ids)"),
        {"ids": [UUID(i) for i in ids]},
    )
    return {str(m["id"]): dict(m) for m in result.mappings()}


def compute_changes(
    items: list[dict], current: dict[str, dict]
) -> tuple[list[DescChange], list[str]]:
    writes: list[DescChange] = []
    missing: list[str] = []
    for it in items:
        cur = current.get(it["source_id"])
        if cur is None:
            missing.append(it["source_id"])
            continue
        if (cur["description"] or "") == it["description"]:
            continue  # idempotent no-op
        writes.append(
            DescChange(
                source_id=it["source_id"],
                name=cur["name"],
                old=cur["description"],
                new=it["description"],
            )
        )
    return writes, missing


async def _write(session, writes: list[DescChange]) -> None:
    stmt = text("UPDATE sources SET description = :description WHERE id = :id")
    for c in writes:
        await session.execute(
            stmt, {"description": c.new, "id": UUID(c.source_id)}
        )


def render_report(writes: list[DescChange], missing: list[str]) -> str:
    lines = ["=" * 78, "APPLY DESCRIPTIONS (texte seul, dry-run)", "=" * 78]
    lines.append(f"À écrire : {len(writes)} | introuvables : {len(missing)}")
    lines.append("-" * 78)
    for c in writes:
        old_len = len(c.old or "")
        lines.append(
            f"• {c.name} ({c.source_id})\n"
            f"    desc : {old_len}c -> {len(c.new)}c | {c.new[:90]}…"
        )
    if missing:
        lines.append("-" * 78)
        lines.append("Introuvables : " + ", ".join(missing))
    lines.append("=" * 78)
    return "\n".join(lines)


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return (
        Path(__file__).resolve().parents[3]
        / ".context"
        / f"apply_descriptions_backup_{ts}.json"
    )


async def run(artifact_path: Path, *, apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})")
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    items = _load_descriptions(artifact_path)
    ids = [it["source_id"] for it in items]

    async with async_session_maker() as session:
        try:
            current = await _load_current(session, ids)
            writes, missing = compute_changes(items, current)

            bpath = _backup_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(
                json.dumps(
                    {
                        "generated_at": datetime.now(UTC).isoformat(),
                        "before": [
                            {"source_id": c.source_id, "name": c.name, "old": c.old}
                            for c in writes
                        ],
                    },
                    indent=2,
                    ensure_ascii=False,
                )
            )
            print(f"Backup écrit : {bpath}")
            print(render_report(writes, missing))

            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            await _write(session, writes)
            await session.commit()
            print(f"\nAPPLIQUÉ : {len(writes)} descriptions écrites (description seule).")
            return 0
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--apply", action="store_true", help="exécute (défaut: dry-run)")
    parser.add_argument("--allow-prod", action="store_true", help="autorise --apply en prod")
    args = parser.parse_args()
    sys.exit(asyncio.run(run(args.artifact, apply=args.apply, allow_prod=args.allow_prod)))


if __name__ == "__main__":
    main()
