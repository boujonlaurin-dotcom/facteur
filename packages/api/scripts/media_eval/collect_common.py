#!/usr/bin/env python3
"""Module commun des collecteurs voie A (code déterministe → DB directe).

La voie A écrit des signaux ``voie=CODE`` (détection / registres publics) sans
LLM. La voie B (agents) qualifie la *substance* et passe par
``ingest_artifacts.py``. Les deux voies peuvent produire le même quadruplet
(critère|type|statut|ancre) sans se supprimer : la clé de dédupe voie A est
**préfixée ``code|``** (D2) alors que la voie B ne l'est pas — même quadruplet
⇒ deux clés ⇒ deux lignes conservées.

Ce module fournit :
- ``FetchResult`` + ``fetch_http`` : récupération HTTP robuste (httpx puis repli
  ``curl_cffi`` sur anti-bot), qui **ne lève jamais** — un échec devient un
  ``FetchResult`` bloqué (« jamais d'échec silencieux ») ;
- ``require_run`` : lève si le run n'existe pas (sa ``date_reference`` pilote la
  fraîcheur, cf. ``create_run.py``) ;
- ``Collecteur`` : contexte d'écriture (snapshots + signaux) avec dédupe
  applicative et validation Pydantic avant insertion ;
- ``run_cli`` : harnais argparse commun aux 6 collecteurs (dry-run/--apply).

Un ``fetcher`` est injectable : en test on lit des fixtures HTML/JSON figées,
zéro réseau.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import sys
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import httpx
from pydantic import ValidationError
from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    MediaEvalMedia,
    MediaEvalRun,
    MediaEvalSignal,
    MediaEvalSnapshot,
    ModeAcces,
    StatutSignal,
    TypePage,
    VoieCollecte,
)
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.ingest_artifacts import IngestError, resoudre_media
from scripts.media_eval.schemas import SignalArtifact

# UA dédié : identifiable, honnête (pas de spoof d'un vrai navigateur en httpx —
# le repli curl_cffi impersonate chrome n'est utilisé que sur anti-bot avéré).
USER_AGENT = "FacteurMediaEval/1.0 (+https://facteur.app; evaluation open data)"
_ANTIBOT_STATUS: frozenset[int] = frozenset({401, 403, 429, 503})
_TIMEOUT = 20.0
_RETRIES = 2


class CollecteError(Exception):
    """Erreur bloquante d'un collecteur (run/média absent, incohérence dure)."""


# --------------------------------------------------------------------------- #
# Récupération HTTP — ne lève jamais.
# --------------------------------------------------------------------------- #
@dataclass
class FetchResult:
    url: str
    status: int | None
    text: str
    mode_acces: ModeAcces
    erreur: str | None = None

    @property
    def ok(self) -> bool:
        """Réponse exploitable (200, contenu récupéré)."""
        return self.status == 200 and self.erreur is None

    @property
    def bloque(self) -> bool:
        """Accès refusé (anti-bot, réseau) — ≠ page absente (404)."""
        return self.mode_acces == ModeAcces.BLOQUE


# Un fetcher : URL -> FetchResult (injectable en test).
Fetcher = Callable[[str], Awaitable[FetchResult]]


def _result_httpx(url: str, resp: httpx.Response) -> FetchResult:
    if resp.status_code == 200:
        return FetchResult(url, 200, resp.text, ModeAcces.LIBRE)
    mode = ModeAcces.BLOQUE if resp.status_code in _ANTIBOT_STATUS else ModeAcces.LIBRE
    return FetchResult(
        url, resp.status_code, resp.text, mode, f"HTTP {resp.status_code}"
    )


def _curl_get(url: str, timeout: float) -> tuple[int, str]:
    from curl_cffi import requests as curl_requests

    resp = curl_requests.get(
        url, impersonate="chrome", timeout=timeout, allow_redirects=True
    )
    return resp.status_code, resp.text


async def _fetch_curl(url: str, timeout: float) -> FetchResult:
    """Repli anti-bot (curl_cffi sync exécuté hors event-loop)."""
    try:
        status, text = await asyncio.to_thread(_curl_get, url, timeout)
    except Exception as exc:  # réseau / TLS / curl : jamais de raise
        return FetchResult(url, None, "", ModeAcces.BLOQUE, f"curl_cffi: {exc}")
    if status == 200:
        return FetchResult(url, 200, text, ModeAcces.LIBRE)
    mode = ModeAcces.BLOQUE if status in _ANTIBOT_STATUS else ModeAcces.LIBRE
    return FetchResult(url, status, text, mode, f"HTTP {status}")


