#!/usr/bin/env python3
"""Ingestion des artefacts des agents collecteurs (voie B) — SANS LLM.

Les agents n'écrivent jamais en DB : ils déposent des JSON dans
``.context/media_eval/<run_id>/``. Ce script valide (Pydantic,
`scripts/media_eval/schemas.py`) puis insère :

- ``SignalBatchArtifact`` → lignes `media_eval_signaux` ;
- ``DebunkageBatchArtifact`` → couples signal C1 + `media_eval_debunkages`
  (``poids_emetteur`` dérivé par code, jamais par l'agent).

Idempotent par ``dedupe_key`` (sha256 canonique calculé ici) : ré-ingérer le
même artefact ne crée rien. Un artefact invalide est rejeté en bloc (exit
non-zéro, rien d'écrit). **Dry-run par défaut**, ``--apply`` gardé.

Usage :
    cd packages/api
    python3 scripts/media_eval/ingest_artifacts.py --artifact <fichier.json>
    python3 scripts/media_eval/ingest_artifacts.py --artifact <dossier/> --apply
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    MediaEvalDebunkage,
    MediaEvalMedia,
    MediaEvalSignal,
    StatutSignal,
    VoieCollecte,
)
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.schemas import (
    TYPE_SIGNAUX,
    DebunkageArtifact,
    DebunkageBatchArtifact,
    SignalArtifact,
    SignalBatchArtifact,
)

# Couverture attendue de la voie B gouvernance : le silence est interdit, chaque
# type de signal doit être adressé (present/partiel/absent_verifie/bloque_acces).
CRITERES_GOUVERNANCE: tuple[str, ...] = ("C5", "C7", "C8", "C9", "C11")


class IngestError(Exception):
    """Artefact invalide — rien ne doit être écrit."""


@dataclass
class IngestResult:
    inseres: int = 0
    doublons: int = 0
    details: list[str] = field(default_factory=list)


def charger_artifact(path: Path) -> SignalBatchArtifact | DebunkageBatchArtifact:
    """Valide un fichier artefact (type inféré du contenu des items)."""
    data = json.loads(path.read_text())
    items = data.get("items") or []
    if items and "url_debunkage" in items[0]:
        return DebunkageBatchArtifact.model_validate(data)
    return SignalBatchArtifact.model_validate(data)


def dedupe_key_signal(item: SignalArtifact) -> str:
    ancre = item.source_urls[0] if item.source_urls else (item.citation or "")
    brut = f"{item.critere}|{item.type_signal}|{item.statut}|{ancre}"
    return hashlib.sha256(brut.encode()).hexdigest()


def voie_depuis_agent(agent: str) -> VoieCollecte:
    """Voie dérivée du préfixe (D6) : ``humain:`` → HUMAIN, sinon AGENT.

    Ouvre la voie C (artefact manuel ``agent: "humain:laurin"``) sans nouveau
    script — un repli quand une source open data est inaccessible.
    """
    return VoieCollecte.HUMAIN if agent.startswith("humain:") else VoieCollecte.AGENT


def dedupe_key_debunkage(item: DebunkageArtifact) -> str:
    brut = f"C1|{item.type_signal}|{item.url_debunkage}|{item.publie_at.isoformat()}"
    return hashlib.sha256(brut.encode()).hexdigest()


async def resoudre_media(session, domaine: str) -> MediaEvalMedia:
    media = (
        await session.execute(
            select(MediaEvalMedia).where(MediaEvalMedia.domaine == domaine)
        )
    ).scalar_one_or_none()
    if media is None:
        raise IngestError(
            f"média inconnu : {domaine!r} (lancer seed_medias.py d'abord)"
        )
    return media


async def _dedupe_existants(session, media_id: UUID, run_id: str) -> set[str]:
    rows = await session.execute(
        select(MediaEvalSignal.dedupe_key).where(
            MediaEvalSignal.media_id == media_id,
            MediaEvalSignal.run_id == run_id,
        )
    )
    return {r[0] for r in rows}


async def inserer_signaux(session, batch: SignalBatchArtifact) -> IngestResult:
    """Insère les signaux d'un batch — sans commit (l'appelant décide)."""
    result = IngestResult()
    deja_vus: dict[UUID, set[str]] = {}
    for item in batch.items:
        media = await resoudre_media(session, item.media_domaine)
        if media.id not in deja_vus:
            deja_vus[media.id] = await _dedupe_existants(
                session, media.id, batch.run_id
            )
        key = dedupe_key_signal(item)
        if key in deja_vus[media.id]:
            result.doublons += 1
            continue
        deja_vus[media.id].add(key)
        session.add(
            MediaEvalSignal(
                media_id=media.id,
                critere=item.critere,
                type_signal=item.type_signal,
                statut=StatutSignal(item.statut),
                valeur=item.valeur,
                citation=item.citation,
                voie=voie_depuis_agent(batch.agent),
                collecteur=batch.agent,
                source_urls=item.source_urls,
                sources_consultees=item.sources_consultees or None,
                run_id=batch.run_id,
                dedupe_key=key,
                collecte_at=batch.genere_at,
                version_prompt_collecteur=batch.version_prompt,
            )
        )
        result.inseres += 1
        result.details.append(
            f"signal {item.critere}/{item.type_signal} ({item.statut})"
        )
    return result


async def inserer_debunkages(session, batch: DebunkageBatchArtifact) -> IngestResult:
    """Insère les couples signal C1 + débunkage — sans commit."""
    result = IngestResult()
    deja_vus: dict[UUID, set[str]] = {}
    for item in batch.items:
        media = await resoudre_media(session, item.media_domaine)
        if media.id not in deja_vus:
            deja_vus[media.id] = await _dedupe_existants(
                session, media.id, batch.run_id
            )
        key = dedupe_key_debunkage(item)
        if key in deja_vus[media.id]:
            result.doublons += 1
            continue
        deja_vus[media.id].add(key)
        poids = item.poids_emetteur()  # dérivé par code, jamais par l'agent
        signal = MediaEvalSignal(
            media_id=media.id,
            critere="C1",
            type_signal=item.type_signal,
            statut=StatutSignal.PRESENT,
            valeur={
                "url": item.url_debunkage,
                "emetteur": item.emetteur,
                "poids_emetteur": poids,
                "gravite": item.gravite,
                "suite_donnee": item.suite_donnee,
                "publie_at": item.publie_at.isoformat(),
                "resume": item.resume,
                # Dédup par affaire (§5.2.1) : lue par build_eval_input pour le
                # comptage fallback C1 et par l'évaluateur. Repli sur l'URL si
                # l'agent n'a pas qualifié l'affaire (1 débunkage = 1 litige).
                "cle_affaire": item.cle_affaire or item.url_debunkage,
            },
            citation=item.citation or item.resume,
            voie=voie_depuis_agent(batch.agent),
            collecteur=batch.agent,
            source_urls=item.source_urls,
            sources_consultees=item.sources_consultees or None,
            run_id=batch.run_id,
            dedupe_key=key,
            collecte_at=batch.genere_at,
            version_prompt_collecteur=batch.version_prompt,
        )
        session.add(signal)
        await session.flush()  # signal.id requis pour le couple
        session.add(
            MediaEvalDebunkage(
                media_id=media.id,
                signal_id=signal.id,
                url_debunkage=item.url_debunkage,
                emetteur=item.emetteur,
                poids_emetteur=poids,
                gravite=item.gravite,
                suite_donnee=item.suite_donnee,
                resume=item.resume,
                publie_at=item.publie_at,
            )
        )
        result.inseres += 1
        result.details.append(
            f"debunkage {item.emetteur} ({item.gravite}, poids={poids})"
        )
    return result


async def ingester(session, paths: list[Path]) -> IngestResult:
    """Valide TOUS les artefacts avant d'insérer quoi que ce soit."""
    batches = [charger_artifact(p) for p in paths]  # lève avant toute écriture
    total = IngestResult()
    for batch in batches:
        if isinstance(batch, DebunkageBatchArtifact):
            partiel = await inserer_debunkages(session, batch)
        else:
            partiel = await inserer_signaux(session, batch)
        total.inseres += partiel.inseres
        total.doublons += partiel.doublons
        total.details.extend(partiel.details)
    return total


