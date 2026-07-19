#!/usr/bin/env python3
"""Re-mapping one-shot du gold batch 1 (v1.2) vers la grille v1.3 — FICHIERS SEULS.

Aucun accès DB : lit ``docs/media-eval/golden/gold_v0.json`` (notation Laurin,
numérotation v1.2) et applique la correspondance **Annexe B** de
``methodologie-v1.3.md`` pour produire ``gold_v1_3.json`` (v1.3). ``gold_v0.json``
reste figé (historique batch 1).

Principe : **les déterminations restent valides** (les faits n'ont pas changé) ;
seuls numéros, poids et échelles changent. Quand l'ancien score n'existe plus sur
la nouvelle échelle (continue → niveaux), l'entrée passe en ``revue_requise`` avec
les niveaux candidats — Laurin tranche ces cas ligne à ligne (STOP validation).

Correspondance (Annexe B) :
- C1 → C1  (véracité ; N/A conservé)
- C5 → C6  (transparence propriété ; continue 0-10 → 5 niveaux 0/1/4/7/10)
- C7 → C8  (séparation pub ; continue 0-4 → 4 niveaux 0/1/3/4)
- C9 → C10 (indépendance ; 3 niveaux 0/5/10 → identique, niveau conservé)
- C8 + C11 → C9 (**fusion** engagement + positionnement ; → 3 niveaux 0/5/10)

Usage :
    cd packages/api
    python3 scripts/media_eval/remap_v12_v13.py            # écrit gold_v1_3.json
    python3 scripts/media_eval/remap_v12_v13.py --dry-run  # affiche sans écrire
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.media_eval.schemas import GoldenSet, grille

_REPO_ROOT = Path(__file__).resolve().parents[4]
GOLD_DIR = _REPO_ROOT / "docs" / "media-eval" / "golden"
GOLD_V0 = GOLD_DIR / "gold_v0.json"
GOLD_V13 = GOLD_DIR / "gold_v1_3.json"
DEFAULT_REPORT = (
    _REPO_ROOT / ".context" / "media_eval" / "pilote-2026-07b" / "remap_v12_v13.json"
)

# Renumérotation simple (1 critère v1.2 → 1 critère v1.3).
RENUMEROTATION: dict[str, str] = {"C1": "C1", "C5": "C6", "C7": "C8", "C9": "C10"}
# Fusion : deux critères v1.2 → un critère v1.3.
FUSION_SOURCES: tuple[str, ...] = ("C8", "C11")
FUSION_CIBLE = "C9"
# Ordre d'affichage des critères v1.3 dans le gold remappé (vague 1).
ORDRE_V13: tuple[str, ...] = ("C1", "C6", "C8", "C9", "C10")

# Décisions PO (Laurin) sur les entrées ``revue_requise`` du batch 1 — STOP
# validation n°2 (2026-07-18). Chaque décision fige le **niveau** retenu (barème
# v1.3) ; le score est dérivé de la grille. La notation v1.3 est *continue guidée
# par les niveaux* : une décision peut fournir un ``score`` continu entre deux
# paliers (clé optionnelle) en cas d'hésitation — ici les trois cas tombent
# proprement sur un palier. Les candidats_* et l'origine_v12 restent tracés.
DECISIONS_PO: dict[tuple[str, str], dict] = {
    ("cnews.fr", "C6"): {
        "niveau": 2,
        "motif": (
            "Financement non décrit + chaîne capitalistique jusqu'à Bolloré non "
            "divulguée sur le site → échoue « revenus décrits + actionnariat » du "
            "niveau 3 ; mentions légales complètes + groupe identifiable = niveau 2."
        ),
    },
    ("cnews.fr", "C8"): {
        "niveau": 2,
        "motif": (
            "Marquage « Contenus sponsorisés » attesté + régie identifiable "
            "(Canal+ Brand Solutions), sans politique publicitaire publiée. "
            "Garde-fou C8 : l'absence de politique publiée ne peut à elle seule "
            "faire descendre sous le niveau 2 ; aucun label discret/irrégulier ni "
            "native advertising observé → niveau 2."
        ),
    },
    ("cnews.fr", "C9"): {
        "niveau": 0,
        "motif": (
            "Ligne jamais auto-explicitée (ex-C11) ET aucun engagement formalisé "
            "public — charte loi-Bloche attestée mais non publiée, jugée non "
            "contraignante (ex-C8 négatifs) → Absent, niveau 0."
        ),
    },
}

_INTITULES_V12 = {
    "C1": "véracité et exactitude",
    "C5": "transparence propriété / financement",
    "C7": "séparation contenu / publicité",
    "C8": "engagement déontologique",
    "C9": "indépendance éditoriale",
    "C11": "transparence du positionnement",
}


def _bracket_niveaux(
    score: float, niveau_scores: dict[int, int]
) -> tuple[str, list[int]]:
    """Niveau(x) v1.3 correspondant à un score continu v1.2.

    Retourne ("exact", [niveau]) si le score tombe sur un palier, sinon
    ("revue", [niveau_bas, niveau_haut]) — les deux paliers qui l'encadrent.
    """
    exact = [n for n, s in niveau_scores.items() if s == score]
    if exact:
        return "exact", sorted(exact)
    bas = [n for n, s in niveau_scores.items() if s < score]
    haut = [n for n, s in niveau_scores.items() if s > score]
    cands: list[int] = []
    if bas:
        cands.append(max(bas, key=lambda n: niveau_scores[n]))
    if haut:
        cands.append(min(haut, key=lambda n: niveau_scores[n]))
    return "revue", sorted(cands)


def _origine(entry: dict) -> dict:
    """Extrait la trace v1.2 d'une entrée source (provenance)."""
    return {
        "critere": entry["critere"],
        "statut": entry["statut"],
        "score": entry.get("score"),
        "niveau": entry.get("niveau"),
        "commentaire": entry.get("commentaire"),
    }


