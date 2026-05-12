"""Pré-sets V1 de la veille — affichés en bas du Step 1 (« Inspirations »).

Stockés en JSON statique côté serveur (pas de table DB) : modifier la liste se
fait par redéploiement, sans migration. Les sources curées sont résolues au
runtime via `Source.theme + is_curated` (cf. routers/veille.py:list_presets)
afin qu'un re-seed du catalogue ne casse pas la liste.
"""

from __future__ import annotations

VEILLE_PRESETS: list[dict] = [
    {
        "slug": "ia_agentique",
        "label": "Outils IA agentique",
        "accroche": (
            "Les derniers outils et bonnes pratiques pour développer à "
            "l'ère de l'IA agentique."
        ),
        "theme_id": "tech",
        "theme_label": "Technologie",
        "topics": [
            "Agents LLM & frameworks",
            "Outils dev & productivité IA",
            "Modèles open-source",
            "Cas d'usage en production",
        ],
        "purposes": ["progresser_au_travail"],
        "editorial_brief": (
            "Plutôt analyses concrètes et retours d'expérience d'équipes "
            "tech que hype marketing. Focus sur ce qui marche en production."
        ),
    },
    {
        "slug": "geopolitique_long",
        "label": "Géopolitique long format",
        "accroche": (
            "Comprendre les recompositions géopolitiques actuelles via "
            "l'analyse long format."
        ),
        "theme_id": "international",
        "theme_label": "Géopolitique",
        "topics": [
            "Tensions sino-américaines",
            "Recompositions du Sud global",
            "Conflits & sécurité",
            "Énergie & matières premières",
        ],
        "purposes": ["culture_generale"],
        "editorial_brief": (
            "Analyses long format avec mise en perspective historique, "
            "plutôt que breaking news. Sources de référence et chercheurs."
        ),
    },
    {
        "slug": "transition_climat",
        "label": "Transition climatique",
        "accroche": (
            "Suivre la transition climatique : politiques publiques, "
            "ruptures techno, retours d'expérience."
        ),
        "theme_id": "environment",
        "theme_label": "Environnement",
        "topics": [
            "Politiques publiques climat",
            "Énergies bas carbone",
            "Industrie & décarbonation",
            "Adaptation & risques",
        ],
        "purposes": ["preparer_projet"],
        "editorial_brief": (
            "Articles factuels et chiffrés sur ce qui change vraiment, "
            "avec un focus sur les implications concrètes (politiques, "
            "industrie, territoires)."
        ),
    },
]


def get_presets() -> list[dict]:
    """Renvoie la liste des pré-sets. Helper pour faciliter le mock en tests."""
    return VEILLE_PRESETS