async def rapport_couverture(session, batches: list) -> list[str]:
    """Types de signaux gouvernance sans aucun signal pour (média, run).

    Contrôle d'observabilité (anti-passivité) : la voie B doit adresser chaque
    ``type_signal`` du registre gouvernance ; un type absent est signalé en
    WARNING (non bloquant). Lu sur l'état de session courant (voie A + voie B),
    donc valable en dry-run comme en ``--apply``.
    """
    cibles = {
        (item.media_domaine, batch.run_id) for batch in batches for item in batch.items
    }
    manquants: list[str] = []
    for domaine, run_id in sorted(cibles):
        media = await resoudre_media(session, domaine)
        rows = await session.execute(
            select(MediaEvalSignal.critere, MediaEvalSignal.type_signal).where(
                MediaEvalSignal.media_id == media.id,
                MediaEvalSignal.run_id == run_id,
            )
        )
        presents = {(c, t) for c, t in rows.all()}
        for critere in CRITERES_GOUVERNANCE:
            for type_signal in TYPE_SIGNAUX[critere]:
                if (critere, type_signal) not in presents:
                    manquants.append(f"{domaine} · {critere}/{type_signal}")
    return manquants


def _collecter_paths(artifact: Path) -> list[Path]:
    if artifact.is_dir():
        paths = sorted(
            p
            for p in artifact.glob("*.json")
            if p.name.startswith(("signaux", "debunkages"))
        )
        if not paths:
            raise IngestError(f"aucun artefact signaux_*/debunkages_* dans {artifact}")
        return paths
    return [artifact]


async def run(artifact: Path, apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    try:
        paths = _collecter_paths(artifact)
    except IngestError as exc:
        print(f"REJET : {exc}")
        return 1

    async with async_session_maker() as session:
        try:
            result = await ingester(session, paths)
            for ligne in result.details:
                print(f"  + {ligne}")
            print(
                f"Artefacts : {len(paths)} | à insérer : {result.inseres} | "
                f"doublons ignorés : {result.doublons}"
            )
            manquants = await rapport_couverture(
                session, [charger_artifact(p) for p in paths]
            )
            if manquants:
                print(
                    f"\n⚠ COUVERTURE : {len(manquants)} type(s) de signal "
                    "gouvernance sans aucun signal (voie A + B) — le silence est "
                    "interdit, chaque type doit être adressé :"
                )
                for ligne in manquants:
                    print(f"    - {ligne}")
            if not apply:
                await session.rollback()
                print("(dry-run — aucune mutation. Relance avec --apply.)")
                return 0
            await session.commit()
            print(f"APPLIQUÉ : {result.inseres} lignes insérées.")
            return 0
        except IngestError as exc:
            await session.rollback()
            print(f"REJET : {exc} — rien n'a été écrit.")
            return 1
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifact",
        type=Path,
        required=True,
        help="fichier artefact JSON ou dossier (signaux_*.json / debunkages_*.json)",
    )
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(run(args.artifact, apply=args.apply, allow_prod=args.allow_prod))
    )


if __name__ == "__main__":
    main()
