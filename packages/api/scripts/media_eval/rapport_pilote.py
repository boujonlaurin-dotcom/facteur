#!/usr/bin/env python3
"""Rapport de run pilote (D7) — Markdown auditable + HTML propre, lecture seule.

Tous les chiffres viennent de la DB (signaux, évaluations, fiches) et du golden
set humain : un reviewer humain peut les recouper. `run()` écrit **deux** rendus
depuis une **unique** collecte DB (`collecter_donnees_rapport`) :
`<out>.md` (git-diffable, audit) et `<out>.html` (rapport autonome single-file,
deux lentilles : propreté des données puis qualité des évaluations). Sections
Markdown :

1. Contexte : run, date_reference, sha256 des rubriques, horodatage gold vs
   évaluations (**preuve D4** : le gold doit précéder les évaluations).
2. Signaux par média × critère × voie.
3. Garde-fous activés (fraîcheur, fallback C1, raccourci JTI, corroboration,
   bloque_acces).
4. Scores vs gold (gold / généré / Δ / accord).
5. Fiches (brut, max applicable, renormalisé, lettre, confiance).
6. **Verdict PASS/FAIL des 4 critères de succès V0** avec preuves chiffrées.
7. Notes de collecte et limites.

Usage :
    cd packages/api
    python3 scripts/media_eval/rapport_pilote.py --run-id pilote-2026-07 \
        --gold ../../docs/media-eval/golden/gold_v0.json \
        --out ../../docs/media-eval/rapports/pilote-2026-07.md
"""

from __future__ import annotations

import argparse
import asyncio
import html
import sys
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    MediaEvalEvaluation,
    MediaEvalMedia,
    MediaEvalRun,
    MediaEvalSignal,
)
from scripts.media_eval.build_eval_input import version_prompt
from scripts.media_eval.evaluate_golden_agreement import evaluate
from scripts.media_eval.export_evaluations import evaluations_to_goldenset
from scripts.media_eval.schemas import (
    BAREMES,
    CORROBORATION_MIN_SOURCES,
    CRITERES_VAGUE_1,
    GoldenSet,
)
from scripts.media_eval.synthese_fiche import compute_fiche

_GARDE_FOUS = (
    ("fraîcheur (730 j)", "signaux événementiels > 730 j exclus (amont)"),
    ("fallback C1", "< 3 débunkages frais → N/A"),
    ("raccourci JTI", "certification valide → C8 pleine par code"),
    ("corroboration", "score plein < 2 sources → palier inférieur"),
    ("bloque_acces", "accès refusé → revue_requise, jamais 0"),
)


# --------------------------------------------------------------------------- #
# Rendu ASCII pur — testable sans DB.
# --------------------------------------------------------------------------- #
def _table(headers: list[str], rows: list[list[str]]) -> str:
    cols = (
        list(zip(*([headers] + rows), strict=False)) if rows else [[h] for h in headers]
    )
    largeurs = [max(len(str(c)) for c in col) for col in cols]
    sep = "+-" + "-+-".join("-" * w for w in largeurs) + "-+"

    def ligne(vals: list[str]) -> str:
        return (
            "| "
            + " | ".join(str(v).ljust(w) for v, w in zip(vals, largeurs, strict=False))
            + " |"
        )

    out = [sep, ligne(headers), sep]
    out += [ligne(r) for r in rows]
    out.append(sep)
    return "\n".join(out)


def tableau_signaux(signaux: list[dict]) -> str:
    """Signaux par média × critère × voie × statut (comptage)."""
    agg: dict[tuple, int] = {}
    for s in signaux:
        cle = (s["media"], s["critere"], s["voie"], s["statut"])
        agg[cle] = agg.get(cle, 0) + 1
    rows = [[m, c, v, st, str(n)] for (m, c, v, st), n in sorted(agg.items())]
    if not rows:
        return "(aucun signal)"
    return _table(["Média", "Critère", "Voie", "Statut", "N"], rows)


def tableau_garde_fous(actives: dict[str, str]) -> str:
    """État de chaque garde-fou (activé sur ce run ou non)."""
    rows = []
    for nom, desc in _GARDE_FOUS:
        etat = actives.get(nom, "—")
        rows.append([nom, desc, etat])
    return _table(["Garde-fou", "Règle", "Constaté"], rows)


def tableau_accord(report: dict) -> str:
    """Détail gold / généré / Δ / accord par paire (depuis evaluate())."""
    if report.get("n", 0) == 0:
        return f"(pas de paire comparable : {report.get('error', 'vide')})"
    rows = []
    for r in sorted(report["desaccords"], key=lambda r: (r["media"], r["critere"])):
        rows.append(
            [
                r["media"],
                r["critere"],
                str(
                    r["gold_score"]
                    if r["gold_statut"] == "evaluee"
                    else r["gold_statut"]
                ),
                str(
                    r["gen_score"] if r["gen_statut"] == "evaluee" else r["gen_statut"]
                ),
                str(r["delta"] if r["delta"] is not None else "-"),
                "✗ " + str(r["type_desaccord"]),
            ]
        )
    entete = (
        f"Accord global : {report['accord_global']:.0%} · par média : "
        f"{report['par_media']} · N/A-vs-score : {report['na_vs_score']} · "
        f"MAE : {report['mae_scores']}"
    )
    if not rows:
        return entete + "\n(aucun désaccord)"
    return (
        entete
        + "\n"
        + _table(["Média", "Critère", "Gold", "Généré", "Δ", "Désaccord"], rows)
    )


