"""Banc de mesure du **scoring par piliers** contre des personas réels et un
corpus gelé (cf. `docs/maintenance/maintenance-scoring-tuning-harness.md`).

Miroir de `evaluate_veille_curation.py` : **ni DB ni réseau**, tout vient de deux
fixtures (`build_persona_dataset.py` + `build_scoring_corpus.py`), sorties `.json`
et `.md` appariées dans `.context/`, `--tag` / `--compare` / `--sweep`.

### La méthodo, et pourquoi elle commande l'ordre des modes

8 personas × ~30 candidats jugeables ≈ 240 labels pour **113 constantes
numériques** dans `ScoringWeights` : 2 labels par paramètre. Tuner directement
contre un gold à cette densité, c'est de l'overfit, pas de la calibration. D'où
l'ordre :

1. `--sensitivity` — **0 label**. Quelles constantes bougent seulement quelque
   chose ? Une constante inerte ne se règle pas, elle se supprime ou s'ignore.
2. `--invariants` — assertions falsifiables, pass/fail, sans notion d'optimum.
3. `--gold` — `precision@5`, **portail de non-régression uniquement**. Jamais une
   fonction à maximiser.

`--sweep` publie **la courbe complète, jamais l'argmax** : lire l'argmax d'une
courbe en dents de scie, c'est calibrer sur du bruit ; le détecteur de
monotonie le dit explicitement.

### Le harnais rejoue le VRAI moteur

`PillarScoringEngine.compute_score` est appelé tel quel — pas de fork de la
porte, sinon l'anti-drift est perdu (garde :
`test_evaluate_scoring_personas.py::test_harness_uses_the_production_engine`).

⚠️ **Piège** : `PillarScoringEngine.__init__` fait
`self.weights = ScoringWeights.PILLAR_WEIGHTS` (`scoring_engine.py:207`). Un
moteur construit **avant** un `weights_override(PILLAR_WEIGHTS=…)` garderait
l'ancien dict. Règle sans exception ici : **un moteur neuf par configuration**,
construit à l'intérieur du `with`.

### Le NOW est figé

`NOW` = le `generated_at` du corpus, jamais l'horloge du run. Sinon le pilier
Fraîcheur dérive d'un jour à l'autre et deux runs sur le même corpus ne sont
plus comparables — ce que `--compare` refuserait de toute façon (il rejette deux
runs dont le `corpus_file` diffère).

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/evaluate_scoring_personas.py --sensitivity \\
        --tag baseline
    PYTHONPATH=. python scripts/evaluate_scoring_personas.py --invariants
    PYTHONPATH=. python scripts/evaluate_scoring_personas.py \\
        --sweep ENTITY_AFFINITY_BASE=8,16,32,64
    PYTHONPATH=. python scripts/evaluate_scoring_personas.py --compare \\
        ../../.context/scoring-personas-baseline-2026-08-03.json \\
        ../../.context/scoring-personas-iter1-2026-08-10.json

Sorties :
    .context/scoring-personas-<tag>-<date>.json  (machine, consommé par --compare)
    .context/scoring-personas-<tag>-<date>.md    (humain)
"""

from __future__ import annotations

