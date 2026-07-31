"""Cœur de regroupement d'articles par sujet.

Remplace le clustering historique (Jaccard glouton contre un sac de tokens
fusionné) par un **cosinus pondéré IDF** + **agglomératif à liaison par centroïde**.

Pourquoi (cf. `docs/bugs/bug-clustering-actus-du-jour-fragmentation.md`) :

- Jaccard traite « ceuta » et « avec » comme également informatifs, et sa
  normalisation par l'union pénalise les titres longs. Avec 8,4 tokens utiles
  par titre, franchir 0.45 exigeait 5 à 6 mots identiques sur 8 — 84 % des
  articles n'avaient aucun voisin éligible. L'IDF donne son poids à ce qui
  identifie l'événement et ignore le remplissage.
- Comparer un candidat au **sac fusionné** du cluster faisait grossir l'union
  à chaque ajout, donc chuter la similarité : le cluster se refermait après
  2 articles. Le centroïde d'un cluster ne se dilue pas quand il grossit.
- La liaison **par centroïde** (et non simple) limite le chaînage : deux sujets
  reliés par un seul article ambigu ne fusionnent pas pour autant.

Mesuré sur 24 h de production (2 214 articles, sujets couverts par ≥ 3 médias) :
32 sujets avec Jaccard 0.45 → **79** avec ce module.

Ce module ne connaît ni SQLAlchemy ni le modèle `Content` : il travaille sur des
ensembles de tokens et rend des groupes d'indices, ce qui le rend testable et
réutilisable (digest, Essentiel, carrousels).
"""

import heapq
import math

# Un token présent dans plus de MAX_DF_RATIO du corpus n'identifie plus un
# sujet (« france », « video »…). On l'écarte du vecteur — mais seulement
# quand le corpus est assez grand pour que la fréquence ait un sens.
MAX_DF_RATIO = 0.4
MIN_CORPUS_FOR_DF_CAP = 50


def compute_idf(token_sets: list[set[str]]) -> dict[str, float]:
    """IDF lissé : `ln((1 + N) / (1 + df)) + 1`.

    Le lissage garantit un poids strictement positif même quand un token est
    présent dans tous les documents — sans lui, un corpus de test où deux
    titres sont identiques produirait des vecteurs nuls.
    """
    n = len(token_sets)
    df: dict[str, int] = {}
    for tokens in token_sets:
        for token in tokens:
            df[token] = df.get(token, 0) + 1
    return {t: math.log((1 + n) / (1 + d)) + 1 for t, d in df.items()}


def build_vectors(
    token_sets: list[set[str]], idf: dict[str, float]
) -> list[dict[str, float]]:
    """Vecteurs creux normalisés L2, pour que le cosinus soit un simple produit."""
    n = len(token_sets)
    df_cap: float | None = None
    if n >= MIN_CORPUS_FOR_DF_CAP:
        df_cap = math.log((1 + n) / (1 + MAX_DF_RATIO * n)) + 1

    vectors: list[dict[str, float]] = []
    for tokens in token_sets:
        weights = {
            t: idf[t] for t in tokens if df_cap is None or idf.get(t, 0.0) >= df_cap
        }
        norm = math.sqrt(sum(w * w for w in weights.values()))
        vectors.append({t: w / norm for t, w in weights.items()} if norm > 0 else {})
    return vectors


def _agglomerate(vectors: list[dict[str, float]], threshold: float) -> list[list[int]]:
    """Agglomératif à **liaison par centroïde**, le standard du clustering d'actualité.

    Chaque cluster est résumé par la somme (non normalisée) des vecteurs de ses
    membres ; la similarité entre deux clusters est le cosinus entre ces
    centroïdes. C'est ce qui corrige le défaut historique : un cluster qui
    grossit ne devient pas mécaniquement moins attractif — contrairement au
    Jaccard contre un sac de tokens fusionné, dont l'union enflait à chaque
    ajout, et contrairement à une liaison moyenne sur graphe creux, où les
    paires sous le seuil comptent pour 0 et referment le cluster de la même façon.

    Les paires candidates viennent d'un index inversé : seuls les clusters
    partageant au moins un token sont comparés, ce qui évite le O(n²).
    """
    size = len(vectors)
    csum: dict[int, dict[str, float]] = {i: dict(vectors[i]) for i in range(size)}
    cnorm: dict[int, float] = {
        i: math.sqrt(sum(w * w for w in vectors[i].values())) for i in range(size)
    }
    members: dict[int, list[int]] = {i: [i] for i in range(size)}
    version: dict[int, int] = dict.fromkeys(range(size), 0)

    postings: dict[str, set[int]] = {}
    for i, vec in enumerate(vectors):
        for token in vec:
            postings.setdefault(token, set()).add(i)

    def similarity(a: int, b: int) -> float:
        if not cnorm[a] or not cnorm[b]:
            return 0.0
        small, large = (a, b) if len(csum[a]) <= len(csum[b]) else (b, a)
        dot = sum(w * csum[large].get(t, 0.0) for t, w in csum[small].items())
        return dot / (cnorm[a] * cnorm[b])

    heap: list[tuple[float, int, int, int, int]] = []

    def push_pairs(a: int) -> None:
        candidates: set[int] = set()
        for token in csum[a]:
            candidates |= postings.get(token, set())
        candidates.discard(a)
        for b in candidates:
            s = similarity(a, b)
            if s >= threshold:
                heapq.heappush(heap, (-s, a, b, version[a], version[b]))

    for i in range(size):
        push_pairs(i)

    alive = set(range(size))
    while heap:
        neg_sim, a, b, va, vb = heapq.heappop(heap)
        if a not in alive or b not in alive:
            continue
        if version[a] != va or version[b] != vb:
            continue  # entrée périmée : un des deux clusters a fusionné depuis
        if -neg_sim < threshold:
            break

        # Fusion de b dans a.
        for token, w in csum[b].items():
            csum[a][token] = csum[a].get(token, 0.0) + w
            postings.setdefault(token, set()).add(a)
            postings[token].discard(b)
        cnorm[a] = math.sqrt(sum(w * w for w in csum[a].values()))
        members[a].extend(members[b])
        version[a] += 1
        alive.discard(b)
        del csum[b], members[b]

        push_pairs(a)

    return [members[i] for i in sorted(alive)]


def cluster_documents(
    token_sets: list[set[str]],
    threshold: float,
    min_tokens: int = 3,
) -> list[list[int]]:
    """Regroupe des documents par sujet et rend des groupes d'indices.

    Args:
        token_sets: tokens normalisés de chaque document (même ordre en sortie).
        threshold: seuil de cosinus IDF (liaison par centroïde) pour fusionner.
        min_tokens: en dessous, le titre est trop court pour être regroupé de
            façon fiable — le document reste un singleton.

    Returns:
        Liste de groupes d'indices. Tout document apparaît exactement une fois.
    """
    if not token_sets:
        return []

    # Les titres trop courts sont écartés du calcul mais restaurés en singletons.
    eligible = [i for i, t in enumerate(token_sets) if len(t) >= min_tokens]
    singletons = [[i] for i, t in enumerate(token_sets) if len(t) < min_tokens]
    if not eligible:
        return singletons

    sub_sets = [token_sets[i] for i in eligible]
    idf = compute_idf(sub_sets)
    vectors = build_vectors(sub_sets, idf)
    groups = _agglomerate(vectors, threshold)

    return [[eligible[k] for k in g] for g in groups] + singletons