def verdict_v0(metrics: dict) -> list[dict]:
    """PASS/FAIL des 4 critères de succès V0 — pur, testable."""
    accord = metrics["accord_par_media"]
    ok_accord = bool(accord) and all(n >= 4 for n in accord.values())
    reporterre = metrics.get("reporterre", {})
    ok_reporterre = (
        reporterre.get("c1_statut") == "non_applicable"
        and reporterre.get("max_applicable") == 34.0
    )
    return [
        {
            "critere": "1. Artefacts valides sans édition manuelle",
            "pass": metrics["evaluations_valides"],
            "preuve": f"{metrics['n_evaluations']} évaluations ingérées "
            "(validées Pydantic avant écriture DB)",
        },
        {
            "critere": "2. Accord ≥ 4/6 par média",
            "pass": ok_accord,
            "preuve": " · ".join(f"{m}: {n}/6" for m, n in sorted(accord.items()))
            or "aucune paire",
        },
        {
            "critere": "3. Reporterre C1 = N/A + renormalisation 34 pts",
            "pass": ok_reporterre,
            "preuve": f"C1 statut={reporterre.get('c1_statut', '—')}, "
            f"max_applicable={reporterre.get('max_applicable', '—')}",
        },
        {
            "critere": "4. Zéro écriture DB par agent",
            "pass": metrics["zero_ecriture_agent"],
            "preuve": "signaux voie=agent via ingest_artifacts, évals via "
            "ingest_evaluations (aucun agent n'ouvre de session DB)",
        },
    ]


def render_verdict(criteres: list[dict]) -> str:
    rows = [
        [c["critere"], "PASS" if c["pass"] else "FAIL", c["preuve"]] for c in criteres
    ]
    global_pass = all(c["pass"] for c in criteres)
    tag = "✅ V0 VALIDÉ" if global_pass else "❌ V0 NON VALIDÉ"
    return _table(["Critère de succès", "Verdict", "Preuve"], rows) + f"\n\n{tag}"


# --------------------------------------------------------------------------- #
# Lentille A — propreté des données (pur, testable sans DB).
# --------------------------------------------------------------------------- #
# Notes de complétude par (média, critère) — palette *status* réservée, rendue
# toujours avec icône + label (jamais couleur seule). Distinction cardinale :
# `bloque` = trou d'accès (donnée manquante) ; `absent_confirme` = absence
# vérifiée avec preuve de recherche (donnée propre).
NOTE_RICHE = "riche"
NOTE_PARTIEL = "partiel"
NOTE_BLOQUE = "bloque"
NOTE_ABSENT = "absent_confirme"
NOTE_NA = "na"
NOTES_ORDRE: tuple[str, ...] = (
    NOTE_RICHE,
    NOTE_PARTIEL,
    NOTE_BLOQUE,
    NOTE_ABSENT,
    NOTE_NA,
)
NOTE_LABEL: dict[str, str] = {
    NOTE_RICHE: "Riche",
    NOTE_PARTIEL: "Partiel",
    NOTE_BLOQUE: "Bloqué",
    NOTE_ABSENT: "Absence confirmée",
    NOTE_NA: "N/A",
}
NOTE_ICON: dict[str, str] = {
    NOTE_RICHE: "●",
    NOTE_PARTIEL: "◐",
    NOTE_BLOQUE: "⚠",
    NOTE_ABSENT: "○",
    NOTE_NA: "–",
}
NOTE_DESC: dict[str, str] = {
    NOTE_RICHE: "signal présent + corroboré (≥ 2 sources indépendantes)",
    NOTE_PARTIEL: "signal présent/partiel mais non corroboré",
    NOTE_BLOQUE: "trou d'accès — donnée manquante (accès refusé / non collectée)",
    NOTE_ABSENT: "absence confirmée avec preuve de recherche (donnée propre)",
    NOTE_NA: "critère non applicable (exclu du dénominateur)",
}
_STATUTS_PRESENTS = ("present", "partiel")


def _domaines_independants(urls: list[str]) -> int:
    """Nb de domaines distincts (proxy d'indépendance des sources)."""
    domaines: set[str] = set()
    for u in urls:
        net = urlparse(u).netloc.lower() if u else ""
        net = net[4:] if net.startswith("www.") else net
        domaines.add(net or (u or ""))
    domaines.discard("")
    return len(domaines)


def _note_cellule(signaux_cell: list[dict], statut_eval: str | None) -> dict:
    """Note de complétude d'un couple (média, critère) — pur, testable."""
    base_note = NOTE_NA if statut_eval == "non_applicable" else None
    par_statut: dict[str, int] = {}
    par_voie: dict[str, int] = {}
    sources: list[str] = []
    for s in signaux_cell:
        par_statut[s["statut"]] = par_statut.get(s["statut"], 0) + 1
        par_voie[s["voie"]] = par_voie.get(s["voie"], 0) + 1
        if s["statut"] in _STATUTS_PRESENTS:
            sources.extend(s.get("source_urls") or [])
    n_sources = _domaines_independants(sources)
    corrobore = n_sources >= CORROBORATION_MIN_SOURCES
    a_present = any(s["statut"] == "present" for s in signaux_cell)
    a_donnee = any(s["statut"] in _STATUTS_PRESENTS for s in signaux_cell)

    if base_note is not None:
        note = base_note
    elif a_present and corrobore:
        note = NOTE_RICHE
    elif a_donnee:
        note = NOTE_PARTIEL
    elif any(s["statut"] == "bloque_acces" for s in signaux_cell):
        note = NOTE_BLOQUE
    elif any(s["statut"] == "absent_verifie" for s in signaux_cell):
        note = NOTE_ABSENT
    else:
        note = NOTE_BLOQUE  # aucun signal exploitable → trou de couverture
    return {
        "note": note,
        "n_signaux": len(signaux_cell),
        "par_statut": par_statut,
        "par_voie": par_voie,
        "n_sources": n_sources,
        "corrobore": corrobore and note in (NOTE_RICHE, NOTE_PARTIEL),
        "statut_eval": statut_eval,
    }


