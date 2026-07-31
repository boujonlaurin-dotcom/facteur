# -*- coding: utf-8 -*-
"""Banc d'essai clustering — métriques B-cubed sur corpus annoté réel (2026-07-31).

Usage : python docs/qa/scripts/bench_clustering_bcubed.py
Pour valider la couche sémantique (§7.6 du bug doc) : remplacer `cos_idf` par une
matrice d'embeddings et viser B3 R > 0.70 a P >= 0.95.
"""
import importlib.util, json, math, os, re, sys
SC=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,SC)
s=importlib.util.spec_from_file_location("ts",os.path.join(SC,"..","..","..","packages","api","app","services","text_similarity.py")); ts=importlib.util.module_from_spec(s); s.loader.exec_module(ts)
nt, jac = ts.normalize_title, ts.jaccard_similarity
from clustering_corpus_ceuta_gironde import CEUTA, GIRONDE, NOISE
from clustering_corpus_trump import TRUMP
DF=json.load(open(os.path.join(SC,"clustering_df_20260731.json"))); N=2212

ART=[("CEUTA",d,t) for d,t in CEUTA]+[("GIRONDE",d,t) for d,t in GIRONDE]+list(TRUMP)
ART+=[("NOISE%d"%i,d,t) for i,(d,t) in enumerate(NOISE)]   # chaque bruit = sujet distinct
GOLD=[l for l,_,_ in ART]; DOM=[d for _,d,_ in ART]; TIT=[t for _,_,t in ART]
TOK=[nt(t) for t in TIT]
def idf(t): return math.log(N/max(DF.get(t,1),1))
def caps(title):
    body=re.sub(r'^[^:]{0,32}:','',title); out=set()
    for w in re.findall(r'\b[A-ZÉÈÀÂÎÔÛÇ][\wÀ-ÿ\-]{2,}', body):
        n=nt(w)
        if n: out|=n
    return out
CAPS=[caps(t) for t in TIT]

def cos_idf(i,j):
    inter=TOK[i]&TOK[j]
    if not inter: return 0.0
    num=sum(idf(t)**2 for t in inter)
    da=math.sqrt(sum(idf(t)**2 for t in TOK[i])); db=math.sqrt(sum(idf(t)**2 for t in TOK[j]))
    return num/(da*db) if da and db else 0.0

def bcubed(pred):
    """B-cubed P/R/F1 : standard d'évaluation du clustering d'événements."""
    c={}
    for i,p in enumerate(pred): c.setdefault(p,[]).append(i)
    g={}
    for i,l in enumerate(GOLD): g.setdefault(l,[]).append(i)
    P=R=0.0
    for i in range(len(ART)):
        ci=[x for x in c[pred[i]]]; gi=[x for x in g[GOLD[i]]]
        inter=len(set(ci)&set(gi))
        P+=inter/len(ci); R+=inter/len(gi)
    P/=len(ART); R/=len(ART)
    F=2*P*R/(P+R) if P+R else 0.0
    return P,R,F

def to_pred(clusters):
    pred=[None]*len(ART)
    for k,c in enumerate(clusters):
        for i in c: pred[i]=k
    return pred

# --- 1. Algo ACTUEL (glouton, sac fusionné, Jaccard 0.45) ---
def current():
    raw=[]
    for i,tk in enumerate(TOK):
        if not tk or len(tk)<3: raw.append([i]); continue
        best,bm=0.0,None
        for c in raw:
            bag=set()
            for j in c: bag|=TOK[j]
            if len(bag)>15: bag=set(sorted(bag)[:15])
            sim=jac(tk,bag)
            if sim>best and sim>=0.45: best,bm=sim,c
        (bm.append(i) if bm else raw.append([i]))
    return raw

# --- 2/3. Agglomératif (liaison moyenne / complète) sur une matrice de similarité ---
def agglo(simfn, th, linkage="average", constraint=None):
    clusters=[[i] for i in range(len(ART))]
    S={}
    for i in range(len(ART)):
        for j in range(i+1,len(ART)):
            S[(i,j)]=simfn(i,j)
    def sim(a,b):
        vals=[S[(min(x,y),max(x,y))] for x in a for y in b]
        if constraint and not any(constraint(x,y) for x in a for y in b): return -1.0
        return sum(vals)/len(vals) if linkage=="average" else min(vals)
    merged=True
    while merged:
        merged=False; best=th; pair=None
        for x in range(len(clusters)):
            for y in range(x+1,len(clusters)):
                v=sim(clusters[x],clusters[y])
                if v>=best: best=v; pair=(x,y)
        if pair:
            x,y=pair; clusters[x]=clusters[x]+clusters[y]; clusters.pop(y); merged=True
    return clusters

def anchor(i,j,maxdf=0.06):
    inter=TOK[i]&TOK[j]
    return any(DF.get(t,1)<=N*maxdf and (t in CAPS[i] or t in CAPS[j]) for t in inter)

def show(name, clusters):
    P,R,F=bcubed(to_pred(clusters))
    ce=max(clusters,key=lambda c:sum(1 for i in c if GOLD[i]=="CEUTA"))
    gi=max(clusters,key=lambda c:sum(1 for i in c if GOLD[i]=="GIRONDE"))
    nce=len({DOM[i] for i in ce if GOLD[i]=="CEUTA"}); ngi=len({DOM[i] for i in gi if GOLD[i]=="GIRONDE"})
    mixtes=sum(1 for c in clusters if len({GOLD[i] for i in c})>1)
    print(f"  {name:<46} B³ P={P:.2f} R={R:.2f} F1={F:.2f} | Ceuta {nce:>2} méd. | Gironde {ngi} méd. | {mixtes} mixtes")

print("="*104)
print(f"BANC D'ESSAI — {len(ART)} articles réels, 6 sujets annotés + 10 bruits distincts")
print("B³ = métrique standard de clustering d'événements (P=pureté, R=complétude)")
print("="*104)
show("ACTUEL (Jaccard 0.45, glouton, sac fusionné)", current())
for th in (0.35,0.30,0.25):
    show(f"Jaccard {th}, agglomératif liaison moyenne", agglo(lambda i,j: jac(TOK[i],TOK[j]), th))
for th in (0.40,0.35,0.30,0.25,0.20):
    show(f"Cosinus IDF {th}, liaison moyenne", agglo(cos_idf, th))
for th in (0.30,0.25,0.20):
    show(f"Cosinus IDF {th} + ancre obligatoire", agglo(cos_idf, th, constraint=anchor))
