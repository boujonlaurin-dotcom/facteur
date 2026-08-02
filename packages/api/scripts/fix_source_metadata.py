#!/usr/bin/env python3
"""Correction des métadonnées fausses du catalogue de sources (chantier B-1).

Contexte : `docs/bugs/bug-curation-essentiel-personnalisation.md` §B-1. Trois
familles d'erreurs, toutes écrites à la création de la source (titre RSS mal
parsé + `SourceService._guess_theme()` sur un flux dont le titre est en
anglais) :

  - **`language`** : des médias français taggés `'en'`. `is_foreign_source()`
    (`app/services/language_user_filter.py:42-50`) les traite alors comme
    étrangers et les masque pour les 51 utilisateurs à
    `hide_non_fr_sources = true`, sauf s'ils suivent la source.
  - **`theme`** : L'Équipe classée `culture` (donc invisible au mute `sport`),
    Libération-Politique en `custom`, Society (society.fr) en `tech`.
    `Source.theme` pilote le mute de thème (`digest_selector.py:888,970`) et
    les presets sereins (`recommendation/filter_presets.py:202,294`).
  - **`name`** : `Home Fil actu - actualités` est le fil brut 24/7 de BFMTV,
    entré avec le titre RSS de la page d'accueil. C'est la seule entrée BFMTV
    du catalogue et elle pèse 15,8 % des slots héros.

**Portée réelle, à ne pas surestimer** : le pool de clustering éditorial
(`editorial/candidate_pool.py:build_editorial_pool_stmt`) n'applique **aucun**
filtre langue. Ces corrections ne changent donc **pas** la composition du top-5
aujourd'hui. Elles sont un **prérequis** du chantier A (PR 5), qui rebranche le
pool personnalisé — lequel, lui, filtre sur la langue
(`digest_selector.py:1008-1009`).

Ce que ce script ne fait **pas**, volontairement :

  - **Il ne remplit pas les 206 `language IS NULL`.** `is_foreign_source(None)`
    vaut `False` : un NULL est déjà traité comme FR. Renseigner la colonne
    rendrait donc *nouvellement invisibles* les sources réellement étrangères
    pour les 51 utilisateurs concernés. C'est un changement de comportement
    produit, pas de l'hygiène — décision PO séparée.
  - **Il ne touche pas aux sources ambiguës.** La table ci-dessous est une liste
    explicite et relue, pas une heuristique : chaque ligne porte son URL comme
    preuve et un `expected_name` qui bloque l'écriture si la source a été
    renommée depuis l'audit.

Garde-fous (calqués sur `fix_basket_usa_theme.py` / `apply_source_reclassification.py`) :
  - **Dry-run par défaut** ; `--apply` gardé, `--allow-prod` requis hors DB de test.
  - **Idempotent** : re-run sans changement = no-op, code de sortie 0.
  - Audit non mutant : imprime les anomalies laissées de côté (NULL language,
    sources curées à 0 article/30 j).

Usage :
    cd packages/api
    python3 scripts/fix_source_metadata.py                        # dry-run + audit
    python3 scripts/fix_source_metadata.py --apply --allow-prod   # prod (gated PO)
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import func, select, update

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.content import Content
from app.models.source import Source
from scripts.cleanup_orphan_sources import _is_test_db

# Colonnes que ce script s'autorise à écrire. Toute autre clé dans une
# `Correction` est un bug de programmation, pas une donnée à appliquer.
MUTABLE_FIELDS: tuple[str, ...] = ("name", "language", "theme")


@dataclass(frozen=True)
class Correction:
    """Une correction relue à la main, avec sa preuve.

    `expected_name` est un garde-fou : si le nom en base ne correspond plus,
    la source a été renommée depuis l'audit et on refuse d'écrire à l'aveugle.
    """

    source_id: str
    expected_name: str
    evidence: str
    name: str | None = None
    language: str | None = None
    theme: str | None = None

    def desired(self) -> dict[str, str]:
        """Les champs à écrire, sans les `None` (= « ne pas toucher »)."""
        return {
            f: getattr(self, f)
            for f in MUTABLE_FIELDS
            if getattr(self, f, None) is not None
        }


# --------------------------------------------------------------------------
# Table des corrections. Relue le 2026-08-01 contre la prod (`DATABASE_URL_RO`).
# Chaque ligne : URL de la source comme preuve de la langue, volume 30 j pour
# situer l'enjeu. Seules les sources françaises **non ambiguës** y figurent.
# --------------------------------------------------------------------------
CORRECTIONS: tuple[Correction, ...] = (
    Correction(
        source_id="f88f4548-eca5-4c85-92c7-301d8434c701",
        expected_name="Home Fil actu - actualités",
        evidence="bfmtv.com/rss/news-24-7 — fil 24/7 de BFMTV, 4 803 art./30 j, "
        "nom = titre RSS de la home mal parsé ; seule entrée BFMTV du catalogue",
        name="BFMTV",
        language="fr",
    ),
    Correction(
        source_id="ae1e5e0f-dd3c-40e7-86dd-31cd14710002",
        expected_name="L'Équipe - L'actualité du sport en continu.",
        evidence="dwh.lequipe.fr — 3 065 art./30 j ; classée `culture`, donc "
        "invisible au mute `sport` alors que c'est un média 100 % sport",
        language="fr",
        theme="sport",
    ),
    Correction(
        source_id="df46726f-26ee-4469-9bf2-08245304cea5",
        expected_name="Libération - Politique",
        evidence="liberation.fr — 1 347 art./30 j ; `custom` alors que le flux "
        "est la rubrique Politique",
        language="fr",
        theme="politics",
    ),
    Correction(
        source_id="f07f88dc-ddc5-4dbe-b951-1bf90e89eb86",
        expected_name="CNEWS",
        evidence="cnews.fr — 1 318 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="b8e4dfb0-87e5-434e-b54c-a59c49ce2fdc",
        expected_name="The Conversation",
        evidence="theconversation.com/fr — édition française, 250 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="e6a87c97-22dc-470b-bec7-99aea5d610b5",
        expected_name="POLITIS",
        evidence="politis.fr — 71 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="460f4601-47a8-4e66-be60-e03c6dbb150d",
        expected_name="JeuxOnline.info",
        evidence="jeuxonline.info — 59 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="41497cf6-4b3d-4959-a7dd-33f501f867b4",
        expected_name="Le Point",
        evidence="lepoint.fr — 50 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="31af28bd-7d05-4c64-af96-9ee47fee6f5e",
        expected_name="Contexte - European Political News and Policy Insights",
        evidence="contexte.com — média français, 48 art./30 j ; le titre du flux "
        "est en anglais, d'où le mauvais tag",
        language="fr",
    ),
    Correction(
        source_id="2cb53520-5701-4ffa-8379-24657e615405",
        expected_name="RSS Reggae.fr - les news",
        evidence="reggae.fr — 32 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="ec765de2-835c-4e57-a192-19d6e0b18d75",
        expected_name="FrenchWeb",
        evidence="frenchweb.fr — 29 art./30 j",
        language="fr",
    ),
    Correction(
        source_id="26b05d76-4fda-45d2-b5ec-4548c8c77650",
        expected_name="Society",
        evidence="society.fr — 22 art./30 j ; magazine société classé `tech`",
        language="fr",
        theme="society",
    ),
    Correction(
        source_id="188eb0f7-031a-4e78-96f0-b77f035a6f42",
        expected_name="HugoDécrypte - Grands formats",
        evidence="chaîne YouTube française, 20 art./30 j",
        language="fr",
    ),
)


@dataclass
class Write:
    source_id: str
    name: str
    changes: dict[str, tuple[str | None, str]]  # champ -> (avant, après)


@dataclass
class Plan:
    writes: list[Write] = field(default_factory=list)
    noop: list[str] = field(default_factory=list)  # déjà à la bonne valeur
    missing: list[str] = field(default_factory=list)  # id absent de la base
    renamed: list[str] = field(default_factory=list)  # expected_name ne colle plus


def compute_changes(
    corrections: tuple[Correction, ...] | list[Correction],
    current: dict[str, dict[str, str | None]],
) -> Plan:
    """Diff pur entre la table de corrections et l'état lu en base.

    `current` : source_id (str) -> {"name", "language", "theme"}.
    Aucune I/O : c'est la fonction couverte par les tests.
    """
    plan = Plan()
    for corr in corrections:
        row = current.get(corr.source_id)
        if row is None:
            plan.missing.append(f"{corr.expected_name} ({corr.source_id})")
            continue
        # Le nom en base doit être celui de l'audit — ou déjà celui qu'on veut
        # écrire, sinon le renommage rendrait le script non rejouable.
        if row.get("name") not in {corr.expected_name, corr.name or corr.expected_name}:
            plan.renamed.append(
                f"{corr.source_id} : attendu « {corr.expected_name} », "
                f"trouvé « {row.get('name')} »"
            )
            continue

        changes = {
            fld: (row.get(fld), value)
            for fld, value in corr.desired().items()
            if row.get(fld) != value
        }
        if not changes:
            plan.noop.append(corr.expected_name)
            continue
        plan.writes.append(
            Write(source_id=corr.source_id, name=corr.expected_name, changes=changes)
        )
    return plan


async def _load_current(session) -> dict[str, dict[str, str | None]]:
    ids = [UUID(c.source_id) for c in CORRECTIONS]
    result = await session.execute(
        select(Source.id, Source.name, Source.language, Source.theme).where(
            Source.id.in_(ids)
        )
    )
    return {
        str(r.id): {"name": r.name, "language": r.language, "theme": r.theme}
        for r in result
    }


async def _audit(session) -> None:
    """Anomalies volontairement **non** corrigées ici — à arbitrer séparément."""
    null_lang = await session.scalar(
        select(func.count())
        .select_from(Source)
        .where(Source.is_active.is_(True), Source.language.is_(None))
    )
    active = await session.scalar(
        select(func.count()).select_from(Source).where(Source.is_active.is_(True))
    )
    print("-" * 78)
    print("AUDIT (non muté — décisions séparées) :")
    print(
        f"  • language IS NULL : {null_lang}/{active} sources actives. "
        "NON rempli par ce script : `is_foreign_source(None)` vaut False, donc "
        "un NULL est déjà traité comme FR. Renseigner la colonne masquerait "
        "nouvellement les sources étrangères pour les users à "
        "`hide_non_fr_sources = true`."
    )

    cutoff = datetime.now(UTC) - timedelta(days=30)
    dead = await session.execute(
        select(Source.name, Source.id)
        .outerjoin(
            Content,
            (Content.source_id == Source.id) & (Content.published_at >= cutoff),
        )
        .where(Source.is_active.is_(True), Source.is_curated.is_(True))
        .group_by(Source.id, Source.name)
        .having(func.count(Content.id) == 0)
        .order_by(Source.name)
    )
    rows = list(dead)
    print(f"  • {len(rows)} source(s) curée(s) et active(s) à 0 article/30 j :")
    for r in rows[:20]:
        print(f"      - {r.name} ({r.id})")
    if len(rows) > 20:
        print(f"      … et {len(rows) - 20} autres")
    print("-" * 78)


def _render(plan: Plan) -> None:
    print(f"\n{len(plan.writes)} source(s) à corriger :")
    for w in plan.writes:
        print(f"  • {w.name} ({w.source_id})")
        for fld, (before, after) in sorted(w.changes.items()):
            print(f"      {fld} : {before!r} -> {after!r}")
    if plan.noop:
        print(f"\n{len(plan.noop)} déjà à jour (no-op) : {', '.join(plan.noop)}")
    if plan.renamed:
        print(f"\n{len(plan.renamed)} IGNORÉE(S) — renommée(s) depuis l'audit :")
        for line in plan.renamed:
            print(f"  ! {line}")
    if plan.missing:
        print(f"\n{len(plan.missing)} INTROUVABLE(S) en base :")
        for line in plan.missing:
            print(f"  ! {line}")


async def run(apply: bool, allow_prod: bool) -> int:
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
            current = await _load_current(session)
            plan = compute_changes(CORRECTIONS, current)
            _render(plan)
            await _audit(session)

            if plan.missing or plan.renamed:
                print(
                    "\nABORT : la table de corrections ne colle plus à la base "
                    "(source introuvable ou renommée). Relire avant d'appliquer."
                )
                return 2
            if not plan.writes:
                print("\n(no-op — toutes les corrections sont déjà en base.)")
                return 0
            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            for w in plan.writes:
                await session.execute(
                    update(Source)
                    .where(Source.id == UUID(w.source_id))
                    .values(**{f: after for f, (_, after) in w.changes.items()})
                )
            await session.commit()
            print(f"\nAPPLIQUÉ : {len(plan.writes)} source(s) corrigée(s).")
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
        "--allow-prod", action="store_true", help="autorise --apply hors DB de test"
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(run(apply=args.apply, allow_prod=args.allow_prod)))


if __name__ == "__main__":
    main()