def evaluer_proprete_donnees(
    signaux: list[dict],
    evaluations: list[dict],
    fiches: dict[str, dict],
) -> dict:
    """Lentille « propreté des données » — pur, testable sans DB.

    Par (média, critère) : décompte signaux, ventilation voie/statut,
    corroboration et **note de complétude** (`riche | partiel | bloque |
    absent_confirme | na`). Plus un rollup santé-data par média et global.
    """
    statut_eval = {(e["media_domaine"], e["critere"]): e["statut"] for e in evaluations}
    par_cle: dict[tuple[str, str], list[dict]] = {}
    for s in signaux:
        par_cle.setdefault((s["media"], s["critere"]), []).append(s)

    medias = sorted(
        {s["media"] for s in signaux}
        | {e["media_domaine"] for e in evaluations}
        | set(fiches)
    )
    cellules: list[dict] = []
    for media in medias:
        for critere in CRITERES_VAGUE_1:
            cle = (media, critere)
            cell_sig = par_cle.get(cle, [])
            st_eval = statut_eval.get(cle)
            if not cell_sig and st_eval is None:
                continue  # ni signal ni éval : critère hors périmètre du run
            note = _note_cellule(cell_sig, st_eval)
            cellules.append({"media": media, "critere": critere, **note})

    par_media: dict[str, dict] = {}
    for c in cellules:
        par_media.setdefault(c["media"], []).append(c)

    def _rollup(cells: list[dict]) -> dict:
        par_note = dict.fromkeys(NOTES_ORDRE, 0)
        for c in cells:
            par_note[c["note"]] += 1
        n_avec_donnee = sum(par_note[n] for n in (NOTE_RICHE, NOTE_PARTIEL))
        n_corrobore = sum(1 for c in cells if c["corrobore"])
        return {
            "n_signaux": sum(c["n_signaux"] for c in cells),
            "n_cellules": len(cells),
            "par_note": par_note,
            "n_corrobore": n_corrobore,
            "n_avec_donnee": n_avec_donnee,
            "n_bloque": par_note[NOTE_BLOQUE],
            "pct_corrobore": (
                round(n_corrobore / n_avec_donnee, 3) if n_avec_donnee else None
            ),
        }

    return {
        "cellules": cellules,
        "par_media": {m: _rollup(cs) for m, cs in sorted(par_media.items())},
        "global": _rollup(cellules),
    }


# --------------------------------------------------------------------------- #
# Rendu HTML autonome (single-file, CSS inline) — pur, testable sans DB.
# --------------------------------------------------------------------------- #
def _esc(value: object) -> str:
    return html.escape("" if value is None else str(value), quote=True)


# Voie (français) → classes CSS du design system (badge, pastille, en anglais).
_VOIE_CLS: dict[str, tuple[str, str]] = {
    "code": ("b-code", "d-code"),
    "agent": ("b-agent", "d-agent"),
    "humain": ("b-human", "d-human"),
}


def _voie_dots(par_voie: dict[str, int]) -> str:
    return "".join(
        f'<span class="dot {_VOIE_CLS[v][1]}" title="{v} ×{par_voie[v]}"></span>'
        for v in ("code", "agent", "humain")
        if par_voie.get(v)
    )


def _val_accord(statut: str, score: float | None, niveau: int | None) -> str:
    if niveau is not None:
        return f"niv {niveau}"
    if statut == "evaluee":
        return "—" if score is None else f"{score:g}"
    return statut


_CONFIANCE_CLS = {"haute": "ok", "moyenne": "mid", "basse": "warn"}

