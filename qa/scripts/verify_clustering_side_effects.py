# -*- coding: utf-8 -*-
"""Effets de bord et sensibilité du clustering livré, sur corpus de production complet.

Complète `verify_clustering_prod_paths.py` :

  1. robustesse du gain selon l'heure de génération (le pool éditorial dépend du débit) ;
  2. sensibilité au seuil, mesurée sur 2 300 articles et non sur le corpus annoté de 63 ;
  3. rayon d'action de `is_trending` (combien d'articles deviennent trending) ;
  4. fragmentation résiduelle d'un sujet donné (combien de clusters le portent) ;
  5. clusters « boilerplate » (journaux radio, programmes TV) qui gonflent le KPI.

Usage : python3.12 docs/qa/scripts/verify_clustering_side_effects.py <corpus.json> [followed_ids]
"""

import datetime as dt
import importlib.util
import json
import os
import re
import sys

SC = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "v", os.path.join(SC, "verify_clustering_prod_paths.py")
)
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

# Titres structurellement non-clusterisables : journaux radio horaires, grilles TV,
# podcasts quotidiens. Ils partagent un gabarit, pas un sujet.
BOILERPLATE = re.compile(
    r"journal (rtl|de \d|d'information)|journal de \d+h|^journal de|"
    r"ce soir à la télé|programme tv|revue de presse|"
    r"l'invité de|le \d+h de|édition de \d+h",
    re.I,
)


def is_boilerplate_cluster(group, rows, ratio=0.6):
    hits = sum(1 for i in group if BOILERPLATE.search(rows[i]["t"]))
    return len(group) >= 3 and hits / len(group) >= ratio


def kpi(groups, rows):
    doms = [v.domains_of(g, rows) for g in groups]
    total = sum(1 for d in doms if len(d) >= 3)
    junk = sum(
        1
        for k, g in enumerate(groups)
        if len(doms[k]) >= 3 and is_boilerplate_cluster(g, rows)
    )
    trending_articles = sum(len(g) for k, g in enumerate(groups) if len(doms[k]) >= 3)
    return total, junk, trending_articles


def fragmentation(groups, rows, needle):
    return sum(1 for g in groups if any(needle in rows[i]["t"].lower() for i in g))


def llm_input_view(rows, threshold, limit=15):
    """Les `limit` clusters que la curation LLM voit réellement.

    `curation.select_topics` trie par nombre de médias et tronque à
    `cluster_input_limit` (15). C'est donc CE classement — pas le KPI global —
    qui détermine ce que l'utilisateur lit. Le digest en retient 5.
    """
    tk = [v.normalize_title(r["t"]) for r in rows]
    g = v.cluster_after(tk, threshold)
    m = v.metrics(g, rows)
    order = sorted(
        range(len(g)), key=lambda k: (len(m["_doms"][k]), len(g[k])), reverse=True
    )
    return [(len(m["_doms"][k]), len(g[k]), rows[g[k][0]]["t"]) for k in order[:limit]]