def _commentaire_v12(entry: dict) -> str:
    c = _INTITULES_V12.get(entry["critere"], entry["critere"])
    return f"[v1.2 {entry['critere']} — {c}] {entry.get('commentaire') or ''}".strip()


def remap_simple(entry: dict, cible: str) -> dict:
    """Renumérote une entrée v1.2 vers son critère v1.3 (hors fusion)."""
    g13 = grille("v1.3")
    base = {
        "media_domaine": entry["media_domaine"],
        "critere": cible,
        "version_methodo": "v1.3",
        "score": None,
        "niveau": None,
        "origine_v12": [_origine(entry)],
    }
    statut = entry["statut"]

    if statut in ("non_applicable", "a_noter"):
        # N/A et « à noter en aveugle » traversent tels quels (renumérotés).
        base["statut"] = statut
        base["regle_remap"] = "na_conserve" if statut == "non_applicable" else "a_noter"
        base["commentaire"] = _commentaire_v12(entry)
        return base

    # statut == "evaluee".
    niveau_scores = g13.niveau_scores[cible]
    if entry.get("niveau") is not None:
        # Source déjà à niveaux (C9 v1.2 3 niveaux) → cible à échelle identique
        # (C10 v1.3) : niveau conservé, score dérivé de la grille v1.3.
        niveau = int(entry["niveau"])
        base.update(
            statut="evaluee",
            niveau=niveau,
            score=float(niveau_scores[niveau]),
            regle_remap="niveaux_identiques",
            commentaire=(
                f"Échelle 3 niveaux identique (0/5/10) : niveau {niveau} conservé. "
                + _commentaire_v12(entry)
            ),
        )
        return base

    # Source continue → cible à niveaux : le score existe-t-il sur la grille v1.3 ?
    score = float(entry["score"])
    verdict, cands = _bracket_niveaux(score, niveau_scores)
    if verdict == "exact":
        niveau = cands[0]
        base.update(
            statut="evaluee",
            niveau=niveau,
            score=float(niveau_scores[niveau]),
            regle_remap="continue_vers_niveaux_exact",
            commentaire=(
                f"Score v1.2 {score:g} = palier v1.3 niveau {niveau}. "
                + _commentaire_v12(entry)
            ),
        )
        return base

    paliers = [niveau_scores[n] for n in cands]
    base.update(
        statut="revue_requise",
        candidats_niveau=cands,
        candidats_score=paliers,
        regle_remap="continue_vers_niveaux_revue",
        commentaire=(
            f"Score v1.2 {score:g} sans équivalent exact sur l'échelle v1.3 "
            f"({'/'.join(str(s) for s in sorted(set(niveau_scores.values())))}) : "
            f"à trancher entre niveau {cands[0]} ({paliers[0]}) et niveau "
            f"{cands[-1]} ({paliers[-1]}). " + _commentaire_v12(entry)
        ),
    )
    return base