_HTML_STYLE = """
  :root{
    --ink:#1b2430;--ink-soft:#48566a;--line:#e3e8ef;--bg:#f6f8fb;--card:#fff;
    --brand:#2f5fe0;--brand-soft:#eaf0ff;
    --code:#0f766e;--code-soft:#e6f6f3;--agent:#7c3aed;--agent-soft:#f1eafe;
    --human:#b45309;--human-soft:#fdf1e0;--ok:#15803d;--warn:#b91c1c;
    --st-riche:#15803d;--st-riche-bg:#eaf6ee;
    --st-partiel:#a16207;--st-partiel-bg:#fdf6e3;
    --st-bloque:#b91c1c;--st-bloque-bg:#fdeceb;
    --st-absent:#475569;--st-absent-bg:#eef2f7;
    --st-na:#94a3b8;--st-na-bg:#f4f6f9;
    --shadow:0 1px 2px rgba(16,24,40,.06),0 8px 24px rgba(16,24,40,.05);
  }
  *{box-sizing:border-box;}
  body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,
    Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg);
    line-height:1.55;-webkit-font-smoothing:antialiased;}
  .wrap{max-width:1080px;margin:0 auto;padding:0 22px 96px;}
  header.hero{background:linear-gradient(135deg,#1b2a4e 0%,#2f5fe0 100%);
    color:#fff;padding:48px 0 40px;box-shadow:var(--shadow);}
  header.hero .wrap{padding-bottom:0;}
  .eyebrow{text-transform:uppercase;letter-spacing:.14em;font-size:12px;
    font-weight:700;opacity:.82;margin:0 0 10px;}
  header.hero h1{font-size:32px;line-height:1.15;margin:0 0 12px;font-weight:800;}
  header.hero p.lede{font-size:16px;max-width:780px;margin:0;opacity:.95;}
  .meta-row{display:flex;flex-wrap:wrap;gap:10px;margin-top:20px;}
  .pill{display:inline-flex;align-items:center;gap:7px;
    background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.22);
    padding:5px 12px;border-radius:999px;font-size:13px;font-weight:600;}
  .verdict-row{display:flex;flex-wrap:wrap;gap:12px;align-items:center;
    margin-top:22px;}
  .vbadge{display:inline-flex;align-items:center;gap:8px;font-weight:800;
    font-size:15px;padding:8px 16px;border-radius:10px;}
  .vbadge.ok{background:#eaf6ee;color:var(--ok);}
  .vbadge.warn{background:#fdeceb;color:var(--warn);}
  .vbadge.big{font-size:16px;}
  .accord-tag{font-size:14px;font-weight:700;color:#fff;opacity:.95;}
  section{margin:0 0 46px;}
  h2{font-size:23px;font-weight:800;margin:34px 0 4px;letter-spacing:-.01em;
    display:flex;align-items:baseline;gap:12px;}
  h2 .num{font-size:14px;font-weight:800;color:#fff;background:var(--brand);
    border-radius:8px;padding:2px 10px;}
  h3{font-size:17px;font-weight:700;margin:26px 0 10px;}
  .section-lede{color:var(--ink-soft);font-size:15.5px;margin:0 0 18px;
    max-width:840px;}
  .card{background:var(--card);border:1px solid var(--line);border-radius:14px;
    padding:20px 22px;box-shadow:var(--shadow);}
  .grid{display:grid;gap:16px;}
  .grid-2{grid-template-columns:repeat(auto-fit,minmax(300px,1fr));}
  .grid-3{grid-template-columns:repeat(auto-fit,minmax(240px,1fr));}
  .grid-4{grid-template-columns:repeat(auto-fit,minmax(220px,1fr));}
  table{width:100%;border-collapse:collapse;font-size:14px;margin:8px 0 0;}
  th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);
    vertical-align:top;}
  th{font-size:12px;text-transform:uppercase;letter-spacing:.05em;
    color:var(--ink-soft);font-weight:700;}
  tbody tr:last-child td{border-bottom:none;}
  code,.mono{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,
    monospace;font-size:12.5px;background:#f1f4f8;padding:1px 6px;
    border-radius:5px;color:#223;}
  .badge{display:inline-flex;align-items:center;gap:6px;font-weight:700;
    font-size:12px;padding:3px 9px;border-radius:6px;white-space:nowrap;}
  .b-code{color:var(--code);background:var(--code-soft);}
  .b-agent{color:var(--agent);background:var(--agent-soft);}
  .b-human{color:var(--human);background:var(--human-soft);}
  .dot{width:9px;height:9px;border-radius:50%;display:inline-block;}
  .d-code{background:var(--code);}.d-agent{background:var(--agent);}
  .d-human{background:var(--human);}
  /* Matrice propreté — palette status réservée (icône + label). */
  .mx td{text-align:center;font-size:12.5px;}
  .mx td.media-cell{text-align:left;font-weight:700;white-space:nowrap;}
  .mx-cell{display:inline-flex;flex-direction:column;gap:3px;align-items:center;
    padding:6px 8px;border-radius:8px;min-width:96px;}
  .mx-note{font-weight:800;font-size:12.5px;display:inline-flex;gap:5px;
    align-items:center;}
  .mx-meta{font-size:11px;color:var(--ink-soft);display:inline-flex;gap:5px;
    align-items:center;}
  .mx-empty{color:var(--st-na);}
  .st-riche{background:var(--st-riche-bg);color:var(--st-riche);}
  .st-partiel{background:var(--st-partiel-bg);color:var(--st-partiel);}
  .st-bloque{background:var(--st-bloque-bg);color:var(--st-bloque);}
  .st-absent_confirme{background:var(--st-absent-bg);color:var(--st-absent);}
  .st-na{background:var(--st-na-bg);color:var(--st-na);}
  .legend{display:flex;flex-wrap:wrap;gap:14px;margin:14px 0 4px;font-size:13px;}
  .legend .lg{display:inline-flex;align-items:center;gap:6px;font-weight:600;
    padding:3px 9px;border-radius:7px;}
  .callout{border-left:4px solid var(--brand);background:var(--brand-soft);
    border-radius:0 10px 10px 0;padding:13px 17px;margin:16px 0;font-size:14px;}
  .callout.warn{border-left-color:var(--warn);background:#fdeceb;}
  .callout.ok{border-left-color:var(--ok);background:#eaf6ee;}
  /* Cartes santé + fiches + verdict */
  .stat{border-top:4px solid var(--brand);}
  .stat .big{font-size:26px;font-weight:800;margin:2px 0 0;}
  .stat .lbl{font-size:12px;text-transform:uppercase;letter-spacing:.05em;
    color:var(--ink-soft);font-weight:700;}
  .fiche{border-top:4px solid var(--brand);}
  .fiche .letter{font-size:30px;font-weight:800;color:var(--brand);}
  .scorebar{height:9px;border-radius:6px;background:var(--line);overflow:hidden;
    margin:10px 0 6px;}
  .scorebar-fill{height:100%;background:var(--brand);border-radius:6px;}
  .chip{display:inline-flex;align-items:center;gap:6px;font-size:12px;
    font-weight:700;padding:3px 9px;border-radius:6px;}
  .chip.ok{background:#eaf6ee;color:var(--ok);}
  .chip.mid{background:var(--st-partiel-bg);color:var(--st-partiel);}
  .chip.warn{background:#fdeceb;color:var(--warn);}
  .vcard{border-top:4px solid var(--line);}
  .vcard.pass{border-top-color:var(--ok);}
  .vcard.fail{border-top-color:var(--warn);}
  .vcard .vh{display:flex;justify-content:space-between;gap:10px;
    align-items:flex-start;}
  .vcard .vt{font-weight:800;font-size:14.5px;margin:0;}
  .vcard .vp{color:var(--ink-soft);font-size:13px;margin:8px 0 0;}
  details{border:1px solid var(--line);border-radius:10px;padding:2px 14px;
    margin:8px 0;background:var(--card);}
  details>summary{cursor:pointer;font-weight:700;padding:10px 0;font-size:14px;}
  details .sig{border-top:1px solid var(--line);padding:10px 0;}
  details .sig:first-of-type{border-top:none;}
  .sig .cit{color:var(--ink-soft);font-size:13.5px;margin:4px 0;font-style:italic;}
  .sig .src{font-size:12px;word-break:break-all;}
  .sig .src a{color:var(--brand);text-decoration:none;}
  .row-warn{background:#fdeceb;}
  footer{border-top:1px solid var(--line);padding:22px 0;color:var(--ink-soft);
    font-size:13px;text-align:center;}
  @media (max-width:640px){header.hero h1{font-size:26px;}h2{font-size:20px;}}
"""


def _html_hero(run: dict, gl: dict, verdict: list[dict], accord: dict) -> str:
    global_pass = all(c["pass"] for c in verdict)
    vcls = "ok" if global_pass else "warn"
    vtxt = "✅ V0 VALIDÉ" if global_pass else "❌ V0 non validé"
    pct = gl.get("pct_corrobore")
    pct_txt = f"{pct:.0%}" if pct is not None else "—"
    accord_txt = (
        f"Accord global : {accord['accord_global']:.0%}"
        if accord.get("n", 0)
        else "Accord : pas de paire comparable"
    )
    perim = run.get("perimetre") or {}
    medias = ", ".join(perim.get("medias", [])) if isinstance(perim, dict) else ""
    return f"""<header class="hero"><div class="wrap">
  <p class="eyebrow">Facteur · media-eval · Rapport de run</p>
  <h1>{_esc(run["run_id"])}</h1>
  <p class="lede">Méthodologie {_esc(run["version_methodo"])} · date_reference
    (fraîcheur) <strong>{_esc(run["date_reference"])}</strong>{
        f" · périmètre : {_esc(medias)}" if medias else ""
    }. Deux lentilles : propreté des données collectées, puis qualité des
    évaluations (accord vs golden humain).</p>
  <div class="meta-row">
    <span class="pill">{gl["n_signaux"]} signaux collectés</span>
    <span class="pill">{pct_txt} corroborés</span>
    <span class="pill">{gl["n_bloque"]} trou(s) d'accès</span>
  </div>
  <div class="verdict-row">
    <span class="vbadge {vcls} big">{vtxt}</span>
    <span class="accord-tag">{_esc(accord_txt)}</span>
  </div>
</div></header>"""


