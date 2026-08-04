"""Dérive **8 personas de scoring** d'un dump de comptes réels, pour le harnais
de tuning (cf. `docs/maintenance/maintenance-scoring-tuning-harness.md`).

Les personas fournissent le *contexte utilisateur* (`ScoringContext`) que
`evaluate_scoring_personas.py` croise avec le corpus gelé de
`build_scoring_corpus.py`. Ils remplacent les faux profils écrits à la main :
un persona inventé mesure l'intuition de celui qui l'a écrit, pas la prod.

### Pourquoi `--raw` et pas une lecture directe

Convention de `build_event_dataset.py` : **ce script ne touche jamais la DB**.
Le rôle `claude_analytics_ro` a bien le SELECT sur `contents` / `sources` (d'où
la lecture directe dans `build_scoring_corpus.py`) mais il est **refusé sur
toutes les tables `user_*`** (`permission denied for table user_interests`).
Le seul chemin autorisé est donc le MCP Supabase (rôle `postgres`), et le dump
atterrit dans `.context/` — non versionné.

Le SQL du dump vit dans `PERSONA_DUMP_SQL` ci-dessous : il est la source de
vérité du format d'entrée, et il est **tenu aligné sur la construction de
contexte de la prod** (`digest_selector._build_digest_context`).

### Clustering — stdlib uniquement, et pourquoi

`numpy` **n'est pas** une dépendance de `packages/api/requirements.txt` (il
n'existe que dans `requirements-ml.txt`, commenté). Le harnais et ses tests
doivent tourner en CI ⇒ k-medoids écrit à la main sur 5 features et ~60 points,
ce qui est trivial. **Zéro `random`** : seeding farthest-point depuis le
centroïde global, égalités tranchées par l'ordre des `user_key` ⇒ le même dump
redonne exactement les mêmes personas.

k-medoids et non k-means : un médoïde **est** un compte réel, donc un contexte
de scoring cohérent. Un centroïde k-means serait un profil moyen qui n'existe
pas — 4,3 thèmes suivis et 0,7 sujet, dont le scoring ne veut rien dire.

### Anonymisation

Les personas sortent en `persona_01…persona_08` : aucun `user_id`, aucun email,
aucun `display_name`. Les `source_id` et slugs de thèmes/sujets sont en revanche
**conservés** : ce sont des identifiants de catalogue partagés par tous les
comptes, pas des données personnelles, et le scoring en dépend entièrement.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/build_persona_dataset.py \\
        --raw ../../.context/persona-raw-2026-08-03.json \\
        --out tests/fixtures/scoring_personas.json

Sortie :
    packages/api/tests/fixtures/scoring_personas.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import statistics
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
DATASET_KIND = "scoring_personas"

# Nombre de clusters. 6 + 2 extrêmes délibérés = 8 personas, soit ~240 candidats
# labellisables — à comparer aux 113 constantes de `ScoringWeights`. Monter k
# n'achèterait pas de pouvoir statistique, ça diluerait le temps de revue.
DEFAULT_K = 6

# Plafond de `user_interests.weight` en prod. Le persona « vétéran » est celui
# qui l'a atteint : c'est le régime où `THEME_MATCH` sature.
INTEREST_WEIGHT_CAP = 3.0

# Un compte « J+1 » : inscrit depuis au plus ce nombre de jours.
FRESH_ACCOUNT_MAX_DAYS = 1

MAX_ITERATIONS = 50


# Requête du dump, à jouer via le **MCP Supabase** (le rôle RO est refusé sur
# les tables `user_*`). Alignée sur `digest_selector._build_digest_context` :
# sources suivies (+ is_custom / has_subscription / priority_multiplier),
# intérêts (+ state), sous-thèmes, Sujets custom, affinités entités, mutes
# (`user_personalization`) et préférences.
#
# `md5(user_id)` sert de clé de jointure stable **dans le dump seulement** — le
# persona produit ne la porte pas.
PERSONA_DUMP_SQL = """
WITH active AS (
  SELECT p.user_id, p.created_at
  FROM user_profiles p
  WHERE p.deleted_at IS NULL
    AND (EXISTS (SELECT 1 FROM analytics_events e
                 WHERE e.user_id = p.user_id
                   AND e.created_at > now() - interval '30 days')
      OR EXISTS (SELECT 1 FROM user_content_status u
                 WHERE u.user_id = p.user_id
                   AND u.updated_at > now() - interval '30 days'))
)
SELECT json_agg(row_to_json(x) ORDER BY x.user_key) AS users
FROM (
  SELECT
    md5(a.user_id::text) AS user_key,
    GREATEST(0, EXTRACT(DAY FROM (now() - a.created_at))::int) AS days_since_signup,
    COALESCE((SELECT json_agg(json_build_object(
        'source_id', us.source_id::text, 'is_custom', us.is_custom,
        'has_subscription', us.has_subscription,
        'priority_multiplier', us.priority_multiplier, 'state', us.state)
        ORDER BY us.source_id)
      FROM user_sources us WHERE us.user_id = a.user_id), '[]'::json)
      AS followed_sources,
    COALESCE((SELECT json_agg(json_build_object(
        'slug', ui.interest_slug, 'weight', ui.weight, 'state', ui.state)
        ORDER BY ui.interest_slug)
      FROM user_interests ui WHERE ui.user_id = a.user_id), '[]'::json)
      AS interests,
    COALESCE((SELECT json_object_agg(ust.topic_slug, ust.weight)
      FROM user_subtopics ust WHERE ust.user_id = a.user_id), '{}'::json)
      AS subtopic_weights,
    COALESCE((SELECT json_agg(json_build_object(
        'topic_name', tp.topic_name, 'slug_parent', tp.slug_parent,
        'keywords', tp.keywords, 'priority_multiplier', tp.priority_multiplier,
        'state', tp.state, 'entity_type', tp.entity_type,
        'canonical_name', tp.canonical_name)
        ORDER BY tp.topic_name)
      FROM user_topic_profiles tp WHERE tp.user_id = a.user_id), '[]'::json)
      AS custom_topics,
    COALESCE((SELECT json_object_agg(ea.entity_canonical, ea.affinity)
      FROM user_entity_affinity ea WHERE ea.user_id = a.user_id), '{}'::json)
      AS entity_affinities,
    COALESCE((SELECT json_build_object(
        'muted_sources', COALESCE(to_json(up.muted_sources), '[]'::json),
        'muted_themes', COALESCE(to_json(up.muted_themes), '[]'::json),
        'muted_topics', COALESCE(to_json(up.muted_topics), '[]'::json),
        'muted_content_types',
          COALESCE(to_json(up.muted_content_types), '[]'::json))
      FROM user_personalization up WHERE up.user_id = a.user_id),
      '{"muted_sources":[],"muted_themes":[],"muted_topics":[],
        "muted_content_types":[]}'::json) AS mutes,
    COALESCE((SELECT json_object_agg(pr.preference_key, pr.preference_value)
      FROM user_preferences pr WHERE pr.user_id = a.user_id), '{}'::json)
      AS user_prefs
  FROM active a
) x;
"""

FEATURE_NAMES = (
    "n_followed_sources",
    "n_themes",
    "n_custom_topics",
    "max_interest_weight",
    "days_since_signup",
)


# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------


def features(user: dict[str, Any]) -> list[float]:
    """Les 5 axes qui séparent réellement les comptes en prod.

    Volume de sources, largeur thématique, investissement dans les Sujets,
    intensité de l'intérêt le plus fort, ancienneté. Ce sont exactement les
    entrées qui font varier les piliers Pertinence et Source.
    """
    weights = [float(i.get("weight") or 0.0) for i in user.get("interests") or []]
    return [
        float(len(user.get("followed_sources") or [])),
        float(len(user.get("interests") or [])),
        float(len(user.get("custom_topics") or [])),
        max(weights) if weights else 0.0,
        float(user.get("days_since_signup") or 0),
    ]


def zscore(matrix: list[list[float]]) -> list[list[float]]:
    """Z-score colonne par colonne (stdlib). Écart-type nul ⇒ colonne à 0 :
    une feature constante ne doit pas peser dans la distance."""
    if not matrix:
        return []
    n_cols = len(matrix[0])
    columns = [[row[j] for row in matrix] for j in range(n_cols)]
    means = [statistics.fmean(col) for col in columns]
    stdevs = [statistics.pstdev(col) for col in columns]
    return [
        [
            (row[j] - means[j]) / stdevs[j] if stdevs[j] > 1e-12 else 0.0
            for j in range(n_cols)
        ]
        for row in matrix
    ]


def distance(a: list[float], b: list[float]) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b, strict=True)) ** 0.5


# ---------------------------------------------------------------------------
# k-medoids déterministe
# ---------------------------------------------------------------------------


def _seed_medoids(points: list[list[float]], k: int) -> list[int]:
    """Farthest-point depuis le centroïde global.

    Le premier médoïde est le point le plus **proche** du centroïde (le compte
    le plus banal) ; les suivants maximisent la distance minimale aux déjà
    choisis. Aucun aléa, égalités tranchées par l'indice — donc par `user_key`,
    puisque le dump est trié.
    """
    n_cols = len(points[0])
    centroid = [statistics.fmean([p[j] for p in points]) for j in range(n_cols)]
    first = min(range(len(points)), key=lambda i: (distance(points[i], centroid), i))
    medoids = [first]

    while len(medoids) < k:
        best = max(
            range(len(points)),
            key=lambda i: (
                min(distance(points[i], points[m]) for m in medoids)
                if i not in medoids
                else -1.0,
                -i,  # égalité → indice le plus bas
            ),
        )
        if best in medoids:  # moins de k points distincts
            break
        medoids.append(best)
    return sorted(medoids)


def _assign(points: list[list[float]], medoids: list[int]) -> list[int]:
    """Chaque point au médoïde le plus proche ; égalité → médoïde d'indice bas."""
    return [
        min(range(len(medoids)), key=lambda m: (distance(p, points[medoids[m]]), m))
        for p in points
    ]


