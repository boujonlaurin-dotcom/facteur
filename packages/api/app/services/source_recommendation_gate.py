"""Garde-fou éditorial des sources POUSSÉES — footer « Étoffer [thème] ».

Facteur ne se porte **jamais** garant d'une source non vérifiée ou extrémiste.
Les sources *poussées* (Tier 1 « Pépite Facteur » et Tier 2 « Catalogue évalué »)
doivent passer le gate de ce module. Les sources non évaluées / externes
(Tier 3 « Ta recherche ») ne transitent jamais par ici : elles n'apparaissent
que sur une recherche **explicite** de l'utilisateur, hors de tout endpoint de
recommandation poussée.

Les seuils ci-dessous sont des **knobs PO** : modifiables ici, en un seul
endroit, sans toucher au routeur ni au modèle.
"""

from app.models.enums import BiasStance, ReliabilityScore
from app.models.source import Source

# --- Gate de sécurité commun aux tiers POUSSÉS (1 & 2) -----------------------
# Une source poussée ne doit jamais avoir une fiabilité basse/inconnue…
PUSHED_EXCLUDED_RELIABILITY: frozenset[ReliabilityScore] = frozenset(
    {ReliabilityScore.LOW, ReliabilityScore.UNKNOWN}
)
# …ni un positionnement « alternatif » (complotiste / non vérifié).
PUSHED_EXCLUDED_BIAS: frozenset[BiasStance] = frozenset({BiasStance.ALTERNATIVE})

# --- Critère « Catalogue évalué » (Tier 2) -----------------------------------
# Plus strict que le gate de sécurité : fiabilité **explicitement** bonne…
QUALITY_CATALOG_RELIABILITY: frozenset[ReliabilityScore] = frozenset(
    {ReliabilityScore.HIGH, ReliabilityScore.MEDIUM}
)
# …et biais **connu** (ni alternatif, ni inconnu) — sinon Facteur ne peut pas
# afficher un badge d'évaluation honnête.
QUALITY_CATALOG_EXCLUDED_BIAS: frozenset[BiasStance] = frozenset(
    {BiasStance.ALTERNATIVE, BiasStance.UNKNOWN}
)


def _reliability(source: Source) -> ReliabilityScore:
    """Fiabilité normalisée — défaut prudent `UNKNOWN` (donc exclue des tiers
    poussés) si la valeur est absente ou inattendue."""
    raw = source.reliability_score
    if isinstance(raw, ReliabilityScore):
        return raw
    try:
        return ReliabilityScore(raw)
    except (ValueError, TypeError):
        return ReliabilityScore.UNKNOWN


def _bias(source: Source) -> BiasStance:
    """Biais normalisé — défaut prudent `UNKNOWN`."""
    raw = source.bias_stance
    if isinstance(raw, BiasStance):
        return raw
    try:
        return BiasStance(raw)
    except (ValueError, TypeError):
        return BiasStance.UNKNOWN


def passes_safety_gate(source: Source) -> bool:
    """La source peut-elle être **poussée** (Tier 1 ou 2) ?

    Exclut toute source à fiabilité basse/inconnue ou au positionnement
    alternatif. Appliqué aussi aux pépites curées : une pépite sans fiabilité
    renseignée ne sera pas poussée tant que l'équipe ne l'a pas évaluée — sûr
    par construction.
    """
    if _reliability(source) in PUSHED_EXCLUDED_RELIABILITY:
        return False
    if _bias(source) in PUSHED_EXCLUDED_BIAS:
        return False
    return True


def is_quality_catalog(source: Source) -> bool:
    """La source qualifie-t-elle pour le **Tier 2 « Catalogue évalué »** ?

    Curée, fiabilité haute/moyenne et biais connu non alternatif. Ce critère
    est strictement plus fort que [passes_safety_gate] : une source Tier 2
    passe donc toujours le gate de sécurité.
    """
    if not source.is_curated:
        return False
    if _reliability(source) not in QUALITY_CATALOG_RELIABILITY:
        return False
    if _bias(source) in QUALITY_CATALOG_EXCLUDED_BIAS:
        return False
    return True