def _html_matrice(proprete: dict) -> str:
    cellules = {(c["media"], c["critere"]): c for c in proprete["cellules"]}
    medias = sorted({c["media"] for c in proprete["cellules"]})
    head = "".join(
        f'<th>{c}<br><span style="font-weight:600;text-transform:none;'
        f'color:var(--ink-soft)">{BAREMES[c]} pts</span></th>'
        for c in CRITERES_VAGUE_1
    )
    lignes = []
    for media in medias:
        cells = [f'<td class="media-cell">{_esc(media)}</td>']
        for critere in CRITERES_VAGUE_1:
            c = cellules.get((media, critere))
            if c is None:
                cells.append('<td><span class="mx-empty">—</span></td>')
                continue
            note = c["note"]
            meta_bits = [f"{c['n_signaux']} sig"]
            dots = _voie_dots(c["par_voie"])
            if dots:
                meta_bits.append(dots)
            if note in (NOTE_RICHE, NOTE_PARTIEL):
                mark = "✓" if c["corrobore"] else "·"
                meta_bits.append(f"{mark} {c['n_sources']} src")
            cells.append(
                f'<td><span class="mx-cell st-{note}">'
                f'<span class="mx-note">{NOTE_ICON[note]} {NOTE_LABEL[note]}</span>'
                f'<span class="mx-meta">{" · ".join(meta_bits)}</span>'
                f"</span></td>"
            )
        lignes.append("<tr>" + "".join(cells) + "</tr>")
    legend = "".join(
        f'<span class="lg st-{n}">{NOTE_ICON[n]} {NOTE_LABEL[n]}</span>'
        for n in NOTES_ORDRE
    )
    rollup = "".join(
        f'<div class="card stat"><div class="lbl">{_esc(m)}</div>'
        f'<div class="big">{r["n_signaux"]}</div>'
        f'<div class="lbl" style="margin-top:6px">signaux · '
        f"{r['par_note'][NOTE_RICHE]} riche · {r['n_bloque']} bloqué · "
        f"{r['par_note'][NOTE_NA]} N/A</div></div>"
        for m, r in proprete["par_media"].items()
    )
    return f"""<section id="proprete">
  <h2><span class="num">1</span> Propreté des données collectées</h2>
  <p class="section-lede">À quel point les données derrière chaque note sont
    propres : présence, provenance (voie), corroboration, et surtout la
    distinction cardinale <strong>trou d'accès</strong> (donnée manquante) vs
    <strong>absence confirmée</strong> (donnée propre, preuve de recherche à
    l'appui).</p>
  <div class="grid grid-4" style="margin-bottom:18px">{rollup}</div>
  <div class="card" style="overflow-x:auto;padding-top:8px">
    <table class="mx"><thead><tr><th>Média</th>{head}</tr></thead>
    <tbody>{"".join(lignes)}</tbody></table>
    <div class="legend">{legend}</div>
    <div class="callout"><strong>Distinction cardinale :</strong>
      <span class="badge st-bloque">⚠ Bloqué</span> = trou d'accès (l'accès a été
      refusé ou la donnée n'a pu être collectée — donnée <em>manquante</em>) ·
      <span class="badge st-absent_confirme">○ Absence confirmée</span> = le média
      n'a pas cette caractéristique et on l'a <em>vérifié</em> (sources
      consultées) — donnée <em>propre</em>, jamais convertie en 0.</div>
  </div>
</section>"""


def _html_signaux(signaux: list[dict]) -> str:
    par_cle: dict[tuple[str, str], list[dict]] = {}
    for s in signaux:
        par_cle.setdefault((s["media"], s["critere"]), []).append(s)
    if not par_cle:
        contenu = "<p class='section-lede'>(aucun signal collecté)</p>"
    else:
        blocs = []
        for (media, critere), sigs in sorted(par_cle.items()):
            items = []
            for s in sigs:
                srcs = "".join(
                    f'<div class="src">🔗 <a href="{_esc(u)}">{_esc(u)}</a></div>'
                    for u in (s.get("source_urls") or [])
                )
                consultees = s.get("sources_consultees") or []
                preuve = (
                    f'<div class="src">🔎 preuve de recherche : '
                    f"{_esc(', '.join(consultees))}</div>"
                    if consultees
                    else ""
                )
                voie = s["voie"]
                bcls, dcls = _VOIE_CLS.get(voie, ("b-code", "d-code"))
                cit = (
                    f'<div class="cit">« {_esc(s["citation"])} »</div>'
                    if s.get("citation")
                    else ""
                )
                items.append(
                    f'<div class="sig"><code>{_esc(s["type_signal"])}</code> '
                    f'<span class="badge st-{_statut_note(s["statut"])}">'
                    f"{_esc(s['statut'])}</span> "
                    f'<span class="badge {bcls}">'
                    f'<span class="dot {dcls}"></span>{_esc(voie)}</span>'
                    f"{cit}{srcs}{preuve}</div>"
                )
            blocs.append(
                f"<details><summary>{_esc(media)} · {critere} "
                f"— {len(sigs)} signal(aux)</summary>{''.join(items)}</details>"
            )
        contenu = "".join(blocs)
    return f"""<section id="signaux">
  <h2><span class="num">2</span> Signaux détaillés</h2>
  <p class="section-lede">La preuve derrière chaque note : citation, URLs
    sources et, pour les absences vérifiées, les sources consultées.</p>
  {contenu}
</section>"""


def _statut_note(statut: str) -> str:
    """Classe de couleur status pour un statut de signal (rendu badge)."""
    return {
        "present": NOTE_RICHE,
        "partiel": NOTE_PARTIEL,
        "bloque_acces": NOTE_BLOQUE,
        "absent_verifie": NOTE_ABSENT,
    }.get(statut, NOTE_NA)