def kmedoids(points: list[list[float]], k: int) -> tuple[list[int], list[int]]:
    """Retourne `(indices des médoïdes, assignation par point)`.

    Boucle d'échange classique : assigner, puis remplacer chaque médoïde par le
    membre de son cluster qui minimise la somme des distances intra-cluster.
    S'arrête au point fixe (garanti : le coût décroît strictement à chaque
    changement, l'espace des configurations est fini).
    """
    if not points:
        return [], []
    k = min(k, len(points))
    medoids = _seed_medoids(points, k)

    for _ in range(MAX_ITERATIONS):
        assignment = _assign(points, medoids)
        updated: list[int] = []
        for cluster in range(k):
            members = [i for i, c in enumerate(assignment) if c == cluster]
            if not members:
                updated.append(medoids[cluster])
                continue
            best = min(
                members,
                key=lambda i: (sum(distance(points[i], points[j]) for j in members), i),
            )
            updated.append(best)
        if updated == medoids:
            break
        medoids = updated

    return medoids, _assign(points, medoids)


# ---------------------------------------------------------------------------
# Personas
# ---------------------------------------------------------------------------


def _archetype(user: dict[str, Any]) -> str:
    """Étiquette lisible — sert le rapport, pas le scoring."""
    n_src, n_themes, n_topics, max_w, days = features(user)
    return (
        f"{int(n_src)} sources · {int(n_themes)} thèmes · {int(n_topics)} sujets · "
        # 2 décimales : à 1 décimale, un 2,96 s'affiche « 3.0 » et se lit
        # « au plafond » alors qu'il ne l'est pas — c'est justement la
        # distinction que le persona vétéran matérialise.
        f"w_max {max_w:.2f} · J+{int(days)}"
    )


