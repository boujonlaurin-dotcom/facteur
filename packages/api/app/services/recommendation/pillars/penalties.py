"""Penalty Pass — Applique les pénalités absolues post-pilier.

Consolide : PersonalizationLayer (mutes), ImpressionLayer (déjà vu).
Les pénalités ne sont PAS normalisées — elles s'appliquent en absolu
au score final car elles représentent des signaux négatifs forts.
"""

import json

from app.models.content import Content
from app.services.recommendation.pillars.base import PillarContribution
from app.services.recommendation.pillars.pertinence import _subtopic_label, _theme_label
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext

# Penalty constants (same as PersonalizationLayer)
MUTED_SOURCE_MALUS = -80.0
MUTED_CONTENT_TYPE_MALUS = -50.0
MUTED_THEME_MALUS = -40.0
MUTED_TOPIC_MALUS = -30.0


class PenaltyPass:
    """Compute absolute penalties from mutes and impressions."""

    name = "penalite"
    display_name = "Pénalités"

    def compute(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Returns (total_penalty, contributions). All values are negative or zero."""
        score = 0.0
        contributions: list[PillarContribution] = []

        # --- Muted Source ---
        if context.muted_sources and content.source_id in context.muted_sources:
            score += MUTED_SOURCE_MALUS
            contributions.append(
                PillarContribution(
                    label="Source masquée",
                    points=MUTED_SOURCE_MALUS,
                    is_positive=False,
                )
            )

        # --- Muted Theme ---
        if context.muted_themes:
            effective_theme = None
            if hasattr(content, "theme") and content.theme:
                effective_theme = content.theme.lower().strip()
            elif content.source and content.source.theme:
                effective_theme = content.source.theme.lower().strip()

            if effective_theme and effective_theme in context.muted_themes:
                score += MUTED_THEME_MALUS
                contributions.append(
                    PillarContribution(
                        label=f"Thème masqué : {_theme_label(effective_theme)}",
                        points=MUTED_THEME_MALUS,
                        is_positive=False,
                    )
                )

        # --- Muted Content Type ---
        if context.muted_content_types:
            ct = content.content_type
            if ct and ct in context.muted_content_types:
                ct_label = {
                    "article": "articles",
                    "podcast": "podcasts",
                    "youtube": "vidéos YouTube",
                }.get(ct, ct)
                score += MUTED_CONTENT_TYPE_MALUS
                contributions.append(
                    PillarContribution(
                        label=f"Moins de {ct_label}",
                        points=MUTED_CONTENT_TYPE_MALUS,
                        is_positive=False,
                    )
                )

        # --- Muted Topics ---
        if context.muted_topics and content.topics:
            content_topics = {t.lower().strip() for t in content.topics if t}
            muted_matches = content_topics & set(context.muted_topics)
            for topic in muted_matches:
                score += MUTED_TOPIC_MALUS
                contributions.append(
                    PillarContribution(
                        label=f"Sujet masqué : {_subtopic_label(topic)}",
                        points=MUTED_TOPIC_MALUS,
                        is_positive=False,
                    )
                )

        # --- Muted Entities (matched via muted_topics) ---
        if context.muted_topics and content.entities:
            entity_names: set[str] = set()
            for raw in content.entities:
                try:
                    parsed = json.loads(raw)
                    name = parsed.get("name", "")
                    if isinstance(name, str) and name:
                        entity_names.add(name.lower().strip())
                except (json.JSONDecodeError, TypeError):
                    continue

            muted_entity_matches = entity_names & set(context.muted_topics)
            for entity in muted_entity_matches:
                score += MUTED_TOPIC_MALUS
                contributions.append(
                    PillarContribution(
                        label=f"Sujet masqué : {entity}",
                        points=MUTED_TOPIC_MALUS,
                        is_positive=False,
                    )
                )

        # --- Impression Penalties ---
        impression_result = self._score_impressions(content, context)
        score += impression_result[0]
        contributions.extend(impression_result[1])

        return score, contributions

    def _score_impressions(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Time-decayed impression penalties."""
        if not context.impression_data:
            return 0.0, []

        data = context.impression_data.get(content.id)
        if data is None:
            return 0.0, []

        ts, is_manual = data

        # Manual "already seen" — permanent penalty
        if is_manual:
            return ScoringWeights.IMPRESSION_MANUAL, [
                PillarContribution(
                    label="Marqué comme déjà vu",
                    points=ScoringWeights.IMPRESSION_MANUAL,
                    is_positive=False,
                )
            ]

        # Time-based tiered penalty
        hours = (context.now - ts).total_seconds() / 3600

        if hours < 1:
            penalty = ScoringWeights.IMPRESSION_VERY_RECENT
            label = "Affiché très récemment"
        elif hours < 24:
            penalty = ScoringWeights.IMPRESSION_RECENT
            label = f"Affiché il y a {int(hours)}h"
        elif hours < 48:
            penalty = ScoringWeights.IMPRESSION_DAY
            label = "Affiché hier"
        elif hours < 72:
            penalty = ScoringWeights.IMPRESSION_OLD
            label = "Affiché il y a 2-3j"
        else:
            return 0.0, []

        return penalty, [
            PillarContribution(label=label, points=penalty, is_positive=False)
        ]