def main():
    rows = json.load(open(sys.argv[1], encoding="utf-8"))
    if len(sys.argv) > 2:
        v.FOLLOWED = set(sys.argv[2].split(","))
    for r in rows:
        r["_ts"] = dt.datetime.fromisoformat(r["p"]).replace(tzinfo=dt.UTC).timestamp()

    base = dt.datetime(2026, 7, 31, 5, 0, tzinfo=dt.UTC).timestamp()

    print("=" * 112)
    print("0. CE QUE LA CURATION LLM VOIT — top 15 clusters (cluster_input_limit),")
    print("   dont elle retient 5 pour le digest. C'est la vue produit.")
    print("=" * 112)
    for label, pool in (
        ("AVANT correctif — pool plafonné à 200", v.editorial_pool(rows, base)),
        ("APRÈS correctif — corpus de la fenêtre", v.editorial_pool_v2(rows, base)),
    ):
        print(f"\n  {label} ({len(pool)} articles) :")
        for i, (d, a, title) in enumerate(llm_input_view(pool, 0.30), 1):
            print(f"    {i:>2}. [{d:>2} méd. / {a:>2} art.] {title[:84]}")

    print("\n" + "=" * 112)
    print(
        "1. ROBUSTESSE — sujets >= 3 médias vus par le digest, selon l'heure de génération"
    )
    print("   (algorithme identique des deux côtés : seul le pool change)")
    print("=" * 112)
    print(
        f"  {'heure':<8}{'pool AVANT':>11}{'méd.':>6}{'fenêtre':>9}{'KPI':>6}"
        f"{'  |':>3}{'pool APRÈS':>11}{'méd.':>6}{'fenêtre':>9}{'KPI':>6}{'gain':>7}"
    )
    for h in (5, 8, 11, 14, 17, 20):
        gen = dt.datetime(2026, 7, 31, h, 0, tzinfo=dt.UTC).timestamp()
        if gen > max(r["_ts"] for r in rows if r["p"] <= "2026-08-01T00:01"):
            continue
        old, new = v.editorial_pool(rows, gen), v.editorial_pool_v2(rows, gen)
        if len(old) < 50:
            continue
        cells = []
        for pool in (old, new):
            tk = [v.normalize_title(r["t"]) for r in pool]
            k, _, _ = kpi(v.cluster_after(tk, 0.30), pool)
            span = (max(r["_ts"] for r in pool) - min(r["_ts"] for r in pool)) / 3600
            cells.append((len(pool), len({r["d"] for r in pool}), span, k))
        (n1, m1, s1, k1), (n2, m2, s2, k2) = cells
        print(
            f"  {h:02d}:00{'':<3}{n1:>11}{m1:>6}{s1:>8.1f}h{k1:>6}{'  |':>3}"
            f"{n2:>11}{m2:>6}{s2:>8.1f}h{k2:>6}{f'x{k2 / max(k1, 1):.0f}':>7}"
        )

    c24 = v.corpus_window(rows, base, 24)
    tk24 = [v.normalize_title(r["t"]) for r in c24]

    print("\n" + "=" * 112)
    print(f"2. SENSIBILITÉ AU SEUIL — corpus complet 24 h ({len(c24)} articles),")
    print("   et non le corpus annoté de 63 articles ayant servi à calibrer")
    print("=" * 112)
    print(
        f"  {'seuil':<9}{'sujets>=3méd':>14}{'dont boilerplate':>19}"
        f"{'art. trending':>15}{'ceuta méd.':>12}{'gironde méd.':>14}{'max art.':>10}"
    )
    for th in (0.22, 0.25, 0.28, 0.30, 0.32, 0.35, 0.40):
        g = v.cluster_after(tk24, th)
        total, junk, tart = kpi(g, c24)
        _, cd = v.topic_media(g, c24, "ceuta")
        _, gd = v.topic_media(g, c24, "gironde")
        mx = max(len(x) for x in g)
        star = "  <-- livré" if abs(th - 0.30) < 1e-9 else ""
        print(f"  {th:<9}{total:>14}{junk:>19}{tart:>15}{cd:>12}{gd:>14}{mx:>10}{star}")

    print("\n" + "=" * 112)
    print("3. RAYON D'ACTION DE is_trending — corpus 24 h complet")
    print("   (`DigestSelector._build_global_trending_context`, calculé chaque batch)")
    print("=" * 112)
    for name, th, fn in (
        ("AVANT  Jaccard 0.40", 0.40, v.cluster_before),
        ("APRÈS  cosinus 0.30", 0.30, v.cluster_after),
    ):
        g = fn(tk24, th)
        total, junk, tart = kpi(g, c24)
        print(
            f"  {name:<22} sujets>=3méd={total:>4}   articles marqués trending="
            f"{tart:>5} ({100.0 * tart / len(c24):.1f} % du corpus)"
        )

    print("\n" + "=" * 112)
    print("4. FRAGMENTATION RÉSIDUELLE — nombre de clusters distincts portant le sujet")
    print("=" * 112)
    for name, th, fn in (
        ("AVANT  Jaccard 0.40", 0.40, v.cluster_before),
        ("APRÈS  cosinus 0.30", 0.30, v.cluster_after),
    ):
        g = fn(tk24, th)
        parts = "   ".join(
            f"{n}={fragmentation(g, c24, n)}" for n in ("gironde", "ceuta", "incendie")
        )
        print(f"  {name:<22} {parts}")


if __name__ == "__main__":
    main()