def to_persona(
    user: dict[str, Any],
    persona_id: str,
    *,
    cluster_size: int,
    is_heldout: bool,
    selection: str,
) -> dict[str, Any]:
    """Projette un compte réel en persona anonymisé.

    Les intérêts passent d'une liste à `slug → {weight, state}` : c'est la forme
    que consomment `ScoringContext.user_interest_weights` et
    `user_interest_states`, donc autant la figer ici plutôt que dans le harnais.
    """
    mutes = user.get("mutes") or {}
    interests = {
        entry["slug"]: {
            "weight": float(entry.get("weight") or 0.0),
            "state": entry.get("state"),
        }
        for entry in (user.get("interests") or [])
        if entry.get("slug")
    }
    return {
        "persona_id": persona_id,
        "archetype": _archetype(user),
        # Combien de comptes réels ce persona représente. Un résultat mesuré sur
        # un persona à `cluster_size` 1 ne se généralise pas.
        "cluster_size": cluster_size,
        # `selection` dit *pourquoi* ce compte est là : médoïde d'un cluster, ou
        # extrême délibéré.
        "selection": selection,
        "is_heldout": is_heldout,
        "days_since_signup": int(user.get("days_since_signup") or 0),
        "followed_sources": list(user.get("followed_sources") or []),
        "interests": interests,
        "subtopic_weights": dict(user.get("subtopic_weights") or {}),
        "custom_topics": list(user.get("custom_topics") or []),
        "entity_affinities": dict(user.get("entity_affinities") or {}),
        "muted_sources": list(mutes.get("muted_sources") or []),
        "muted_themes": list(mutes.get("muted_themes") or []),
        "muted_topics": list(mutes.get("muted_topics") or []),
        "muted_content_types": list(mutes.get("muted_content_types") or []),
        "user_prefs": dict(user.get("user_prefs") or {}),
    }


def _max_weight(user: dict[str, Any]) -> float:
    return features(user)[3]


