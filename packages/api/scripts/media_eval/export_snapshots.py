#!/usr/bin/env python3
"""Export des snapshots d'un run vers des fichiers texte (voie A → fichiers).

La voie A capture jusqu'à 20 000 caractères par page en DB. La voie B (agents
gouvernance) doit **lire cette substance sans re-fetcher** le site — c'est le
levier principal contre les 403 anti-bot (le contenu obtenu par ``curl_cffi``
est réutilisé). Ce script dump les snapshots vers
``.context/media_eval/<run_id>/snapshots/<slug>__<type_page>.txt`` (en-tête :
url, http_status, mode_acces, hash, collecte_at) et **liste les chemins écrits**
pour que l'orchestrateur les passe aux agents.

Lecture seule DB, écriture uniquement sous ``.context/`` (jamais commité).

Usage :
    cd packages/api
    python3 scripts/media_eval/export_snapshots.py --run-id pilote-2026-07b \
        [--media cnews.fr] [--out-root .context/media_eval]
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import MediaEvalMedia, MediaEvalSnapshot

_REPO_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_OUT_ROOT = _REPO_ROOT / ".context" / "media_eval"


def slug(domaine: str) -> str:
    return domaine.replace(".", "_")


def _type_page_str(type_page) -> str:
    return type_page.value if hasattr(type_page, "value") else str(type_page)


def nom_fichier(domaine: str, type_page, existants: set[str]) -> str:
    """``<slug>__<type_page>.txt`` — suffixe numérique si collision (déterministe)."""
    base = f"{slug(domaine)}__{_type_page_str(type_page)}"
    nom = f"{base}.txt"
    n = 2
    while nom in existants:
        nom = f"{base}__{n}.txt"
        n += 1
    existants.add(nom)
    return nom


def rendre_fichier(snap: MediaEvalSnapshot) -> str:
    """Contenu du fichier : en-tête de provenance + texte de la page (pur)."""
    mode = (
        snap.mode_acces.value if hasattr(snap.mode_acces, "value") else snap.mode_acces
    )
    entete = [
        f"url: {snap.url}",
        f"type_page: {_type_page_str(snap.type_page)}",
        f"http_status: {snap.http_status}",
        f"mode_acces: {mode}",
        f"hash: {snap.hash}",
        f"collecte_at: {snap.capture_at.isoformat() if snap.capture_at else None}",
        "",
        "---",
        "",
    ]
    return "\n".join(entete) + (snap.contenu or "")


async def charger_snapshots(
    session, run_id: str, media_domaine: str | None
) -> list[tuple[str, MediaEvalSnapshot]]:
    """Snapshots du run (option. filtrés par média) joints au domaine, triés."""
    stmt = (
        select(MediaEvalMedia.domaine, MediaEvalSnapshot)
        .join(MediaEvalMedia, MediaEvalMedia.id == MediaEvalSnapshot.media_id)
        .where(MediaEvalSnapshot.run_id == run_id)
    )
    if media_domaine:
        stmt = stmt.where(MediaEvalMedia.domaine == media_domaine)
    stmt = stmt.order_by(MediaEvalMedia.domaine, MediaEvalSnapshot.url)
    rows = await session.execute(stmt)
    return [(domaine, snap) for domaine, snap in rows.all()]


async def run(run_id: str, media_domaine: str | None, out_root: Path) -> int:
    async with async_session_maker() as session:
        try:
            snaps = await charger_snapshots(session, run_id, media_domaine)
            if not snaps:
                cible = f" pour {media_domaine}" if media_domaine else ""
                print(f"REJET : aucun snapshot pour le run {run_id!r}{cible}.")
                return 1
            out_dir = out_root / run_id / "snapshots"
            out_dir.mkdir(parents=True, exist_ok=True)
            existants: set[str] = set()
            ecrits: list[Path] = []
            for domaine, snap in snaps:
                nom = nom_fichier(domaine, snap.type_page, existants)
                chemin = out_dir / nom
                chemin.write_text(rendre_fichier(snap))
                ecrits.append(chemin)
            print(f"Snapshots exportés : {len(ecrits)} → {out_dir}")
            for chemin in ecrits:
                affiche = (
                    chemin.relative_to(_REPO_ROOT)
                    if chemin.is_relative_to(_REPO_ROOT)
                    else chemin
                )
                print(f"  → {affiche}")
            return 0
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True, help="ex. pilote-2026-07b")
    parser.add_argument(
        "--media", default=None, help="filtre optionnel par domaine (ex. cnews.fr)"
    )
    parser.add_argument(
        "--out-root",
        type=Path,
        default=DEFAULT_OUT_ROOT,
        help="racine des artefacts (défaut .context/media_eval)",
    )
    args = parser.parse_args()
    get_settings()  # lecture seule — DB courante
    sys.exit(asyncio.run(run(args.run_id, args.media, args.out_root)))


if __name__ == "__main__":
    main()