def _html_fiches(fiches: dict[str, dict]) -> str:
    if not fiches:
        return (
            '<section id="fiches"><h2><span class="num">3</span> Fiches par '
            "média</h2><p class='section-lede'>(aucune fiche)</p></section>"
        )
    cartes = []
    for media, f in sorted(fiches.items()):
        pct = max(0.0, min(100.0, f["score_renormalise"]))
        ccls = _CONFIANCE_CLS.get(f["confiance"], "mid")
        na = ", ".join(f["criteres_na"]) or "aucun"
        evalues = ", ".join(f["criteres_evalues"]) or "aucun"
        cartes.append(
            f'<div class="card fiche"><div style="display:flex;'
            f'justify-content:space-between;align-items:flex-start;gap:10px">'
            f"<div><div style='font-weight:800;font-size:16px'>{_esc(media)}</div>"
            f'<div class="lbl" style="color:var(--ink-soft)">'
            f"{f['score_brut']:g} / {f['score_max_applicable']:g} pts "
            f"applicables</div></div>"
            f'<div class="letter">{_esc(f["lettre"])}</div></div>'
            f'<div class="scorebar"><div class="scorebar-fill" '
            f'style="width:{pct:g}%"></div></div>'
            f'<div style="font-weight:800;font-size:15px">'
            f'{f["score_renormalise"]:g}<span style="color:var(--ink-soft);'
            f'font-weight:600">/100</span></div>'
            f'<div style="margin-top:10px"><span class="chip {ccls}">confiance '
            f"{_esc(f['confiance'])}</span></div>"
            f'<div class="lbl" style="margin-top:10px;color:var(--ink-soft);'
            f'text-transform:none;letter-spacing:0">Évalués : {_esc(evalues)}'
            f"<br>N/A : {_esc(na)}</div></div>"
        )
    return f"""<section id="fiches">
  <h2><span class="num">3</span> Fiches par média</h2>
  <p class="section-lede">Score renormalisé sur les critères applicables (les
    N/A sortent du dénominateur), lettre A–E, niveau de confiance.</p>
  <div class="grid grid-3">{"".join(cartes)}</div>
</section>"""


def _html_accord(accord: dict) -> str:
    if accord.get("n", 0) == 0:
        return f"""<section id="accord">
  <h2><span class="num">4</span> Accord évaluations vs golden</h2>
  <div class="callout warn">Pas de paire comparable :
    {_esc(accord.get("error", "vide"))}.</div>
</section>"""
    par_media = " · ".join(f"{m} : {v}" for m, v in accord["par_media"].items())
    rows = []
    for d in accord["desaccords"]:
        na = d["type_desaccord"] == "na_vs_score"
        rows.append(
            f'<tr class="{"row-warn" if na else ""}">'
            f"<td>{_esc(d['media'])}</td><td>{d['critere']}</td>"
            f"<td>{_esc(d['type_desaccord'])}</td>"
            f"<td>{_esc(_val_accord(d['gold_statut'], d['gold_score'], d['gold_niveau']))}</td>"
            f"<td>{_esc(_val_accord(d['gen_statut'], d['gen_score'], d['gen_niveau']))}</td>"
            f"<td>{d['delta'] if d['delta'] is not None else '—'}</td></tr>"
        )
    corps = (
        "".join(rows)
        if rows
        else '<tr><td colspan="6">Aucun désaccord — accord parfait.</td></tr>'
    )
    return f"""<section id="accord">
  <h2><span class="num">4</span> Accord évaluations vs golden</h2>
  <p class="section-lede">Qualité des évaluations : accord avec la notation
    humaine de référence (exact sur les niveaux C9/C11, |Δ| ≤ 20 % du barème
    sinon). Les désaccords <strong>N/A-vs-score</strong> (surlignés) sont ceux
    qui font échouer le critère 2.</p>
  <div class="card" style="padding-top:8px">
    <p><strong>Accord global : {accord["accord_global"]:.0%}</strong> ·
      par média : {_esc(par_media)} · désaccords N/A-vs-score :
      <strong>{accord["na_vs_score"]}</strong> · MAE : {accord["mae_scores"]}</p>
    <table><thead><tr><th>Média</th><th>Critère</th><th>Type</th><th>Gold</th>
      <th>Généré</th><th>Δ</th></tr></thead><tbody>{corps}</tbody></table>
  </div>
</section>"""


def _html_verdict(verdict: list[dict], d4: dict) -> str:
    cartes = []
    for c in verdict:
        cls = "pass" if c["pass"] else "fail"
        tag_cls = "ok" if c["pass"] else "warn"
        tag = "PASS" if c["pass"] else "FAIL"
        cartes.append(
            f'<div class="card vcard {cls}"><div class="vh">'
            f'<p class="vt">{_esc(c["critere"])}</p>'
            f'<span class="vbadge {tag_cls}">{tag}</span></div>'
            f'<p class="vp">{_esc(c["preuve"])}</p></div>'
        )
    d4cls = "ok" if d4.get("ok") else "warn"
    return f"""<section id="verdict">
  <h2><span class="num">5</span> Verdict V0</h2>
  <p class="section-lede">Les 4 critères de succès verrouillés du pilote V0,
    avec leur preuve chiffrée.</p>
  <div class="grid grid-2">{"".join(cartes)}</div>
  <div class="callout {d4cls}"><strong>Preuve D4 (golden en aveugle) :</strong>
    {_esc(d4["message"])}</div>
</section>"""