async def fetch_http(url: str, *, timeout: float = _TIMEOUT) -> FetchResult:
    """GET robuste — httpx (2 retries) puis repli curl_cffi sur anti-bot.

    Ne lève jamais : toute exception ou statut anti-bot persistant devient un
    ``FetchResult`` bloqué (le collecteur émettra un signal ``bloque_acces``).
    """
    derniere_exc: str | None = None
    for tentative in range(_RETRIES + 1):
        try:
            async with httpx.AsyncClient(
                follow_redirects=True,
                timeout=timeout,
                headers={"User-Agent": USER_AGENT},
            ) as client:
                resp = await client.get(url)
            if resp.status_code in _ANTIBOT_STATUS:
                break  # anti-bot → repli curl_cffi
            return _result_httpx(url, resp)
        except httpx.HTTPError as exc:
            derniere_exc = str(exc)
            if tentative == _RETRIES:
                break
    curl = await _fetch_curl(url, timeout)
    if curl.erreur is None or derniere_exc is None:
        return curl
    return FetchResult(url, curl.status, curl.text, curl.mode_acces, curl.erreur)


# --------------------------------------------------------------------------- #
# Résolution du run — jamais implicite.
# --------------------------------------------------------------------------- #
async def require_run(session, run_id: str) -> MediaEvalRun:
    """Retourne le run ou **lève** (sa date_reference pilote la fraîcheur).

    Pas de ``ensure_run()`` : la création d'un run est un acte délibéré et
    audité (``create_run.py``).
    """
    run = (
        await session.execute(select(MediaEvalRun).where(MediaEvalRun.run_id == run_id))
    ).scalar_one_or_none()
    if run is None:
        raise CollecteError(
            f"run inconnu : {run_id!r} — le créer d'abord "
            "(scripts/media_eval/create_run.py)."
        )
    return run


# --------------------------------------------------------------------------- #
# Dédupe voie A (D2) — préfixe `code|` pour cohabiter avec la voie B.
# --------------------------------------------------------------------------- #
def dedupe_key_signal_code(item: SignalArtifact) -> str:
    """sha256 canonique préfixé ``code|`` (distinct de la clé voie B).

    Même quadruplet (critère|type|statut|ancre) qu'un signal agent ⇒ clé
    différente ⇒ les deux lignes coexistent (détection code vs substance agent).
    """
    ancre = item.source_urls[0] if item.source_urls else (item.citation or "")
    brut = f"code|{item.critere}|{item.type_signal}|{item.statut}|{ancre}"
    return hashlib.sha256(brut.encode()).hexdigest()


# --------------------------------------------------------------------------- #
# Contexte d'écriture d'un collecteur.
# --------------------------------------------------------------------------- #
@dataclass
class CollectStats:
    inseres: int = 0
    doublons: int = 0
    snapshots: int = 0
    bloques: int = 0
    details: list[str] = field(default_factory=list)


def _hash_contenu(contenu: str | None) -> str:
    return hashlib.sha256((contenu or "").encode()).hexdigest()