def remap_fusion(media: str, sources: list[dict]) -> dict:
    """Fusionne ex-C8 (engagement) + ex-C11 (positionnement) en C9 v1.3.

    La recombinaison de deux jugements en un seul niveau est un **jugement
    gold** : toujours ``revue_requise`` (ou ``a_noter`` si les deux sources le
    sont), les valeurs d'origine documentées pour la décision de Laurin.
    """
    g13 = grille("v1.3")
    origine = [_origine(s) for s in sources]
    base = {
        "media_domaine": media,
        "critere": FUSION_CIBLE,
        "version_methodo": "v1.3",
        "score": None,
        "niveau": None,
        "origine_v12": origine,
        "regle_remap": "fusion_c8_c11",
    }
    commentaires = " ".join(_commentaire_v12(s) for s in sources)

    if all(s["statut"] == "a_noter" for s in sources):
        base["statut"] = "a_noter"
        base["regle_remap"] = "fusion_c8_c11_a_noter"
        base["commentaire"] = (
            "Fusion ex-C8 + ex-C11 → C9 (3 niveaux 0/5/10). À noter EN AVEUGLE. "
            + commentaires
        )
        return base

    # Au moins une source évaluée : recombinaison à trancher entre Absent (0) et
    # Partiel (5) — un positionnement partiel (ex-C11) sans engagement formalisé
    # public (ex-C8 négatifs) penche vers Absent, mais reste un jugement gold.
    niveau_scores = g13.niveau_scores[FUSION_CIBLE]
    cands = [0, 1]
    base.update(
        statut="revue_requise",
        candidats_niveau=cands,
        candidats_score=[niveau_scores[n] for n in cands],
        commentaire=(
            "Fusion ex-C8 (engagement déontologique) + ex-C11 (transparence du "
            "positionnement) → C9 v1.3 (3 niveaux 0/5/10). À trancher entre "
            f"Absent (niveau 0 = {niveau_scores[0]}) et Partiel (niveau 1 = "
            f"{niveau_scores[1]}). " + commentaires
        ),
    )
    return base


def remapper(gold_v0: dict) -> list[dict]:
    """Produit les entrées v1.3 depuis le gold v1.2 (déterministe, ordonné)."""
    par_media: dict[str, dict[str, dict]] = {}
    for entry in gold_v0["entries"]:
        par_media.setdefault(entry["media_domaine"], {})[entry["critere"]] = entry

    remappees: list[dict] = []
    for media in sorted(par_media):
        entrees = par_media[media]
        produites: dict[str, dict] = {}
        # Renumérotations simples.
        for src, cible in RENUMEROTATION.items():
            if src in entrees:
                produites[cible] = remap_simple(entrees[src], cible)
        # Fusion ex-C8 + ex-C11 → C9.
        sources_fusion = [entrees[s] for s in FUSION_SOURCES if s in entrees]
        if sources_fusion:
            produites[FUSION_CIBLE] = remap_fusion(media, sources_fusion)
        # Ordre stable (vague 1 v1.3).
        for critere in ORDRE_V13:
            if critere in produites:
                remappees.append(produites[critere])
    return remappees


def appliquer_decisions_po(entries: list[dict]) -> list[dict]:
    """Résout les entrées ``revue_requise`` du batch 1 avec les décisions PO.

    Chaque décision (``DECISIONS_PO``) fige le niveau retenu ; le score est dérivé
    de la grille v1.3 (ou pris tel quel si la décision fournit un ``score`` continu
    — notation continue guidée par les niveaux). Les candidats_* et l'origine_v12
    sont conservés pour la traçabilité de l'arbitrage. Les entrées sans décision
    (ex. reporterre.net ``a_noter``, à noter en aveugle) restent inchangées.
    """
    g13 = grille("v1.3")
    for e in entries:
        decision = DECISIONS_PO.get((e["media_domaine"], e["critere"]))
        if decision is None or e["statut"] != "revue_requise":
            continue
        niveau = int(decision["niveau"])
        niveau_scores = g13.niveau_scores[e["critere"]]
        score = float(decision.get("score", niveau_scores[niveau]))
        e["statut"] = "evaluee"
        e["niveau"] = niveau
        e["score"] = score
        e["regle_remap"] = f"{e.get('regle_remap', '')}+decision_po"
        e["decision_po"] = {
            "note_at": "2026-07-18",
            "niveau": niveau,
            "score": score,
            "motif": decision["motif"],
        }
        e["commentaire"] = (
            f"[Décision PO 2026-07-18 — niveau {niveau} ({score:g})] "
            f"{decision['motif']} " + (e.get("commentaire") or "")
        ).strip()
    return entries