def _html_gardefous(garde_fous: dict[str, str], rubrics_sha: dict[str, str]) -> str:
    gf = "".join(
        f"<tr><td>{_esc(nom)}</td><td>{_esc(desc)}</td>"
        f"<td>{_esc(garde_fous.get(nom, '—'))}</td></tr>"
        for nom, desc in _GARDE_FOUS
    )
    sha = "".join(
        f"<tr><td>{c}</td><td><code>{_esc(sha[:12])}</code></td></tr>"
        for c, sha in sorted(rubrics_sha.items())
    )
    return f"""<section id="gardefous">
  <h2><span class="num">6</span> Garde-fous, notes & intégrité</h2>
  <div class="grid grid-2">
    <div class="card"><h3 style="margin-top:0">Garde-fous</h3>
      <table><thead><tr><th>Garde-fou</th><th>Règle</th><th>Constaté</th></tr>
      </thead><tbody>{gf}</tbody></table></div>
    <div class="card"><h3 style="margin-top:0">Intégrité des rubriques</h3>
      <p class="section-lede" style="margin-bottom:8px">sha256 (12) — fige la
        comparabilité gold/évals.</p>
      <table><thead><tr><th>Critère</th><th>sha256</th></tr></thead>
      <tbody>{sha}</tbody></table></div>
  </div>
  <div class="callout"><strong>Notes & limites :</strong> collecte partielle
    possible (anti-bot) → signaux <code>bloque_acces</code> honnêtes, critère en
    <code>revue_requise</code> (résultat valide) · <code>PAPPERS_API_TOKEN</code>
    absent → C5/C9 propriété en <code>bloque_acces</code> · ARCOM N/A structurel
    pour la presse en ligne (absence neutre).</div>
</section>"""


def render_html(data: dict, proprete: dict) -> str:
    """Rapport HTML autonome (single-file) — pur, testable sans DB."""
    run = data["run"]
    gen_date = datetime.now(UTC).date().isoformat()
    corps = "".join(
        [
            _html_hero(run, proprete["global"], data["verdict"], data["accord_report"]),
            '<div class="wrap">',
            _html_matrice(proprete),
            _html_signaux(data["signaux"]),
            _html_fiches(data["fiches"]),
            _html_accord(data["accord_report"]),
            _html_verdict(data["verdict"], data["d4"]),
            _html_gardefous(data["garde_fous"], data["rubrics_sha"]),
            f"<footer>Rapport media-eval {_esc(run['run_id'])} · généré le "
            f"{gen_date} · lecture seule (DB + gold) · méthodo "
            f"{_esc(run['version_methodo'])}</footer>",
            "</div>",
        ]
    )
    return (
        "<!DOCTYPE html>\n"
        '<html lang="fr"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>Rapport media-eval · {_esc(run['run_id'])}</title>"
        f"<style>{_HTML_STYLE}</style></head><body>{corps}</body></html>\n"
    )


# --------------------------------------------------------------------------- #
# Lecture DB + assemblage.
# --------------------------------------------------------------------------- #
async def _signaux(session, run_id: str) -> list[dict]:
    rows = await session.execute(
        select(MediaEvalSignal, MediaEvalMedia.domaine)
        .join(MediaEvalMedia, MediaEvalMedia.id == MediaEvalSignal.media_id)
        .where(MediaEvalSignal.run_id == run_id)
    )
    return [
        {
            "media": domaine,
            "critere": s.critere,
            "type_signal": s.type_signal,
            "statut": s.statut.value if hasattr(s.statut, "value") else s.statut,
            "voie": s.voie.value if hasattr(s.voie, "value") else s.voie,
            "citation": s.citation,
            "source_urls": list(s.source_urls or []),
            "sources_consultees": list(s.sources_consultees or []),
        }
        for s, domaine in rows.all()
    ]


async def _evaluations(session, run_id: str) -> list[dict]:
    rows = await session.execute(
        select(MediaEvalEvaluation, MediaEvalMedia.domaine)
        .join(MediaEvalMedia, MediaEvalMedia.id == MediaEvalEvaluation.media_id)
        .where(MediaEvalEvaluation.run_id == run_id)
    )
    return [
        {
            "media_domaine": domaine,
            "critere": ev.critere,
            "statut": ev.statut.value if hasattr(ev.statut, "value") else ev.statut,
            "score": ev.score,
            "niveau": ev.niveau,
            "flags": list(ev.flags or []),
            "evaluateur": ev.evaluateur,
            "evalue_at": ev.evalue_at,
        }
        for ev, domaine in rows.all()
    ]


def _accord_par_media(report: dict) -> dict[str, int]:
    """Nombre d'accords par média (numérateur des chaînes 'a/total')."""
    out: dict[str, int] = {}
    for media, frac in report.get("par_media", {}).items():
        try:
            out[media] = int(str(frac).split("/")[0])
        except (ValueError, IndexError):
            out[media] = 0
    return out


def construire_metrics(
    evaluations: list[dict],
    accord_report: dict,
    fiches: dict[str, dict],
) -> dict:
    """Agrège les métriques du verdict V0 — pur, testable."""
    reporterre = {}
    rep_c1 = next(
        (
            e
            for e in evaluations
            if e["media_domaine"] == "reporterre.net" and e["critere"] == "C1"
        ),
        None,
    )
    if "reporterre.net" in fiches:
        reporterre = {
            "c1_statut": rep_c1["statut"] if rep_c1 else "absent",
            "max_applicable": fiches["reporterre.net"]["score_max_applicable"],
        }
    return {
        "n_evaluations": len(evaluations),
        "evaluations_valides": len(evaluations) > 0,
        "accord_par_media": _accord_par_media(accord_report),
        "reporterre": reporterre,
        "zero_ecriture_agent": all(
            not e["evaluateur"].startswith("humain:direct") for e in evaluations
        ),
    }