class Collecteur:
    """Écrit snapshots + signaux voie A avec dédupe applicative et validation.

    Précharge les clés de dédupe et snapshots existants (idempotence
    cross-run). Toute écriture de signal passe par ``SignalArtifact`` (PR 1) —
    un signal incohérent lève ``CollecteError`` avant insertion.
    """

    def __init__(
        self, session, media: MediaEvalMedia, run: MediaEvalRun, collecteur: str
    ) -> None:
        self.session = session
        self.media = media
        self.run = run
        self.collecteur = collecteur
        self.stats = CollectStats()
        self._deja: set[str] = set()
        self._snaps: dict[tuple, MediaEvalSnapshot] = {}

    async def _preload(self) -> None:
        rows = await self.session.execute(
            select(MediaEvalSignal.dedupe_key).where(
                MediaEvalSignal.media_id == self.media.id,
                MediaEvalSignal.run_id == self.run.run_id,
            )
        )
        self._deja = {r[0] for r in rows}
        snaps = await self.session.execute(
            select(MediaEvalSnapshot).where(
                MediaEvalSnapshot.media_id == self.media.id,
                MediaEvalSnapshot.run_id == self.run.run_id,
            )
        )
        self._snaps = {(s.url, s.hash): s for s in snaps.scalars()}

    async def snapshot(
        self,
        *,
        url: str,
        type_page: TypePage,
        contenu: str | None,
        http_status: int | None = None,
        mode_acces: ModeAcces = ModeAcces.LIBRE,
    ) -> MediaEvalSnapshot:
        """Capture horodatée, dédupée par (url, hash) — jamais d'unique DB."""
        h = _hash_contenu(contenu)
        existant = self._snaps.get((url, h))
        if existant is not None:
            return existant
        snap = MediaEvalSnapshot(
            media_id=self.media.id,
            run_id=self.run.run_id,
            url=url,
            type_page=type_page,
            contenu=contenu,
            hash=h,
            http_status=http_status,
            mode_acces=mode_acces,
        )
        self.session.add(snap)
        await self.session.flush()  # snap.id requis pour lier un signal
        self._snaps[(url, h)] = snap
        self.stats.snapshots += 1
        return snap

    async def signal(
        self,
        *,
        critere: str,
        type_signal: str,
        statut: str | StatutSignal,
        valeur: dict | None = None,
        citation: str | None = None,
        source_urls: list[str] | None = None,
        sources_consultees: list[str] | None = None,
        snapshot_id=None,
    ) -> MediaEvalSignal | None:
        """Valide (SignalArtifact) puis insère un signal voie CODE.

        Retourne le signal inséré, ou ``None`` si c'est un doublon (dédupe).
        """
        statut_str = statut.value if hasattr(statut, "value") else str(statut)
        try:
            artifact = SignalArtifact(
                media_domaine=self.media.domaine,
                critere=critere,
                type_signal=type_signal,
                statut=statut_str,
                valeur=valeur,
                citation=citation,
                source_urls=list(source_urls or []),
                sources_consultees=list(sources_consultees or []),
            )
        except ValidationError as exc:
            raise CollecteError(
                f"signal invalide {critere}/{type_signal} ({statut_str}) : {exc}"
            ) from exc
        key = dedupe_key_signal_code(artifact)
        if key in self._deja:
            self.stats.doublons += 1
            return None
        self._deja.add(key)
        signal = MediaEvalSignal(
            media_id=self.media.id,
            critere=critere,
            type_signal=type_signal,
            statut=StatutSignal(statut_str),
            valeur=valeur,
            citation=citation,
            voie=VoieCollecte.CODE,
            collecteur=self.collecteur,
            source_urls=list(source_urls or []),
            sources_consultees=list(sources_consultees) if sources_consultees else None,
            snapshot_id=snapshot_id,
            run_id=self.run.run_id,
            dedupe_key=key,
        )
        self.session.add(signal)
        self.stats.inseres += 1
        self.stats.details.append(f"{critere}/{type_signal} ({statut_str})")
        return signal

    async def bloque(
        self,
        *,
        critere: str,
        type_signal: str,
        url: str | None,
        raison: str,
        sources_consultees: list[str] | None = None,
    ) -> MediaEvalSignal | None:
        """Signal ``bloque_acces`` — « jamais d'échec silencieux »."""
        signal = await self.signal(
            critere=critere,
            type_signal=type_signal,
            statut=StatutSignal.BLOQUE_ACCES,
            valeur={"raison": raison, "url": url} if url else {"raison": raison},
            citation=raison,
            source_urls=[url] if url else [],
            sources_consultees=sources_consultees,
        )
        if signal is not None:
            self.stats.bloques += 1
        return signal


async def ouvrir_collecteur(
    session, media: MediaEvalMedia, run: MediaEvalRun, collecteur: str
) -> Collecteur:
    """Construit un ``Collecteur`` avec dédupe/snapshots préchargés."""
    c = Collecteur(session, media, run, collecteur)
    await c._preload()
    return c


# --------------------------------------------------------------------------- #
# Harnais CLI commun (dry-run par défaut, --apply gardé).
# --------------------------------------------------------------------------- #
CollecterFn = Callable[..., Awaitable[CollectStats]]


async def _run(
    nom: str,
    collecter_fn: CollecterFn,
    *,
    media_domaine: str,
    run_id: str,
    apply: bool,
    allow_prod: bool,
) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"[{nom}] DB cible : "
        f"{db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    async with async_session_maker() as session:
        try:
            run = await require_run(session, run_id)
            media = await resoudre_media(session, media_domaine)
            stats = await collecter_fn(session, media, run, fetch_http)
            for ligne in stats.details:
                print(f"  + {ligne}")
            print(
                f"[{nom}] {media.domaine} · run {run_id} — "
                f"à insérer : {stats.inseres} (dont bloqués : {stats.bloques}) | "
                f"snapshots : {stats.snapshots} | doublons : {stats.doublons}"
            )
            if not apply:
                await session.rollback()
                print("(dry-run — aucune mutation. Relance avec --apply.)")
                return 0
            await session.commit()
            print(
                f"[{nom}] APPLIQUÉ : {stats.inseres} signaux, {stats.snapshots} snapshots."
            )
            return 0
        except (CollecteError, IngestError) as exc:
            await session.rollback()
            print(f"REJET : {exc} — rien n'a été écrit.")
            return 1
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def run_cli(nom: str, collecter_fn: CollecterFn) -> None:
    """Point d'entrée ``main()`` commun aux 6 collecteurs voie A."""
    parser = argparse.ArgumentParser(description=f"Collecteur voie A : {nom}")
    parser.add_argument("--media", required=True, help="domaine (ex. cnews.fr)")
    parser.add_argument("--run-id", required=True, help="ex. pilote-2026-07")
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(
            _run(
                nom,
                collecter_fn,
                media_domaine=args.media,
                run_id=args.run_id,
                apply=args.apply,
                allow_prod=args.allow_prod,
            )
        )
    )
