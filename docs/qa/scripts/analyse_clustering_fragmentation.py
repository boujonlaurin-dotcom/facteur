# -*- coding: utf-8 -*-
"""Reproduit le diagnostic de bug-clustering-actus-du-jour-fragmentation.md.

Corpus réel extrait de production le 2026-07-31 (fenêtre 24 h).
Compare l'algorithme actuel (ImportanceDetector.build_topic_clusters) aux
variantes candidates, sur un jeu où l'on veut REGROUPER Ceuta et Gironde tout
en SÉPARANT les 4 sujets distincts qui mentionnent tous « Trump ».

Usage :  cd packages/api && python ../../docs/qa/scripts/analyse_clustering_fragmentation.py
"""
import importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.path.join(HERE, "..", "..", "..", "packages", "api")
sys.path.insert(0, HERE)

s = importlib.util.spec_from_file_location(
    "ts", os.path.join(API, "app", "services", "text_similarity.py"))
ts = importlib.util.module_from_spec(s); s.loader.exec_module(ts)
nt, jac = ts.normalize_title, ts.jaccard_similarity

from clustering_corpus_ceuta_gironde import CEUTA, GIRONDE, NOISE
from clustering_corpus_trump import TRUMP

DF = json.load(open(os.path.join(HERE, "clustering_df_20260731.json")))
N = 2212  # articles publiés sur la fenêtre 24 h analysée

ART=[("CEUTA",d,t) for d,t in CEUTA]+[("GIRONDE",d,t) for d,t in GIRONDE]+list(TRUMP)+[("NOISE",d,t) for d,t in NOISE]
TOK=[nt(t) for _,_,t in ART]; LAB=[l for l,_,_ in ART]; DOM=[d for _,d,_ in ART]
def caps(title):
    body=re.sub(r'^[^:]{0,32}:','',title)
    out=set()
    for w in re.findall(r'\b[A-ZÉÈÀÂÎÔÛÇ][\wÀ-ÿ\-]{2,}', body):
        n=nt(w)
        if n: out|=n
    return out
CAPS=[caps(t) for _,_,t in ART]
BIG={l for l in LAB}

def greedy(link):
    raw=[]
    for i,tk in enumerate(TOK):
        if not tk: raw.append([i]); continue
        hit=None
        for c in raw:
            if any(link(i,j) for j in c): hit=c; break
        (hit.append(i) if hit else raw.append([i]))
    return raw

def rule_current(th=0.45):
    raw=[]
    for i,tk in enumerate(TOK):
        if not tk or len(tk)<3: raw.append([i]); continue
        best,bm=0.0,None
        for c in raw:
            bag=set()
            for j in c: bag|=TOK[j]
            if len(bag)>15: bag=set(list(bag)[:15])
            sim=jac(tk,bag)
            if sim>best and sim>=th: best,bm=sim,c
        (bm.append(i) if bm else raw.append([i]))
    return raw

def anchors(i,j,maxdf):
    inter=TOK[i]&TOK[j]
    return [t for t in inter if DF.get(t,1)<=N*maxdf and (t in CAPS[i] or t in CAPS[j])]

def report(name, raw):
    # rappel : plus gros cluster par sujet réel
    rec={}
    for lab in ("CEUTA","GIRONDE","GAZA","UKRAINE","IRAN"):
        tot=sum(1 for l in LAB if l==lab)
        if not tot: continue
        best=max(raw,key=lambda c:sum(1 for i in c if LAB[i]==lab))
        n=sum(1 for i in best if LAB[i]==lab); d=len({DOM[i] for i in best if LAB[i]==lab})
        rec[lab]=(n,tot,d)
    # precision : clusters melangeant >=2 sujets reels distincts (hors NOISE isole)
    fusions=[c for c in raw if len({LAB[i] for i in c})>1]
    worst=max((len({LAB[i] for i in c}) for c in raw), default=1)
    line=" ".join(f"{k}:{v[0]}/{v[1]}({v[2]}d)" for k,v in rec.items())
    trend=sum(1 for c in raw if len({DOM[i] for i in c})>=3)
    print(f"  {name:<42} {line}")
    print(f"  {'':<42} -> {len(raw):>2} clusters | {trend} trending(>=3dom) | {len(fusions)} clusters mixtes | pire fusion: {worst} sujets")

print("="*112)
print(f"TEST DÉCISIF — {len(ART)} articles réels : Ceuta(21) + Gironde(8) + Trump 4 sujets distincts(24) + bruit(10)")
print("Objectif : REGROUPER Ceuta et Gironde, tout en SÉPARANT Gaza / Ukraine / Iran (tous 'Trump').")
print("="*112)
report("A. ACTUEL (Jaccard 0.45, sac fusionné)", rule_current())
report("B. Ancre nom propre seule (df<=6%)", greedy(lambda i,j: bool(anchors(i,j,0.06))))
report("C. Ancre + >=2 ancres partagées", greedy(lambda i,j: len(anchors(i,j,0.06))>=2))
for jt in (0.15,0.20,0.25):
    report(f"D. Ancre + Jaccard >= {jt}", greedy(lambda i,j,jt=jt: bool(anchors(i,j,0.06)) and jac(TOK[i],TOK[j])>=jt))
for jt in (0.15,0.20):
    report(f"E. Ancre + (2 ancres OU Jaccard>={jt})", greedy(lambda i,j,jt=jt: len(anchors(i,j,0.06))>=2 or (bool(anchors(i,j,0.06)) and jac(TOK[i],TOK[j])>=jt)))
