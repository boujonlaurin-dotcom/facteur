#!/usr/bin/env python3
"""Création (upsert idempotent) d'un `media_eval_runs` — acte délibéré.

``date_reference`` **pilote la fenêtre de fraîcheur** (build_eval_input) : un
run rejoué plus tard doit produire exactement les mêmes entrées évaluateur.
Sa création est donc un acte audité — pas un ``ensure_run()`` implicite. Les
collecteurs et ``build_eval_input`` appellent ``require_run()`` (dans
``collect_common`` / ``ingest_artifacts``) qui **lève** si le run est absent.

Upsert par ``run_id`` : insert si absent, mise à jour de libellé/périmètre
sinon. **Un changement de ``date_reference`` est refusé** (rejouabilité) —
supprimer et recréer le run explicitement. **Dry-run par défaut**, ``--apply``
gardé (``--allow-prod`` hors DB test).

Usage :
    cd packages/api
    python3 scripts/media_eval/create_run.py --run-id pilote-2026-07 \
        --date-reference 2026-07-10 --medias cnews.fr reporterre.net
    python3 scripts/media_eval/create_run.py --run-id pilote-2026-07 \
        --date-reference 2026-07-10 --apply --allow-prod
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from datetime import UTC, date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import MediaEvalRun
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.schemas import GRILLES, VERSION_METHODO_COURANTE, grille


class RunConflit(Exception):
    """Un run existe déjà avec une ``date_reference`` différente."""


async def upsert_run(
    session,
    *,
    run_id: str,
    date_reference: date,
    libelle: str | None,
    medias: list[str],
    criteres: list[str],
    version_methodo: str = VERSION_METHODO_COURANTE,
) -> tuple[str, MediaEvalRun]:
    """Insert/maj idempotent. Retourne (action, run) — sans commit.

    ``action`` ∈ {"cree", "maj", "inchange"}. Lève ``RunConflit`` si le run
    existe avec une autre ``date_reference`` (jamais de changement silencieux).
    ``version_methodo`` est figée à la création (jamais mutée ensuite).
    """
    existant = (
        await session.execute(select(MediaEvalRun).where(MediaEvalRun.run_id == run_id))
    ).scalar_one_or_none()
    perimetre = {"medias": medias, "criteres": criteres}

    if existant is None:
        session.add(
            MediaEvalRun(
                run_id=run_id,
                libelle=libelle,
                version_methodo=version_methodo,
                date_reference=date_reference,
                perimetre=perimetre,
            )
        )
        return "cree", existant  # existant=None : caller n'en a pas besoin

    if existant.date_reference != date_reference:
        raise RunConflit(
            f"run {run_id!r} existe avec date_reference={existant.date_reference} "
            f"≠ {date_reference} demandée. La fraîcheur en dépend : supprimer et "
            "recréer le run explicitement plutôt que de le muter."
        )

    change = False
    if libelle is not None and existant.libelle != libelle:
        existant.libelle = libelle
        change = True
    if existant.perimetre != perimetre:
        existant.perimetre = perimetre
        change = True
    return ("maj" if change else "inchange"), existant


async def run(
    *,
    run_id: str,
    date_reference: date,
    libelle: str | None,
    medias: list[str],
    criteres: list[str],
    version_methodo: str,
    apply: bool,
    allow_prod: bool,
) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    print(f"date_reference (pilote la fraîcheur) : {date_reference.isoformat()}")
    print(f"version_methodo : {version_methodo}")
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    async with async_session_maker() as session:
        try:
            action, _ = await upsert_run(
                session,
                run_id=run_id,
                date_reference=date_reference,
                libelle=libelle,
                medias=medias,
                criteres=criteres,
                version_methodo=version_methodo,
            )
            print(f"Run {run_id} : {action} (médias={medias}, critères={criteres})")
            if not apply:
                await session.rollback()
                print("(dry-run — aucune mutation. Relance avec --apply.)")
                return 0
            await session.commit()
            print(f"APPLIQUÉ : run {run_id} ({action}).")
            return 0
        except RunConflit as exc:
            await session.rollback()
            print(f"REJET : {exc}")
            return 1
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True, help="ex. pilote-2026-07")
    parser.add_argument(
        "--date-reference",
        default=datetime.now(UTC).date().isoformat(),
        help="date ISO qui pilote la fraîcheur (défaut : aujourd'hui)",
    )
    parser.add_argument("--libelle", default=None)
    parser.add_argument(
        "--medias", nargs="*", default=[], help="domaines du périmètre (mémo)"
    )
    parser.add_argument(
        "--version-methodo",
        default=VERSION_METHODO_COURANTE,
        choices=sorted(GRILLES),
        help=f"grille de méthodo du run (défaut : {VERSION_METHODO_COURANTE})",
    )
    parser.add_argument(
        "--criteres",
        nargs="*",
        default=None,
        help="critères du périmètre (défaut : vague 1 de la version choisie)",
    )
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    criteres = (
        args.criteres
        if args.criteres is not None
        else list(grille(args.version_methodo).criteres_vague_1)
    )
    sys.exit(
        asyncio.run(
            run(
                run_id=args.run_id,
                date_reference=date.fromisoformat(args.date_reference),
                libelle=args.libelle,
                medias=args.medias,
                criteres=criteres,
                version_methodo=args.version_methodo,
                apply=args.apply,
                allow_prod=args.allow_prod,
            )
        )
    )


if __name__ == "__main__":
    main()