def pick_extremes(
    users: list[dict[str, Any]], taken: set[int]
) -> list[tuple[int, str, int]]:
    """Les deux extrêmes délibérés : `(indice, motif, taille de la population)`.

    Le clustering décrit le centre de la distribution ; ces deux-là décrivent
    ses bords, et c'est aux bords que les constantes cassent.

    - **vétéran** : `weight` au plafond `INTEREST_WEIGHT_CAP` — le régime où
      `THEME_MATCH` sature et où un réglage de pertinence ne se voit plus.
    - **compte neuf** : quasi aucun signal — le cold start, où tout le score
      vient des piliers Source / Fraîcheur / Qualité.

    Un extrême déjà retenu comme médoïde est sauté au profit du suivant : huit
    personas identiques à six n'apporteraient rien. Si **aucun** candidat libre
    ne reste (ou si la population n'en contient aucun), l'extrême est simplement
    absent — le total descend sous 8, et `main` le **dit** plutôt que de laisser
    croire à un jeu complet.
    """
    picked: list[tuple[int, str, int]] = []

    veterans = [i for i, u in enumerate(users) if _max_weight(u) >= INTEREST_WEIGHT_CAP]
    fresh = [
        i
        for i, u in enumerate(users)
        if (u.get("days_since_signup") or 0) <= FRESH_ACCOUNT_MAX_DAYS
    ]

    # Vétéran : le plus ancien parmi ceux au plafond (le plus installé).
    # Compte neuf : le plus récent.
    candidates = (
        ("extreme_veteran", veterans, lambda i: (-(_days(users[i])), i)),
        ("extreme_fresh_account", fresh, lambda i: (_days(users[i]), i)),
    )
    for motif, pool, order in candidates:
        for i in sorted(pool, key=order):
            if i not in taken:
                picked.append((i, motif, len(pool)))
                taken.add(i)
                break

    return picked


def _days(user: dict[str, Any]) -> int:
    return int(user.get("days_since_signup") or 0)


def build_personas(users: list[dict[str, Any]], k: int) -> list[dict[str, Any]]:
    """6 médoïdes + 2 extrêmes → 8 personas numérotés dans cet ordre.

    L'ordre compte : `evaluate_scoring_personas.py --gold` tient les **deux
    derniers en held-out**. Les extrêmes ferment donc la liste.
    """
    points = zscore([features(u) for u in users])
    medoids, assignment = kmedoids(points, k)

    sizes = [assignment.count(c) for c in range(len(medoids))]
    selected: list[tuple[int, str, int]] = [
        (idx, "cluster_medoid", sizes[cluster]) for cluster, idx in enumerate(medoids)
    ]
    taken = {idx for idx, _, _ in selected}
    selected.extend(pick_extremes(users, taken))

    return [
        to_persona(
            users[idx],
            f"persona_{rank:02d}",
            cluster_size=size,
            is_heldout=motif.startswith("extreme_"),
            selection=motif,
        )
        for rank, (idx, motif, size) in enumerate(selected, start=1)
    ]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", required=True, help="Dump MCP Supabase (JSON)")
    parser.add_argument(
        "--out",
        default="tests/fixtures/scoring_personas.json",
        help="Fixture de sortie",
    )
    parser.add_argument("--k", type=int, default=DEFAULT_K, help="Nombre de clusters")
    parser.add_argument(
        "--print-sql",
        action="store_true",
        help="Affiche le SQL du dump (à jouer via le MCP Supabase) et sort",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    if args.print_sql:
        print(PERSONA_DUMP_SQL)
        return 0

    raw = json.loads(Path(args.raw).read_text(encoding="utf-8"))
    users = raw.get("users") or []
    if len(users) < args.k:
        print(f"❌ {len(users)} comptes dans le dump, il en faut au moins {args.k}.")
        return 1

    personas = build_personas(users, args.k)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "dataset_kind": DATASET_KIND,
        "generated_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat(),
        "source_window": raw.get("source_window"),
        "population_size": len(users),
        "k": args.k,
        "features": list(FEATURE_NAMES),
        "note": (
            "Personas dérivés de comptes réels (k-medoids déterministe, stdlib) "
            "puis anonymisés. Aucun user_id ni email. Les deux derniers sont des "
            "extrêmes délibérés et servent de held-out au mode --gold."
        ),
        "personas": personas,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"✅ {len(personas)} personas ({len(users)} comptes) → {out_path}")
    for persona in personas:
        print(
            f"   {persona['persona_id']}  n={persona['cluster_size']:<3} "
            f"{persona['selection']:<21} {persona['archetype']}"
        )

    # Un extrême peut manquer : la population n'en contient aucun, ou le seul
    # candidat était déjà médoïde. Le dire — un jeu de 7 personas silencieux
    # ferait croire à un held-out de 2 alors qu'il n'en reste qu'un.
    for motif in ("extreme_veteran", "extreme_fresh_account"):
        if not any(p["selection"] == motif for p in personas):
            print(
                f"⚠️  extrême « {motif} » absent : aucun compte libre ne le "
                "porte (déjà médoïde, ou population sans ce profil). "
                "Le held-out du mode --gold est réduit d'autant."
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