def construire_gold_v13(gold_v0: dict, entries: list[dict]) -> dict:
    return {
        "version_methodo": "v1.3",
        "notateur": gold_v0.get("notateur", "humain:laurin"),
        "note_at": gold_v0.get("note_at"),
        "remap_depuis": "gold_v0.json",
        "remap_note": (
            "Re-mapping du gold batch 1 (v1.2 → v1.3, Annexe B) + décisions PO "
            "(STOP validation n°2, 2026-07-18). Les déterminations v1.2 sont "
            "conservées ; les 3 entrées revue_requise CNEWS (C6/C8/C9) ont été "
            "tranchées par Laurin (voir champ decision_po). Les entrées "
            "reporterre.net restent a_noter (à noter en aveugle avant tout run). "
            "gold_v0.json reste la référence figée du batch 1 v1.2."
        ),
        "entries": entries,
    }


def _resume(entries: list[dict]) -> str:
    lignes = []
    for e in entries:
        detail = ""
        if e["statut"] == "revue_requise":
            detail = f" → niveaux candidats {e.get('candidats_niveau')}"
        elif e["statut"] == "evaluee":
            detail = f" → niveau {e['niveau']} ({e['score']:g})"
        origine = "+".join(o["critere"] for o in e["origine_v12"])
        lignes.append(
            f"  {e['media_domaine']:16} {origine:>7} → {e['critere']:3} "
            f"[{e['statut']}]{detail}"
        )
    return "\n".join(lignes)


def run(*, dry_run: bool, report_path: Path) -> int:
    gold_v0 = json.loads(GOLD_V0.read_text())
    # Valide la source contre la grille v1.2 (garde-fou : gold_v0 bien formé).
    GoldenSet.model_validate(gold_v0)

    entries = remapper(gold_v0)
    appliquer_decisions_po(entries)
    gold_v13 = construire_gold_v13(gold_v0, entries)

    # Valide le résultat contre la grille v1.3 (critères en vague 1, niveaux
    # bornés). Les champs de provenance (origine_v12, candidats_*) sont ignorés
    # par le modèle mais conservés dans le fichier pour la revue de Laurin.
    GoldenSet.model_validate(gold_v13)

    n_revue = sum(1 for e in entries if e["statut"] == "revue_requise")
    n_eval = sum(1 for e in entries if e["statut"] == "evaluee")
    n_na = sum(1 for e in entries if e["statut"] == "non_applicable")
    n_note = sum(1 for e in entries if e["statut"] == "a_noter")
    print("Re-mapping gold v1.2 → v1.3 :")
    print(_resume(entries))
    print(
        f"\n{len(entries)} entrées : {n_eval} evaluee · {n_revue} revue_requise "
        f"(à trancher) · {n_na} non_applicable · {n_note} a_noter (aveugle)."
    )

    if dry_run:
        print("\n(dry-run — aucun fichier écrit.)")
        return 0

    GOLD_V13.write_text(json.dumps(gold_v13, indent=2, ensure_ascii=False) + "\n")
    print(f"\nÉcrit : {GOLD_V13.relative_to(_REPO_ROOT)}")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(gold_v13, indent=2, ensure_ascii=False) + "\n")
    print(f"Export : {report_path}")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="affiche le résultat sans écrire"
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_REPORT,
        help="copie de l'export (défaut : .context/media_eval/pilote-2026-07b/)",
    )
    args = parser.parse_args()
    sys.exit(run(dry_run=args.dry_run, report_path=args.report))


if __name__ == "__main__":
    main()