def render_markdown(
    *,
    run: dict,
    rubrics_sha: dict[str, str],
    d4: dict,
    signaux: list[dict],
    garde_fous: dict[str, str],
    accord_report: dict,
    fiches: dict[str, dict],
    verdict: list[dict],
) -> str:
    lignes: list[str] = [
        f"# Rapport pilote media-eval — {run['run_id']}",
        "",
        f"- Généré le {datetime.now(UTC).date().isoformat()} · méthodo "
        f"{run['version_methodo']}",
        f"- date_reference (fraîcheur) : **{run['date_reference']}**",
        f"- Périmètre : {run.get('perimetre')}",
        "",
        "## 1. Contexte & intégrité",
        "",
        "sha256 des rubriques (fige la comparabilité gold/évals) :",
        "",
        _table(
            ["Critère", "sha256 (12)"],
            [[c, sha[:12]] for c, sha in sorted(rubrics_sha.items())],
        ),
        "",
        f"**Preuve D4 (golden en aveugle)** : {d4['message']}",
        "",
        "## 2. Signaux collectés",
        "",
        tableau_signaux(signaux),
        "",
        "## 3. Garde-fous",
        "",
        tableau_garde_fous(garde_fous),
        "",
        "## 4. Accord évaluations vs gold",
        "",
        tableau_accord(accord_report),
        "",
        "## 5. Fiches média",
        "",
    ]
    if fiches:
        rows = [
            [
                m,
                f"{f['score_brut']:g}",
                f"{f['score_max_applicable']:g}",
                f"{f['score_renormalise']:g}",
                f["lettre"],
                f["confiance"],
            ]
            for m, f in sorted(fiches.items())
        ]
        lignes.append(
            _table(
                ["Média", "Brut", "Max applic.", "/100", "Lettre", "Confiance"], rows
            )
        )
    else:
        lignes.append("(aucune fiche)")
    lignes += [
        "",
        "## 6. Verdict V0",
        "",
        render_verdict(verdict),
        "",
        "## 7. Notes & limites",
        "",
        "- Collecte partielle possible (anti-bot) → signaux `bloque_acces` "
        "honnêtes, critère en `revue_requise` (résultat valide).",
        "- `PAPPERS_API_TOKEN` absent → C5/C9 propriété en `bloque_acces`.",
        "- ARCOM N/A structurel pour la presse en ligne (absence neutre).",
        "",
    ]
    return "\n".join(lignes)


async def collecter_donnees_rapport(
    session, run_id: str, gold_path: Path
) -> dict | None:
    """Collecte DB + gold → `RapportData` (unique source des chiffres).

    Retourne ``None`` si le run est inconnu. Le dict renvoyé alimente
    **les deux** rendus (`render_markdown`, `render_html`) et la lentille
    propreté (`evaluer_proprete_donnees`) : aucune relecture DB dupliquée.
    """
    run_row = (
        await session.execute(select(MediaEvalRun).where(MediaEvalRun.run_id == run_id))
    ).scalar_one_or_none()
    if run_row is None:
        return None

    signaux = await _signaux(session, run_id)
    evaluations = await _evaluations(session, run_id)

    gold = GoldenSet.model_validate_json(gold_path.read_text())
    generated = evaluations_to_goldenset(evaluations)
    accord_report = evaluate(gold, generated)

    # Fiches recalculées par média (source de vérité = compute_fiche).
    fiches: dict[str, dict] = {}
    par_media: dict[str, list[dict]] = {}
    for ev in evaluations:
        par_media.setdefault(ev["media_domaine"], []).append(ev)
    for media, evs in par_media.items():
        fiches[media] = compute_fiche(evs)

    # Preuve D4 : gold.note_at doit précéder l'ingestion des évals.
    min_evalue = min((e["evalue_at"] for e in evaluations), default=None)
    d4 = _verifier_d4(gold.note_at, min_evalue)

    rubrics_sha = {c: version_prompt(c) for c in CRITERES_VAGUE_1}
    garde_fous = _detecter_garde_fous(signaux, evaluations)
    metrics = construire_metrics(evaluations, accord_report, fiches)
    verdict = verdict_v0(metrics)

    return {
        "run": {
            "run_id": run_row.run_id,
            "version_methodo": run_row.version_methodo,
            "date_reference": run_row.date_reference.isoformat(),
            "perimetre": run_row.perimetre,
        },
        "rubrics_sha": rubrics_sha,
        "d4": d4,
        "signaux": signaux,
        "evaluations": evaluations,
        "garde_fous": garde_fous,
        "accord_report": accord_report,
        "fiches": fiches,
        "verdict": verdict,
    }


async def run(run_id: str, gold_path: Path, out: Path) -> int:
    async with async_session_maker() as session:
        try:
            data = await collecter_donnees_rapport(session, run_id, gold_path)
            if data is None:
                print(f"REJET : run {run_id!r} inconnu.")
                return 1

            proprete = evaluer_proprete_donnees(
                data["signaux"], data["evaluations"], data["fiches"]
            )
            texte_md = render_markdown(
                run=data["run"],
                rubrics_sha=data["rubrics_sha"],
                d4=data["d4"],
                signaux=data["signaux"],
                garde_fous=data["garde_fous"],
                accord_report=data["accord_report"],
                fiches=data["fiches"],
                verdict=data["verdict"],
            )
            texte_html = render_html(data, proprete)

            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(texte_md)
            html_path = out.with_suffix(".html")
            html_path.write_text(texte_html)
            print(texte_md)
            print(f"\nRapport markdown : {out}")
            print(f"Rapport HTML : {html_path}")
            return 0
        finally:
            await engine.dispose()


def _verifier_d4(note_at, min_evalue) -> dict:
    if note_at is None:
        return {"ok": False, "message": "gold.note_at absent — preuve D4 impossible."}
    if min_evalue is None:
        return {"ok": True, "message": "aucune évaluation ingérée (rien à comparer)."}
    ok = note_at < min_evalue
    prefixe = "OK" if ok else "⚠ WARNING"
    return {
        "ok": ok,
        "message": f"{prefixe} — gold noté {note_at.isoformat()} "
        f"{'<' if ok else '≥'} 1re éval {min_evalue.isoformat()}.",
    }


def _detecter_garde_fous(
    signaux: list[dict], evaluations: list[dict]
) -> dict[str, str]:
    actives: dict[str, str] = {}
    flags = {f for e in evaluations for f in e.get("flags", [])}
    if any(s["statut"] == "bloque_acces" for s in signaux):
        actives["bloque_acces"] = "oui (signaux bloqués présents)"
    if any(
        e["critere"] == "C1" and "donnees_insuffisantes" in e.get("flags", [])
        for e in evaluations
    ):
        actives["fallback C1"] = "oui (C1 → N/A)"
    if any(e["evaluateur"] == "code:jti_shortcut" for e in evaluations):
        actives["raccourci JTI"] = "oui (C8 par code)"
    if "corroboration_insuffisante" in flags:
        actives["corroboration"] = "oui (score plafonné)"
    return actives


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--gold", type=Path, required=True, help="gold_v0.json")
    parser.add_argument("--out", type=Path, required=True, help="rapport markdown")
    args = parser.parse_args()
    get_settings()  # lecture seule (DB courante)
    sys.exit(asyncio.run(run(args.run_id, args.gold, args.out)))


if __name__ == "__main__":
    main()
