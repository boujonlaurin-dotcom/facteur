# -*- coding: utf-8 -*-
"""Mesure avant/après du clustering sur le CODE LIVRÉ, chemin éditorial et chemin topics.

Contrairement à `bench_clustering_bcubed.py` (qui réimplémente un cosinus IDF et
une liaison *moyenne*), ce banc importe le module de production
`app/services/briefing/topic_clustering.py` tel quel — IDF lissé, plafond de DF,
liaison par centroïde — et rejoue l'algorithme *antérieur* (Jaccard glouton
contre sac fusionné) à l'identique, extrait de `beac381e`.

Il mesure le KPI produit — nombre de sujets couverts par >= 3 médias distincts —
sur les deux pools qui existent réellement en production :

  * `editorial`  : le pool que voit la pipeline éditoriale (`digest_generation_job
    ._get_global_candidates`) = 200 articles les plus récents + tranche sources
    suivies, fenêtre 48 h. C'est le SEUL chemin emprunté par le digest.
  * `corpus24h`  : le corpus complet 24 h, borne haute théorique.

Usage : python3.12 docs/qa/scripts/verify_clustering_prod_paths.py <corpus.json>

Le corpus attendu est une liste JSON d'objets {p: published_at ISO, d: domaine,
s: préfixe source_id, a: type de source, t: titre}, extraite de production.
"""

import importlib.util
import json
import os
import re
import sys

SC = os.path.dirname(os.path.abspath(__file__))
API = os.path.join(SC, "..", "..", "..", "packages", "api", "app", "services")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Code de production importé tel quel — aucune réimplémentation.
ts = _load("text_similarity", os.path.join(API, "text_similarity.py"))
tc = _load("topic_clustering", os.path.join(API, "briefing", "topic_clustering.py"))
normalize_title, jaccard = ts.normalize_title, ts.jaccard_similarity

MIN_TOKENS = 3
MAX_TOKENS = 15  # ScoringWeights.TOPIC_CLUSTER_MAX_TOKENS, supprimée par le correctif
AGGREGATOR_TYPES = {"reddit"}
FOLLOWED = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else set()


# --------------------------------------------------------------------------
# Algorithme ANTÉRIEUR — copie fidèle de importance_detector.build_topic_clusters
# à beac381e (glouton, une passe, Jaccard contre le sac de tokens fusionné).
# --------------------------------------------------------------------------
def cluster_before(token_sets, threshold):
    raw = []
    for i, tokens in enumerate(token_sets):
        if not tokens:
            continue
        if len(tokens) < MIN_TOKENS:
            raw.append({"tokens": set(tokens), "idx": [i]})
            continue
        matched, best = None, 0.0
        for c in raw:
            sim = jaccard(tokens, c["tokens"])
            if sim > best and sim >= threshold:
                best, matched = sim, c
        if matched:
            matched["idx"].append(i)
            merged = matched["tokens"] | tokens
            if len(merged) <= MAX_TOKENS:
                matched["tokens"] = merged
        else:
            raw.append({"tokens": set(tokens), "idx": [i]})
    return [c["idx"] for c in raw]


def cluster_after(token_sets, threshold):
    """Code livré, appelé directement."""
    return tc.cluster_documents(token_sets, threshold=threshold, min_tokens=MIN_TOKENS)


# --------------------------------------------------------------------------
# Phase 2 métier : fold agrégateurs + décompte de domaines (identique aux deux)
# --------------------------------------------------------------------------
def domains_of(group, rows):
    primary = {rows[i]["d"] for i in group if rows[i]["a"] not in AGGREGATOR_TYPES}
    agg = {rows[i]["d"] for i in group if rows[i]["a"] in AGGREGATOR_TYPES}
    return primary or agg


def metrics(groups, rows):
    doms = [domains_of(g, rows) for g in groups]
    sizes = [len(g) for g in groups]
    n = sum(sizes)
    biggest = max(range(len(groups)), key=lambda k: len(doms[k])) if groups else None
    return {
        "articles": n,
        "clusters": len(groups),
        "topics_3plus_media": sum(1 for d in doms if len(d) >= 3),
        "topics_5plus_media": sum(1 for d in doms if len(d) >= 5),
        "multi_article": sum(1 for s in sizes if s >= 2),
        "singleton_rate": round(100.0 * sum(1 for s in sizes if s == 1) / n, 1)
        if n
        else 0.0,
        "grouped_rate": round(100.0 * sum(s for s in sizes if s >= 2) / n, 1)
        if n
        else 0.0,
        "max_media": max((len(d) for d in doms), default=0),
        "max_articles": max(sizes, default=0),
        "_groups": groups,
        "_doms": doms,
        "_biggest": biggest,
    }


def topic_media(groups, rows, needle):
    """Meilleur cluster contenant `needle` : (articles, médias)."""
    best = (0, 0)
    for g in groups:
        hits = [i for i in g if needle in rows[i]["t"].lower()]
        if not hits:
            continue
        d = len({rows[i]["d"] for i in hits})
        if d > best[1] or (d == best[1] and len(hits) > best[0]):
            best = (len(hits), d)
    return best


# --------------------------------------------------------------------------
# Reconstruction des pools de production
# --------------------------------------------------------------------------
def editorial_pool(rows, gen, lookback_h=48, cap=200, followed_cap=200):
    """Réplique digest_generation_job._get_global_candidates."""
    lo = gen - lookback_h * 3600
    win = [r for r in rows if lo <= r["_ts"] <= gen]
    win.sort(key=lambda r: r["_ts"], reverse=True)
    recency = win[:cap]
    seen = {id(r) for r in recency}
    if FOLLOWED:
        fol = [r for r in win if r["s"] in FOLLOWED][:followed_cap]
        return recency + [r for r in fol if id(r) not in seen]
    return recency