import argparse
import datetime as dt
import functools
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from uuid import UUID

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.models.content import Content  # noqa: E402
from app.models.enums import ContentType, InterestState, ReliabilityScore  # noqa: E402
from app.models.source import Source  # noqa: E402
from app.services.recommendation.filter_presets import is_sport_content  # noqa: E402
from app.services.recommendation.scoring_config import (  # noqa: E402
    ScoringWeights,
    is_overridable_scoring_key,
)
from app.services.recommendation.scoring_engine import (  # noqa: E402
    PillarScoringEngine,
    ScoringContext,
)
from scripts._scoring_overrides import (  # noqa: E402
    NON_PATCHABLE_AT_RUNTIME,
    weights_override,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"
FIXTURES_DIR = Path(__file__).resolve().parents[1] / "tests" / "fixtures"

DEFAULT_PERSONAS = FIXTURES_DIR / "scoring_personas.json"
DEFAULT_GOLD = FIXTURES_DIR / "scoring_gold_labels.json"

# Grille de perturbation. Multiplicative : une constante à 50 et une à 0,7 se
# comparent en effet **relatif**, pas en pas absolu. Repli additif pour les
# constantes nulles (une multiplication y serait un no-op).
SENSITIVITY_FACTORS = (0.5, 0.75, 1.25, 2.0)
ZERO_CONSTANT_DELTAS = (-1.0, 1.0)

TOP_K = 5
# Taille du jeu figé sur lequel τ-b est calculé.
TAU_SET_SIZE = 20
# Fenêtre visible de l'invariant de mute. Volontairement distincte de
# `TAU_SET_SIZE` : élargir le jeu de τ pour stabiliser la corrélation ne doit pas
# desserrer en douce une assertion falsifiable.
MUTED_WINDOW = 20

# Sous ce churn max, une constante est déclarée **inerte** : elle ne déplace
# jamais le top-5 d'aucun persona sous aucune perturbation de la grille. On ne
# règle pas un signal inerte.
EFFECT_FLOOR = 1e-9

# Au-delà de ~200 articles × 113 constantes × 4 facteurs × 8 personas, le run se
# compte en heures. Le mode `--sensitivity` échantillonne donc par défaut.
DEFAULT_SENSITIVITY_SAMPLE = 200

# Modules qui composent réellement `PillarScoringEngine.compute_score`. Sert à
# distinguer « inerte parce que sans effet » de « inerte parce que hors du
# moteur » — deux verdicts très différents pour le lecteur du rapport.
#
# Strictement `pillars/` + `helpers/` + le moteur : le reste du paquet
# `recommendation/` (`tournee_suggester`, `carousel_*`, `layers/` legacy v1) lit
# ses propres constantes sans jamais passer par `compute_score`. Les y inclure
# ferait passer `TOURNEE_SUGGEST_SUBCAP` pour une constante de scoring d'article.
_RECO_DIR = Path(__file__).resolve().parents[1] / "app" / "services" / "recommendation"
ENGINE_MODULE_PATHS = (
    _RECO_DIR / "pillars",
    _RECO_DIR / "helpers",
    _RECO_DIR / "scoring_engine.py",
)


# ---------------------------------------------------------------------------
# Chargement des fixtures
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PersonaCustomTopic:
    """Adaptateur Sujet custom → duck-typing de `_score_custom_topics`.

    Même patron que `VeilleAngleTopic` (`app/services/veille/scoring_context.py`)
    : le pilier Pertinence ne fait que des `getattr` sur ces champs, il n'a
    jamais besoin de l'objet ORM. `frozen=True` pour qu'un persona reste
    immuable d'une configuration de sweep à l'autre.
    """

    slug_parent: str | None
    keywords: list[str]
    topic_name: str
    priority_multiplier: float = 1.0
    state: InterestState = InterestState.FOLLOWED
    entity_type: str | None = None
    canonical_name: str | None = None


@dataclass
class Persona:
    persona_id: str
    archetype: str
    cluster_size: int
    is_heldout: bool
    followed_source_ids: set[UUID]
    custom_source_ids: set[UUID]
    subscribed_source_ids: set[UUID]
    source_priority_multipliers: dict[UUID, float]
    interest_weights: dict[str, float]
    interest_states: dict[str, InterestState]
    subtopic_weights: dict[str, float]
    custom_topics: list[PersonaCustomTopic]
    entity_affinities: dict[str, float]
    muted_sources: set[UUID]
    muted_themes: set[str]
    muted_topics: set[str]
    muted_content_types: set[str]
    user_prefs: dict[str, Any] = field(default_factory=dict)


# `persona_id → (scores, classement)` hors override.
Baselines = dict[str, tuple[dict[str, float], list[str]]]


@dataclass
class Corpus:
    now: dt.datetime
    contents: list[Content]
    cluster_source_counts: dict[UUID, int]
    # `is_sport_content` est un pur prédicat sur l'article : ni le persona ni la
    # constante perturbée ne le changent. Le résoudre une fois évite de le
    # rejouer à chaque passe (≈300 000 évaluations sur un run de sensibilité).
    sport_content_ids: frozenset[str]


def _as_uuid(value: Any) -> UUID | None:
    try:
        return UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def _interest_state(raw: Any) -> InterestState:
    try:
        return InterestState(raw)
    except ValueError:
        return InterestState.FOLLOWED


def load_personas(path: Path) -> list[Persona]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("dataset_kind") != "scoring_personas":
        raise ValueError(f"{path.name} n'est pas un dataset scoring_personas")

    personas: list[Persona] = []
    for entry in payload.get("personas", []):
        followed: set[UUID] = set()
        custom: set[UUID] = set()
        subscribed: set[UUID] = set()
        multipliers: dict[UUID, float] = {}
        for source in entry.get("followed_sources") or []:
            sid = _as_uuid(source.get("source_id"))
            if sid is None:
                continue
            followed.add(sid)
            if source.get("is_custom"):
                custom.add(sid)
            if source.get("has_subscription"):
                subscribed.add(sid)
            multipliers[sid] = float(source.get("priority_multiplier") or 1.0)

        interests = entry.get("interests") or {}
        personas.append(
            Persona(
                persona_id=entry["persona_id"],
                archetype=entry.get("archetype", ""),
                cluster_size=int(entry.get("cluster_size") or 0),
                is_heldout=bool(entry.get("is_heldout")),
                followed_source_ids=followed,
                custom_source_ids=custom,
                subscribed_source_ids=subscribed,
                source_priority_multipliers=multipliers,
                interest_weights={
                    slug: float(v.get("weight") or 0.0) for slug, v in interests.items()
                },
                interest_states={
                    slug: _interest_state(v.get("state"))
                    for slug, v in interests.items()
                },
                subtopic_weights={
                    slug: float(w or 0.0)
                    for slug, w in (entry.get("subtopic_weights") or {}).items()
                },
                custom_topics=[
                    PersonaCustomTopic(
                        slug_parent=tp.get("slug_parent"),
                        keywords=list(tp.get("keywords") or []),
                        topic_name=tp.get("topic_name") or "",
                        priority_multiplier=float(tp.get("priority_multiplier") or 1.0),
                        state=_interest_state(tp.get("state")),
                        entity_type=tp.get("entity_type"),
                        canonical_name=tp.get("canonical_name"),
                    )
                    for tp in entry.get("custom_topics") or []
                ],
                entity_affinities={
                    name: float(w or 0.0)
                    for name, w in (entry.get("entity_affinities") or {}).items()
                },
                muted_sources={
                    sid
                    for sid in (_as_uuid(s) for s in entry.get("muted_sources") or [])
                    if sid is not None
                },
                muted_themes={t.lower() for t in entry.get("muted_themes") or [] if t},
                muted_topics={t.lower() for t in entry.get("muted_topics") or [] if t},
                muted_content_types={
                    t.lower() for t in entry.get("muted_content_types") or [] if t
                },
                user_prefs=dict(entry.get("user_prefs") or {}),
            )
        )
    return personas


def _content_type(raw: Any) -> ContentType:
    try:
        return ContentType(raw)
    except ValueError:
        return ContentType.ARTICLE


def _reliability(raw: Any) -> ReliabilityScore | None:
    try:
        return ReliabilityScore(raw)
    except ValueError:
        return None


def load_corpus(path: Path, *, sample: int | None = None) -> Corpus:
    """Réhydrate le corpus en objets ORM **transitoires**.

    Pattern éprouvé de `prove_thematic_scoring.py` : des `Source` / `Content`
    jamais attachés à une session. Les piliers ne lisent que des attributs, donc
    aucune DB n'est nécessaire — et surtout aucun lazy-load ne peut se
    déclencher, puisque `content.source` est assigné en dur.
    """
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("dataset_kind") != "scoring_corpus":
        raise ValueError(f"{path.name} n'est pas un dataset scoring_corpus")

    now = dt.datetime.fromisoformat(payload["generated_at"])
    articles = payload.get("articles") or []
    if sample and sample < len(articles):
        # Déterministe : mêmes articles d'un run à l'autre (tri par id).
        articles = sorted(articles, key=lambda a: a["id"])[:sample]

    sources: dict[str, Source] = {}
    contents: list[Content] = []
    for article in articles:
        raw_source = article["source"]
        sid_raw = raw_source["id"]
        if sid_raw not in sources:
            sources[sid_raw] = Source(
                id=_as_uuid(sid_raw),
                name=raw_source.get("name") or "",
                theme=raw_source.get("theme"),
                is_curated=bool(raw_source.get("is_curated")),
                secondary_themes=list(raw_source.get("secondary_themes") or []),
                tone=raw_source.get("tone"),
                source_tier=raw_source.get("source_tier"),
                reliability_score=_reliability(raw_source.get("reliability_score")),
            )
        source = sources[sid_raw]
        contents.append(
            Content(
                id=_as_uuid(article["id"]),
                title=article.get("title") or "",
                description=article.get("description") or "",
                theme=article.get("theme"),
                topics=list(article.get("topics") or []),
                entities=list(article.get("entities") or []),
                published_at=dt.datetime.fromisoformat(article["published_at"]),
                content_type=_content_type(article.get("content_type")),
                duration_seconds=article.get("duration_seconds"),
                content_quality=article.get("content_quality"),
                # Seule la présence compte pour `QualitePillar` ; le corpus ne
                # versionne que le booléen.
                thumbnail_url="https://thumb" if article.get("has_thumbnail") else None,
                cluster_id=_as_uuid(article.get("cluster_id")),
                language=article.get("language"),
                source_id=source.id,
                source=source,
            )
        )

    return Corpus(
        now=now,
        contents=contents,
        cluster_source_counts=_cluster_source_counts(contents),
        sport_content_ids=frozenset(str(c.id) for c in contents if is_sport_content(c)),
    )


def _cluster_source_counts(contents: list[Content]) -> dict[UUID, int]:
    """Nombre de sources distinctes par cluster, recalculé **depuis le corpus**.

    C'est ce que fait la prod sur sa fenêtre 24 h (`compute_coverage_score`) :
    reprendre un compte figé en base donnerait un bonus de couverture qui ne
    correspond à aucun des candidats effectivement présents ici.
    """
    by_cluster: dict[UUID, set[UUID]] = {}
    for content in contents:
        if content.cluster_id is None:
            continue
        by_cluster.setdefault(content.cluster_id, set()).add(content.source_id)
    return {cluster: len(sources) for cluster, sources in by_cluster.items()}


def load_gold(path: Path) -> dict[str, set[str]]:
    """Gold `precision@5` : `persona_id → {content_id pertinents}`."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("dataset_kind") != "scoring_gold_labels":
        raise ValueError(f"{path.name} n'est pas un dataset scoring_gold_labels")
    return {
        entry["persona_id"]: {
            label["content_id"]
            for label in entry.get("labels") or []
            if label.get("relevant")
        }
        for entry in payload.get("personas", [])
    }


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------


def build_context(
    persona: Persona, corpus: Corpus, *, personalized_theme_mode: bool
) -> ScoringContext:
    """`ScoringContext` transitoire — `user_profile=None`, comme
    `prove_thematic_scoring.py`. Aucun pilier ne déréférence le profil."""
    return ScoringContext(
        user_profile=None,
        user_interests=set(persona.interest_weights),
        user_interest_weights=dict(persona.interest_weights),
        followed_source_ids=set(persona.followed_source_ids),
        user_prefs=dict(persona.user_prefs),
        now=corpus.now,
        user_subtopics=set(persona.subtopic_weights),
        user_subtopic_weights=dict(persona.subtopic_weights),
        user_entity_affinity=dict(persona.entity_affinities),
        muted_sources=set(persona.muted_sources),
        muted_themes=set(persona.muted_themes),
        muted_topics=set(persona.muted_topics),
        muted_content_types=set(persona.muted_content_types),
        custom_source_ids=set(persona.custom_source_ids),
        user_custom_topics=list(persona.custom_topics),
        source_priority_multipliers=dict(persona.source_priority_multipliers),
        subscribed_source_ids=set(persona.subscribed_source_ids),
        user_interest_states=dict(persona.interest_states),
        cluster_source_counts=dict(corpus.cluster_source_counts),
        personalized_theme_mode=personalized_theme_mode,
    )


def score_corpus(
    corpus: Corpus,
    persona: Persona,
    *,
    personalized_theme_mode: bool = False,
    apply_sport_penalty: bool = False,
) -> dict[str, float]:
    """`content_id → final_score`, via un **moteur neuf** (piège PILLAR_WEIGHTS).

    `apply_sport_penalty` rejoue l'ajustement post-pilier de
    `digest_selector` (mode `pour_vous`) : `DIGEST_SPORT_PENALTY` **ne vit pas
    dans le moteur de piliers**, il est appliqué après la combinaison. Le
    prédicat (`is_sport_content`) et la constante sont ceux de la prod — mais
    l'invariant qui en dépend doit dire d'où vient la pénalité, sans quoi on
    croirait mesurer un pilier.
    """
    engine = PillarScoringEngine()
    context = build_context(
        persona, corpus, personalized_theme_mode=personalized_theme_mode
    )
    scores: dict[str, float] = {}
    for content in corpus.contents:
        cid = str(content.id)
        score = engine.compute_score(content, context).final_score
        if apply_sport_penalty and cid in corpus.sport_content_ids:
            # La constante reste lue **dans** la boucle : elle est balayable.
            score += ScoringWeights.DIGEST_SPORT_PENALTY
        scores[cid] = score
    return scores


def ranking(scores: dict[str, float]) -> list[str]:
    """Ordre décroissant, égalités tranchées par `content_id` — sans ce
    tie-break, deux runs identiques pourraient permuter des ex æquo et le churn
    mesurerait l'ordre d'itération d'un dict."""
    return sorted(scores, key=lambda cid: (-scores[cid], cid))


# ---------------------------------------------------------------------------
# Métriques
# ---------------------------------------------------------------------------


def kendall_tau_b(xs: list[float], ys: list[float]) -> float:
    """τ-b sur **un ensemble fixe** d'items, en présence d'ex æquo.

    Pourquoi un ensemble fixe : un « τ sur le top-5 » n'est pas défini, les deux
    top-5 n'ayant pas les mêmes éléments — on ne peut pas corréler deux
    classements sur des univers différents. On gèle donc le top-20 baseline et
    on re-classe *ces mêmes* articles après perturbation.

    Convention : ensembles de 0 ou 1 élément, ou dénominateur nul (tout ex æquo
    d'un côté) → **1.0**, c'est-à-dire « rien n'a bougé ». C'est le verdict
    honnête pour la sensibilité : l'absence de désordre observable.
    """
    n = len(xs)
    if n != len(ys):
        raise ValueError("kendall_tau_b : vecteurs de tailles différentes")
    if n < 2:
        return 1.0

    concordant = discordant = ties_x = ties_y = 0
    for i in range(n):
        for j in range(i + 1, n):
            dx = xs[i] - xs[j]
            dy = ys[i] - ys[j]
            if dx == 0 and dy == 0:
                ties_x += 1
                ties_y += 1
            elif dx == 0:
                ties_x += 1
            elif dy == 0:
                ties_y += 1
            elif (dx > 0) == (dy > 0):
                concordant += 1
            else:
                discordant += 1

    n0 = n * (n - 1) / 2
    denominator = ((n0 - ties_x) * (n0 - ties_y)) ** 0.5
    if denominator <= 0:
        return 1.0
    return (concordant - discordant) / denominator


def top_k_churn(before: list[str], after: list[str], k: int = TOP_K) -> float:
    """`1 − |A∩B|/k` — la part du top-k qui a changé.

    C'est la métrique qui **classe** les constantes dans le rapport : τ mesure
    le désordre global, le churn mesure ce que l'utilisateur voit réellement.
    """
    if k <= 0:
        return 0.0
    a, b = set(before[:k]), set(after[:k])
    return 1.0 - len(a & b) / k


def precision_at_k(order: list[str], relevant: set[str], k: int = TOP_K) -> float:
    if k <= 0:
        return 0.0
    return len([cid for cid in order[:k] if cid in relevant]) / k


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


# ---------------------------------------------------------------------------
# Constantes : périmètre et grille
# ---------------------------------------------------------------------------


def numeric_constants() -> list[str]:
    """Constantes numériques publiques de `ScoringWeights`, hors non-patchables.

    `NON_PATCHABLE_AT_RUNTIME` est exclu **en amont** : `weights_override` lève
    dessus (à raison — le patch serait un no-op silencieux), donc les balayer
    ferait planter le run au lieu de produire un rapport.

    Le critère « clé valide » vient de `is_overridable_scoring_key`, celui-là
    même sur lequel `weights_override` accepte ou refuse : énumérer avec une
    copie de la règle exposerait à lui soumettre une clé qu'il rejette, et le run
    mourrait en route au lieu de produire un rapport.
    """
    return sorted(
        name
        for name in dir(ScoringWeights)
        if is_overridable_scoring_key(name)
        and name not in NON_PATCHABLE_AT_RUNTIME
        and isinstance(getattr(ScoringWeights, name), int | float)
        and not isinstance(getattr(ScoringWeights, name), bool)
    )


def _engine_source_text() -> str:
    chunks: list[str] = []
    for entry in ENGINE_MODULE_PATHS:
        paths = sorted(entry.rglob("*.py")) if entry.is_dir() else [entry]
        for path in paths:
            if "__pycache__" in path.parts:
                continue
            chunks.append(path.read_text(encoding="utf-8"))
    return "\n".join(chunks)


@functools.cache
def constants_in_engine_scope() -> frozenset[str]:
    """Constantes réellement lues par le moteur de piliers (scan statique).

    Mise en cache : le scan relit tout `pillars/` + `helpers/` sur disque, et le
    résultat ne peut pas changer pendant un run.

    Sans ce partage, le rapport dirait « TOURNEE_SUGGEST_SUBCAP est inerte »
    alors qu'elle n'est simplement **pas dans le périmètre de ce harnais** — elle
    pilote l'arrangement de la Tournée, pas le score d'un article. Deux verdicts
    opposés qu'il serait grave de confondre.
    """
    text = _engine_source_text()
    # Pas de classe `[A-Z]` en tête : `ScoringWeights.recency_base` est en
    # minuscules et pilote tout le pilier Fraîcheur — la rater la classerait
    # « hors-périmètre », soit l'inverse de la vérité.
    referenced = set(re.findall(r"ScoringWeights\.([A-Za-z][A-Za-z0-9_]*)", text))
    return frozenset(referenced & set(numeric_constants()))


def measurable_constants(
    *,
    apply_sport_penalty: bool = False,
    **_ignored: Any,
) -> frozenset[str]:
    """Constantes que **ce run** peut réellement mesurer.

    C'est le périmètre du moteur, **plus** les constantes post-piliers que le run
    rejoue effectivement. Sans ce couplage, `--sensitivity --sport-penalty`
    appliquerait `DIGEST_SPORT_PENALTY` à chaque article tout en la rapportant
    « jamais lue par le moteur » — le rapport contredirait le run.
    """
    scope = constants_in_engine_scope()
    if apply_sport_penalty:
        scope |= {"DIGEST_SPORT_PENALTY"}
    return frozenset(scope)


def perturbations(name: str) -> list[tuple[str, float]]:
    """`(étiquette, valeur perturbée)` pour une constante.

    Grille multiplicative : deux constantes d'échelles très différentes (50 vs
    0,7) ne sont comparables qu'en effet relatif. Repli additif quand la valeur
    est nulle — la multiplier serait un no-op déguisé en mesure.
    """
    current = float(getattr(ScoringWeights, name))
    if current == 0.0:
        return [(f"{delta:+g}", delta) for delta in ZERO_CONSTANT_DELTAS]
    return [(f"×{factor:g}", current * factor) for factor in SENSITIVITY_FACTORS]


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------


def _baselines(
    corpus: Corpus, personas: list[Persona], **score_kwargs: Any
) -> Baselines:
    """`persona_id → (scores, classement)` de référence, calculé **hors** de tout
    override — c'est le point de comparaison de toutes les perturbations.

    Une passe coûte tout le corpus × tous les personas. Les quatre modes partent
    de la même référence : `main` la calcule une fois et la passe à chacun.
    """
    baselines: Baselines = {}
    for persona in personas:
        scores = score_corpus(corpus, persona, **score_kwargs)
        baselines[persona.persona_id] = (scores, ranking(scores))
    return baselines


def _deltas_vs_baseline(
    base_scores: dict[str, float], base_order: list[str], scores: dict[str, float]
) -> tuple[float, float]:
    """`(churn top-5, τ-b)` d'une configuration perturbée contre sa référence.

    τ-b se calcule sur le **jeu figé** des `TAU_SET_SIZE` premiers de la
    référence, re-classés par les nouveaux scores : c'est ce qui mesure un
    réordonnancement plutôt qu'un changement de population. Partagé par
    `--sensitivity` et `--sweep`, sans quoi les deux modes pourraient publier
    deux « τ-b » qui ne veulent pas dire la même chose.
    """
    frozen = base_order[:TAU_SET_SIZE]
    tau = kendall_tau_b(
        [base_scores[cid] for cid in frozen],
        [scores[cid] for cid in frozen],
    )
    return top_k_churn(base_order, ranking(scores)), tau


def run_sensitivity(
    corpus: Corpus,
    personas: list[Persona],
    *,
    only_prefix: str | None = None,
    baselines: Baselines | None = None,
    **score_kwargs: Any,
) -> dict[str, Any]:
    """Classement des constantes par churn max. **Aucun label requis.**

    Les constantes hors périmètre ne sont **pas** rescorées : la perturber
    produirait 32 classements identiques. Leur verdict vient du scan statique,
    et le rapport le dit — pour qu'on ne lise pas « hors-périmètre » comme
    « inerte ».
    """
    if baselines is None:
        baselines = _baselines(corpus, personas, **score_kwargs)
    in_scope = measurable_constants(**score_kwargs)
    names = [
        n for n in numeric_constants() if not only_prefix or n.startswith(only_prefix)
    ]

    rows: list[dict[str, Any]] = []
    for name in names:
        if name not in in_scope:
            rows.append(_unmeasured_row(name))
            continue

        churns: list[float] = []
        taus: list[float] = []
        worst: dict[str, Any] | None = None

        for label, value in perturbations(name):
            for persona in personas:
                # Moteur neuf DANS le `with` : sans ça, un override de
                # PILLAR_WEIGHTS serait invisible (scoring_engine.py:207).
                with weights_override(**{name: value}):
                    scores = score_corpus(corpus, persona, **score_kwargs)
                base_scores, base_order = baselines[persona.persona_id]
                churn, tau = _deltas_vs_baseline(base_scores, base_order, scores)
                churns.append(churn)
                taus.append(tau)
                if worst is None or churn > worst["churn"]:
                    worst = {
                        "churn": churn,
                        "tau": tau,
                        "perturbation": label,
                        "persona_id": persona.persona_id,
                    }

        max_churn = max(churns) if churns else 0.0
        min_tau = min(taus) if taus else 1.0
        rows.append(
            {
                "constant": name,
                "value": getattr(ScoringWeights, name),
                "max_churn": max_churn,
                "mean_churn": _mean(churns),
                "min_tau": min_tau,
                "mean_tau": _mean(taus),
                "worst_case": worst,
                "measured": True,
                "verdict": _sensitivity_verdict(max_churn, min_tau, True),
            }
        )

    # Churn d'abord (ce que l'utilisateur voit), puis τ pour départager les
    # constantes à churn nul mais qui réordonnent quand même.
    rows.sort(key=lambda r: (-r["max_churn"], r["min_tau"], r["constant"]))
    return {
        "mode": "sensitivity",
        "constants_evaluated": len(rows),
        "personas": [p.persona_id for p in personas],
        "articles": len(corpus.contents),
        "grid": {
            "factors": list(SENSITIVITY_FACTORS),
            "zero_deltas": list(ZERO_CONSTANT_DELTAS),
        },
        "effect_floor": EFFECT_FLOOR,
        "rows": rows,
    }


def _unmeasured_row(name: str) -> dict[str, Any]:
    """Ligne d'une constante hors périmètre : renseignée, mais `measured=False`.

    Les valeurs neutres (churn 0, τ 1) ne sont **pas** un résultat de mesure ;
    c'est `measured` qui porte la distinction, et le rendu s'appuie dessus.
    """
    return {
        "constant": name,
        "value": getattr(ScoringWeights, name),
        "max_churn": 0.0,
        "mean_churn": 0.0,
        "min_tau": 1.0,
        "mean_tau": 1.0,
        "worst_case": None,
        "measured": False,
        # Le verdict vient de la même fonction que les lignes mesurées : deux
        # écritures du littéral pourraient diverger sans que rien ne rougisse.
        "verdict": _sensitivity_verdict(0.0, 1.0, False),
    }


def _sensitivity_verdict(max_churn: float, min_tau: float, in_scope: bool) -> str:
    """Trois verdicts mesurés, plus un quatrième purement statique.

    Le churn seul ne suffit pas : une constante peut réordonner tout le top-20
    sans jamais changer *l'ensemble* des 5 premiers. La déclarer « inerte » sur
    ce seul critère la retirerait à tort du champ du tuning — d'où le palier
    intermédiaire « faible », qui dit exactement ce qui a été observé.
    """
    if not in_scope:
        return "hors-périmètre"
    if max_churn > EFFECT_FLOOR:
        return "actif"
    if min_tau < 1.0 - EFFECT_FLOOR:
        return "faible"
    return "inerte"


# --- Invariants -------------------------------------------------------------


def _followed_themes(persona: Persona) -> set[str]:
    return {
        slug.lower()
        for slug, state in persona.interest_states.items()
        if state in (InterestState.FOLLOWED, InterestState.FAVORITE)
    }


def _content_by_id(corpus: Corpus) -> dict[str, Content]:
    return {str(c.id): c for c in corpus.contents}


def check_invariants(
    corpus: Corpus,
    persona: Persona,
    order: list[str],
    *,
    apply_sport_penalty: bool = False,
) -> list[dict[str, Any]]:
    """4 assertions falsifiables. `n/a` quand le persona n'a pas le signal —
    un `pass` vacueux est pire que rien, il donne l'illusion d'une couverture.

    `apply_sport_penalty` dit dans quel régime `order` a été produit. L'invariant
    sport porte le nom de la pénalité : sans cette information il attribuerait à
    `DIGEST_SPORT_PENALTY` un rang mesuré **sans** elle.
    """
    index = _content_by_id(corpus)
    top = [index[cid] for cid in order[:TOP_K]]
    results: list[dict[str, Any]] = []

    # 1. Une source mutée ne remonte jamais dans la fenêtre visible.
    if persona.muted_sources:
        window = [index[cid] for cid in order[:MUTED_WINDOW]]
        leaked = [c for c in window if c.source_id in persona.muted_sources]
        results.append(
            {
                "name": "muted_source_never_surfaces",
                "status": "fail" if leaked else "pass",
                "detail": f"{len(leaked)} article(s) de source mutée dans le top-"
                f"{MUTED_WINDOW}",
            }
        )
    else:
        results.append(
            {
                "name": "muted_source_never_surfaces",
                "status": "n/a",
                "detail": "aucune source mutée sur ce persona",
            }
        )

    # 2. Le top-5 reste majoritairement dans les thèmes suivis.
    themes = _followed_themes(persona)
    if themes:
        matched = [
            c
            for c in top
            if (c.theme or "").lower() in themes
            or (c.source and (c.source.theme or "").lower() in themes)
        ]
        results.append(
            {
                "name": "top5_majority_followed_theme",
                "status": "pass" if len(matched) >= 3 else "fail",
                "detail": f"{len(matched)}/5 dans un thème suivi (attendu ≥3)",
            }
        )
    else:
        results.append(
            {
                "name": "top5_majority_followed_theme",
                "status": "n/a",
                "detail": "aucun thème suivi (cold start)",
            }
        )

    # 3. Aucune source ne monopolise le top-5.
    counts: dict[UUID, int] = {}
    for c in top:
        counts[c.source_id] = counts.get(c.source_id, 0) + 1
    worst = max(counts.values(), default=0)
    results.append(
        {
            "name": "no_source_dominates_top5",
            "status": "pass" if worst <= 2 else "fail",
            "detail": f"source la plus présente : {worst}/5 (attendu ≤2)",
        }
    )

    # 4. Un Sujet sportif suivi n'est pas annihilé par DIGEST_SPORT_PENALTY.
    #    C'est le cas qui motive PR-5. Rappel : la pénalité est appliquée par
    #    `digest_selector`, hors moteur de piliers (cf. `score_corpus`).
    sport_candidates = [
        cid
        for cid in order
        if cid in corpus.sport_content_ids
        and index[cid].source_id in persona.followed_source_ids
    ]
    if sport_candidates and "sport" in themes:
        best_rank = order.index(sport_candidates[0]) + 1
        regime = (
            "pénalité appliquée"
            if apply_sport_penalty
            else "hors pénalité (--sport-penalty absent)"
        )
        results.append(
            {
                "name": "followed_sport_survives_penalty",
                "status": "pass" if best_rank <= 10 else "fail",
                "detail": f"meilleur sport suivi au rang {best_rank} "
                f"(attendu ≤10, {regime})",
            }
        )
    else:
        results.append(
            {
                "name": "followed_sport_survives_penalty",
                "status": "n/a",
                "detail": "pas de thème sport suivi avec candidat sport",
            }
        )

    return results


def run_invariants(
    corpus: Corpus,
    personas: list[Persona],
    *,
    baselines: Baselines | None = None,
    **score_kwargs: Any,
) -> dict[str, Any]:
    if baselines is None:
        baselines = _baselines(corpus, personas, **score_kwargs)
    per_persona = []
    for persona in personas:
        _, order = baselines[persona.persona_id]
        checks = check_invariants(
            corpus,
            persona,
            order,
            apply_sport_penalty=score_kwargs.get("apply_sport_penalty", False),
        )
        per_persona.append(
            {
                "persona_id": persona.persona_id,
                "archetype": persona.archetype,
                "cluster_size": persona.cluster_size,
                "checks": checks,
            }
        )

    flat = [c for p in per_persona for c in p["checks"]]
    return {
        "mode": "invariants",
        "personas": per_persona,
        "totals": {
            "pass": len([c for c in flat if c["status"] == "pass"]),
            "fail": len([c for c in flat if c["status"] == "fail"]),
            "n/a": len([c for c in flat if c["status"] == "n/a"]),
        },
    }


# --- Gold -------------------------------------------------------------------


def run_gold(
    corpus: Corpus,
    personas: list[Persona],
    gold: dict[str, set[str]],
    *,
    include_heldout: bool = False,
    baselines: Baselines | None = None,
    **score_kwargs: Any,
) -> dict[str, Any]:
    """`precision@5` — **portail de non-régression**, jamais une cible.

    Les personas held-out (les deux extrêmes) sont exclus par défaut : garder un
    jeu jamais regardé est la seule protection contre le fait de régler les
    constantes jusqu'à ce que le gold passe.
    """
    if baselines is None:
        baselines = _baselines(corpus, personas, **score_kwargs)
    rows = []
    for persona in personas:
        if persona.is_heldout and not include_heldout:
            continue
        relevant = gold.get(persona.persona_id)
        if not relevant:
            continue
        _, order = baselines[persona.persona_id]
        rows.append(
            {
                "persona_id": persona.persona_id,
                "labelled": len(relevant),
                "precision_at_5": precision_at_k(order, relevant),
            }
        )
    return {
        "mode": "gold",
        "include_heldout": include_heldout,
        "rows": rows,
        # `None` et non `0.0` quand rien n'est labellisé : `--compare` doit
        # pouvoir distinguer « a régressé à 0 » de « n'a jamais été mesuré ».
        "macro_precision_at_5": (
            _mean([r["precision_at_5"] for r in rows]) if rows else None
        ),
    }


# --- Sweep ------------------------------------------------------------------


def classify_curve(values: list[float], eps: float = 1e-9) -> str:
    """Verdict de forme d'une courbe de sweep.

    Une courbe en dents de scie n'a pas d'argmax interprétable : son maximum est
    du bruit d'échantillonnage. Le dire explicitement est le seul garde-fou
    contre la calibration accidentelle sur du bruit.
    """
    if len(values) < 2:
        return "TROP COURTE"
    # `strict=False` volontaire : `values[1:]` est plus court d'un cran par
    # construction — c'est le principe même d'un parcours de différences.
    diffs = [b - a for a, b in zip(values, values[1:], strict=False)]
    if all(abs(d) <= eps for d in diffs):
        return "PLATE — constante inerte sur cet intervalle"
    if all(d >= -eps for d in diffs) or all(d <= eps for d in diffs):
        return "MONOTONE"

    # Les paliers (pente nulle) sont retirés avant de compter les inversions :
    # sinon un plat entre deux montées compterait pour deux changements de signe.
    signs = [1 if d > eps else -1 for d in diffs if abs(d) > eps]
    changes = sum(1 for a, b in zip(signs, signs[1:], strict=False) if a != b)
    if changes <= 1:
        return "UNIMODALE"
    return "NON MONOTONE — bruit, ne pas calibrer"


def run_sweep(
    corpus: Corpus,
    personas: list[Persona],
    name: str,
    values: list[float],
    *,
    gold: dict[str, set[str]] | None = None,
    baselines: Baselines | None = None,
    **score_kwargs: Any,
) -> dict[str, Any]:
    """Courbe **complète**, jamais l'argmax."""
    if baselines is None:
        baselines = _baselines(corpus, personas, **score_kwargs)
    # `None` si la constante n'est pas un scalaire (`PILLAR_WEIGHTS` est un
    # dict) : le raccourci ne s'applique alors jamais, et c'est
    # `weights_override` qui rendra son verdict, avec son message à lui.
    raw = getattr(ScoringWeights, name, None)
    current = float(raw) if isinstance(raw, int | float) else None
    rows = []
    for value in values:
        churns: list[float] = []
        taus: list[float] = []
        precisions: list[float] = []
        for persona in personas:
            base_scores, base_order = baselines[persona.persona_id]
            if current is not None and value == current:
                # Surcharger une constante par sa propre valeur est un no-op :
                # la référence *est* le résultat. La recette documentée
                # (`ENTITY_AFFINITY_BASE=8,…` avec 8 en base) passe par ici.
                scores, order = base_scores, base_order
            else:
                with weights_override(**{name: value}):
                    scores = score_corpus(corpus, persona, **score_kwargs)
                order = ranking(scores)
            churn, tau = _deltas_vs_baseline(base_scores, base_order, scores)
            churns.append(churn)
            taus.append(tau)
            if gold and (relevant := gold.get(persona.persona_id)):
                precisions.append(precision_at_k(order, relevant))
        rows.append(
            {
                "value": value,
                "mean_churn_vs_baseline": _mean(churns),
                "mean_tau": _mean(taus),
                "macro_precision_at_5": _mean(precisions) if precisions else None,
            }
        )

    return {
        "mode": "sweep",
        "constant": name,
        "baseline_value": getattr(ScoringWeights, name),
        "rows": rows,
        "shape_churn": classify_curve([r["mean_churn_vs_baseline"] for r in rows]),
        "shape_precision": classify_curve(
            [
                r["macro_precision_at_5"]
                for r in rows
                if r["macro_precision_at_5"] is not None
            ]
        )
        if gold
        else None,
    }


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------


def render_sensitivity(metrics: dict[str, Any], *, top: int = 30) -> str:
    lines = [
        "## Sensibilité — quelles constantes déplacent quelque chose",
        "",
        f"{metrics['constants_evaluated']} constantes · "
        f"{len(metrics['personas'])} personas · {metrics['articles']} articles · "
        f"grille ×{{{', '.join(str(f) for f in metrics['grid']['factors'])}}}",
        "",
        "`churn max` = part du top-5 déplacée dans le pire cas "
        "(persona × perturbation) — c'est ce que l'utilisateur voit. "
        "`τ-b min` = désordre du top-20 baseline re-classé.",
        "",
        "| constante | valeur | churn max | τ-b min | pire cas | verdict |",
        "|---|---:|---:|---:|---|---|",
    ]
    for row in metrics["rows"][:top]:
        worst = row["worst_case"] or {}
        case = (
            f"{worst.get('perturbation', '—')} / {worst.get('persona_id', '—')}"
            if worst.get("churn")
            else "—"
        )
        lines.append(
            f"| `{row['constant']}` | {row['value']} | "
            f"{row['max_churn']:.2f} | {row['min_tau']:.3f} | {case} | "
            f"{row['verdict']} |"
        )

    counts = {
        verdict: len([r for r in metrics["rows"] if r["verdict"] == verdict])
        for verdict in ("actif", "faible", "inerte", "hors-périmètre")
    }
    out_of_scope = [r for r in metrics["rows"] if r["verdict"] == "hors-périmètre"]
    lines += [
        "",
        f"**{counts['actif']} actives · {counts['faible']} faibles · "
        f"{counts['inerte']} inertes · {counts['hors-périmètre']} hors-périmètre.**",
        "",
        "- *actif* : au moins une perturbation de la grille déplace le top-5 "
        "d'au moins un persona. **C'est ici, et nulle part ailleurs, que se "
        "prend une décision de tuning.**",
        "- *faible* : réordonne le top-20 sans jamais changer l'ensemble des 5 "
        "premiers. Effet réel mais invisible pour l'utilisateur.",
        "- *inerte* : lue par le moteur, aucun effet observable sous aucune "
        "perturbation. On ne règle pas un signal inerte.",
        "- *hors-périmètre* : jamais lue par le moteur de piliers (arrangement "
        "de la Tournée, digest, Essentiel, veille…). Ce harnais ne dit **rien** "
        "de son effet en prod — ne pas lire « inerte ».",
    ]
    if out_of_scope:
        lines += [
            "",
            "Hors-périmètre : "
            + ", ".join(f"`{r['constant']}`" for r in out_of_scope[:40])
            + (" …" if len(out_of_scope) > 40 else ""),
        ]
    return "\n".join(lines)


def render_invariants(metrics: dict[str, Any]) -> str:
    totals = metrics["totals"]
    lines = [
        "## Invariants",
        "",
        f"**{totals['pass']} pass · {totals['fail']} fail · {totals['n/a']} n/a**",
        "",
        "| persona | invariant | statut | détail |",
        "|---|---|---|---|",
    ]
    for persona in metrics["personas"]:
        for check in persona["checks"]:
            lines.append(
                f"| {persona['persona_id']} | `{check['name']}` | "
                f"{check['status']} | {check['detail']} |"
            )
    lines += [
        "",
        "`n/a` = le persona ne porte pas le signal testé. Un `pass` vacueux "
        "donnerait l'illusion d'une couverture qui n'existe pas.",
    ]
    return "\n".join(lines)


def render_gold(metrics: dict[str, Any]) -> str:
    lines = [
        "## Gold — precision@5 (portail de non-régression)",
        "",
        f"held-out inclus : {metrics['include_heldout']}",
        "",
    ]
    if not metrics["rows"]:
        # Un « macro precision@5 : 0.000 » sur un gold vide se lit comme un score
        # catastrophique alors qu'il ne s'est rien passé. C'est le faux négatif
        # silencieux que la jauge sœur a déjà payé une fois.
        return "\n".join(
            lines
            + [
                "**Aucun persona labellisé — le gold est un squelette vide.**",
                "",
                "Ce n'est pas un score de 0, c'est une absence de mesure. Le gold "
                "réel est un travail PO, réservé aux 3-5 constantes que "
                "`--sensitivity` a signalées comme *actives* (cf. "
                "`how_to_fill` dans `tests/fixtures/scoring_gold_labels.json`).",
            ]
        )

    lines += [
        "| persona | labels | precision@5 |",
        "|---|---:|---:|",
    ]
    for row in metrics["rows"]:
        lines.append(
            f"| {row['persona_id']} | {row['labelled']} | {row['precision_at_5']:.2f} |"
        )
    lines += [
        "",
        f"**macro precision@5 : {metrics['macro_precision_at_5']:.3f}**",
        "",
        "⚠️ Le gold est un **portail**, pas une fonction à maximiser. "
        "À 240 labels pour 113 constantes, l'optimiser serait de l'overfit.",
    ]
    return "\n".join(lines)


def render_sweep(metrics: dict[str, Any]) -> str:
    lines = [
        f"## Sweep — `{metrics['constant']}` (baseline {metrics['baseline_value']})",
        "",
        "| valeur | churn moyen vs baseline | τ-b moyen | macro p@5 |",
        "|---:|---:|---:|---:|",
    ]
    for row in metrics["rows"]:
        precision = (
            f"{row['macro_precision_at_5']:.2f}"
            if row["macro_precision_at_5"] is not None
            else "—"
        )
        lines.append(
            f"| {row['value']:g} | {row['mean_churn_vs_baseline']:.3f} | "
            f"{row['mean_tau']:.3f} | {precision} |"
        )
    lines += ["", f"**Forme (churn) : {metrics['shape_churn']}**"]
    if metrics.get("shape_precision"):
        lines.append(f"**Forme (precision@5) : {metrics['shape_precision']}**")
    lines += [
        "",
        "La courbe complète est publiée, **jamais l'argmax** : sur une courbe "
        "non monotone, le maximum est du bruit d'échantillonnage.",
    ]
    return "\n".join(lines)


def render_compare(baseline: dict[str, Any], after: dict[str, Any]) -> str:
    """`--compare` **refuse** deux runs de corpus différents.

    C'est la règle qui rend la campagne falsifiable : deux mesures prises sur
    deux jeux de candidats ne se comparent pas, et rien dans les chiffres ne le
    dirait.
    """
    base_corpus = baseline.get("corpus_file")
    after_corpus = after.get("corpus_file")
    if base_corpus != after_corpus:
        raise ValueError(
            "Ces deux runs ne sont pas comparables : corpus "
            f"« {base_corpus} » vs « {after_corpus} ». Un corpus est gelé et "
            "append-only — rejouer la baseline sur le corpus de l'after."
        )

    # Même fichier ne suffit pas : `--corpus-sample` change le jeu de candidats
    # sans changer le nom du corpus. Deux runs à 200 et 30 articles portent des
    # top-5 tirés d'univers différents, et aucun chiffre du rapport ne le dirait.
    base_n = baseline.get("corpus_articles")
    after_n = after.get("corpus_articles")
    if base_n != after_n:
        raise ValueError(
            "Ces deux runs ne sont pas comparables : même corpus "
            f"« {base_corpus} » mais {base_n} vs {after_n} articles retenus "
            "(`--corpus-sample`). Rejouer les deux avec le même échantillon."
        )

    lines = [
        f"## Comparaison — `{baseline.get('tag')}` → `{after.get('tag')}`",
        "",
        f"corpus commun : `{base_corpus}`",
        "",
    ]

    base_gold = (baseline.get("gold") or {}).get("macro_precision_at_5")
    after_gold = (after.get("gold") or {}).get("macro_precision_at_5")
    if base_gold is not None and after_gold is not None:
        delta = (after_gold - base_gold) * 100
        lines += [
            f"macro precision@5 : {base_gold:.3f} → {after_gold:.3f} ({delta:+.1f} pp)",
            "",
        ]

    base_inv = (baseline.get("invariants") or {}).get("totals")
    after_inv = (after.get("invariants") or {}).get("totals")
    if base_inv and after_inv:
        lines += [
            f"invariants fail : {base_inv['fail']} → {after_inv['fail']}",
            "",
        ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_sweep(raw: str) -> tuple[str, list[float]]:
    if "=" not in raw:
        raise SystemExit("--sweep attend CONSTANTE=v1,v2,v3")
    name, values = raw.split("=", 1)
    name = name.strip()
    try:
        parsed = [float(v) for v in values.split(",") if v.strip()]
    except ValueError as exc:
        raise SystemExit(f"--sweep : valeurs illisibles ({exc})") from exc
    if len(parsed) < 2:
        raise SystemExit("--sweep attend au moins 2 valeurs")
    return name, parsed


def _default_corpus() -> Path:
    """Le corpus le plus récent versionné. Le choix est **explicite** dans le
    rapport (`corpus_file`) : c'est la clé qui autorise ou refuse un `--compare`."""
    candidates = sorted(FIXTURES_DIR.glob("scoring_corpus_*.json"))
    if not candidates:
        raise SystemExit(
            "Aucun corpus dans tests/fixtures/ — lancer build_scoring_corpus.py"
        )
    return candidates[-1]


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--personas", default=None)
    parser.add_argument("--corpus", default=None)
    parser.add_argument("--gold-labels", default=None)
    parser.add_argument("--tag", default="baseline")

    parser.add_argument("--sensitivity", action="store_true")
    parser.add_argument("--invariants", action="store_true")
    parser.add_argument("--gold", action="store_true")
    parser.add_argument("--sweep", default=None, metavar="CONST=a,b,c")
    parser.add_argument(
        "--compare", nargs=2, metavar=("BASELINE", "AFTER"), default=None
    )

    parser.add_argument("--only", default=None, help="Préfixe de constantes")
    parser.add_argument(
        "--corpus-sample",
        type=int,
        default=None,
        help=f"Sous-échantillon du corpus (défaut {DEFAULT_SENSITIVITY_SAMPLE} "
        "en --sensitivity)",
    )
    parser.add_argument("--include-heldout", action="store_true")
    parser.add_argument(
        "--personalized-theme-mode",
        action="store_true",
        help="Gate le malus feuilleton (sections de la Tournée)",
    )
    parser.add_argument(
        "--sport-penalty",
        action="store_true",
        help="Rejoue DIGEST_SPORT_PENALTY (post-pilier, chemin digest pour_vous)",
    )
    parser.add_argument("--out-json", default=None)
    parser.add_argument("--out-md", default=None)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)

    if args.compare:
        baseline = json.loads(Path(args.compare[0]).read_text(encoding="utf-8"))
        after = json.loads(Path(args.compare[1]).read_text(encoding="utf-8"))
        print(render_compare(baseline, after))
        return 0

    if not any([args.sensitivity, args.invariants, args.gold, args.sweep]):
        print("Rien à faire : --sensitivity, --invariants, --gold ou --sweep.")
        return 1

    personas_path = Path(args.personas or DEFAULT_PERSONAS)
    corpus_path = Path(args.corpus or _default_corpus())
    personas = load_personas(personas_path)

    sample = args.corpus_sample
    if sample is None and args.sensitivity:
        sample = DEFAULT_SENSITIVITY_SAMPLE
    corpus = load_corpus(corpus_path, sample=sample)

    score_kwargs = {
        "personalized_theme_mode": args.personalized_theme_mode,
        "apply_sport_penalty": args.sport_penalty,
    }

    gold: dict[str, set[str]] | None = None
    gold_path = Path(args.gold_labels or DEFAULT_GOLD)
    if (args.gold or args.sweep) and gold_path.exists():
        gold = load_gold(gold_path)

    sections: list[str] = []
    payload: dict[str, Any] = {
        "generated_at": dt.datetime.now(dt.UTC).isoformat(),
        "tag": args.tag,
        "personas_file": personas_path.name,
        # La clé de comparabilité : `--compare` refuse deux runs qui diffèrent.
        "corpus_file": corpus_path.name,
        "corpus_generated_at": corpus.now.isoformat(),
        "corpus_articles": len(corpus.contents),
        "personalized_theme_mode": args.personalized_theme_mode,
        "sport_penalty": args.sport_penalty,
    }

    # Référence commune aux quatre modes : une passe corpus × personas, pas une
    # par mode. Tous partent du même `score_kwargs`, donc de la même référence.
    baselines = _baselines(corpus, personas, **score_kwargs)

    if args.sensitivity:
        metrics = run_sensitivity(
            corpus, personas, only_prefix=args.only, baselines=baselines, **score_kwargs
        )
        payload["sensitivity"] = metrics
        sections.append(render_sensitivity(metrics))

    if args.invariants:
        metrics = run_invariants(corpus, personas, baselines=baselines, **score_kwargs)
        payload["invariants"] = metrics
        sections.append(render_invariants(metrics))

    if args.gold:
        if gold is None:
            print(f"❌ Aucun gold lisible ({gold_path}).")
            return 1
        metrics = run_gold(
            corpus,
            personas,
            gold,
            include_heldout=args.include_heldout,
            baselines=baselines,
            **score_kwargs,
        )
        payload["gold"] = metrics
        sections.append(render_gold(metrics))

    if args.sweep:
        name, values = _parse_sweep(args.sweep)
        metrics = run_sweep(
            corpus,
            personas,
            name,
            values,
            gold=gold,
            baselines=baselines,
            **score_kwargs,
        )
        payload["sweep"] = metrics
        sections.append(render_sweep(metrics))

    header = [
        f"# Scoring personas — `{args.tag}`",
        "",
        f"- personas : `{personas_path.name}` ({len(personas)})",
        f"- corpus : `{corpus_path.name}` ({len(corpus.contents)} articles, "
        f"NOW figé {corpus.now.isoformat()})",
        "",
    ]
    report = "\n".join(header) + "\n\n".join(sections) + "\n"

    today = dt.datetime.now(dt.UTC).date().isoformat()
    out_json = Path(
        args.out_json or CONTEXT_DIR / f"scoring-personas-{args.tag}-{today}.json"
    )
    out_md = Path(
        args.out_md or CONTEXT_DIR / f"scoring-personas-{args.tag}-{today}.md"
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    out_md.write_text(report, encoding="utf-8")

    print(f"✅ Résultats : {out_json}")
    print(f"✅ Rapport   : {out_md}")
    print()
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