def corpus_window(rows, gen, hours):
    lo = gen - hours * 3600
    return [r for r in rows if lo <= r["_ts"] <= gen]


# Gabarits de bulletins/chroniques — miroir de `NEWS_BULLETIN_PATTERNS`, restreint
# aux formes présentes dans le corpus mesuré. Sert à simuler `drop_unclusterable`.
_BULLETIN = re.compile(
    r"^\s*(journal de \d{1,2}\s?h|le journal\b|journal (rtl|rfi|bfm|europe|france)\b"
    r"|revue de presse\b|les titres\b|jt (de|du)\b|flash (info|actu)\b)",
    re.I,
)


def editorial_pool_v2(rows, gen, window_h=24, cap=6000, min_pool=200, fallback_h=48):
    """Réplique la politique de `editorial/candidate_pool.py` après correctif.

    Tout le corpus de la fenêtre, sans plafond top-N, sans article post-daté,
    sans bulletin. Le plafond historique de 200 devient un plancher.
    """

    def _slice(hours):
        lo = gen - hours * 3600
        win = [r for r in rows if lo <= r["_ts"] <= gen]
        win.sort(key=lambda r: r["_ts"], reverse=True)
        return win[:cap]

    pool = _slice(window_h)
    if len(pool) < min_pool:
        pool = _slice(fallback_h)
    return [r for r in pool if not _BULLETIN.match(r["t"])]


def run(label, rows):
    tokens = [normalize_title(r["t"]) for r in rows]
    out = {}
    for name, groups in (
        (
            "AVANT  Jaccard 0.40 glouton (défaut prod réel)",
            cluster_before(tokens, 0.40),
        ),
        ("AVANT  Jaccard 0.45 glouton (chemin topics)", cluster_before(tokens, 0.45)),
        ("APRÈS  cosinus IDF 0.30 centroïde (livré)", cluster_after(tokens, 0.30)),
    ):
        m = metrics(groups, rows)
        out[name] = m
    print(f"\n### {label} — {len(rows)} articles, {len({r['d'] for r in rows})} médias")
    hdr = f"  {'variante':<46} {'sujets>=3méd':>12} {'>=5méd':>7} {'groupés%':>9} {'maxméd':>7} {'maxart':>7}"
    print(hdr)
    for name, m in out.items():
        print(
            f"  {name:<46} {m['topics_3plus_media']:>12} {m['topics_5plus_media']:>7} "
            f"{m['grouped_rate']:>8}% {m['max_media']:>7} {m['max_articles']:>7}"
        )
    for needle in ("ceuta", "gironde"):
        line = f"  sujet « {needle} » (art./méd.)".ljust(48)
        for name, m in out.items():
            a, d = topic_media(m["_groups"], rows, needle)
            line += f"{a}/{d}".rjust(13)
        print(line)
    return out


def chaining_audit(m, rows, top=5):
    """Inspection des plus gros clusters : détection de chaînage à l'œil nu."""
    order = sorted(
        range(len(m["_groups"])), key=lambda k: len(m["_groups"][k]), reverse=True
    )
    for k in order[:top]:
        g = m["_groups"][k]
        print(f"\n  -- cluster {len(g)} art. / {len(m['_doms'][k])} médias --")
        for i in g[:14]:
            print(f"     [{rows[i]['d']:<28}] {rows[i]['t'][:96]}")
        if len(g) > 14:
            print(f"     ... +{len(g) - 14} autres")


def main():
    import datetime as dt

    rows = json.load(open(sys.argv[1], encoding="utf-8"))
    for r in rows:
        r["_ts"] = dt.datetime.fromisoformat(r["p"]).replace(tzinfo=dt.UTC).timestamp()
    gen = dt.datetime(2026, 7, 31, 5, 0, tzinfo=dt.UTC).timestamp()  # cron 07:00 Paris

    print("=" * 118)
    print(
        "CLUSTERING — MESURE AVANT/APRÈS SUR LE CODE LIVRÉ (topic_clustering.py importé)"
    )
    print("Génération simulée : 2026-07-31 05:00 UTC (cron 07:00 Paris)")
    print(
        "KPI = nombre de sujets couverts par >= 3 médias distincts (après fold agrégateurs)"
    )
    print("=" * 118)

    pool = editorial_pool(rows, gen)
    run("CHEMIN ÉDITORIAL — AVANT correctif : pool plafonné à 200 par récence", pool)

    pool2 = editorial_pool_v2(rows, gen)
    after = run(
        "CHEMIN ÉDITORIAL — APRÈS correctif : corpus complet de la fenêtre", pool2
    )

    c24 = corpus_window(rows, gen, 24)
    run("CORPUS COMPLET 24 h — référence non filtrée", c24)

    print("\n### Couverture du pool éditorial")
    for label, p in (("AVANT", pool), ("APRÈS", pool2)):
        span = (max(r["_ts"] for r in p) - min(r["_ts"] for r in p)) / 3600
        print(
            f"  {label} : {len(p):>5} articles | {len({r['d'] for r in p}):>3} médias | "
            f"{100.0 * len(p) / len(c24):>5.1f} % du corpus 24 h | fenêtre {span:.1f} h"
        )

    print("\n" + "=" * 118)
    print("AUDIT DE CHAÎNAGE — plus gros clusters vus par le digest APRÈS correctif")
    print("=" * 118)
    chaining_audit(after["APRÈS  cosinus IDF 0.30 centroïde (livré)"], pool2)


if __name__ == "__main__":
    main()
