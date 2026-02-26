"""Module de sélection Top 3 pour le briefing quotidien.

Story 4.4: Top 3 Briefing Quotidien
Ce module sélectionne les 3 meilleurs articles avec les contraintes:
1. Application des boosts d'importance (+30 Une, +40 Trending)
2. Maximum 1 article par source (diversité)
3. Slot #3 réservé aux sources suivies par l'utilisateur (quota confiance)

Architecture: Ce module est DÉCOUPLÉ du ScoringEngine. Il consomme le résultat
du scoring et les flags d'importance de ImportanceDetector.
"""

from dataclasses import dataclass
from uuid import UUID

import structlog

from app.models.content import Content

logger = structlog.get_logger()


@dataclass
class Top3Item:
    """Item sélectionné pour le Top 3.

    Attributes:
        content: Le contenu sélectionné
        score: Score final après application des boosts
        top3_reason: Raison expliquant la sélection
            Valeurs possibles: "À la Une", "Sujet tendance", "Source suivie", "Recommandé"
    """

    content: Content
    score: float
    top3_reason: str


class Top3Selector:
    """Sélectionne les 3 meilleurs articles avec contraintes.

    Le sélecteur applique les règles suivantes:
    1. Boost les contenus "À la Une" (+BOOST_UNE points)
    2. Boost les contenus "Trending" (+BOOST_TRENDING points)
    3. Trie par score décroissant
    4. Sélectionne les slots #1 et #2 parmi les meilleurs (sources distinctes)
    5. Réserve le slot #3 aux sources suivies par l'utilisateur

    Attributes:
        BOOST_UNE: Points ajoutés pour un contenu "À la Une" (défaut: 30)
        BOOST_TRENDING: Points ajoutés pour un sujet tendance (défaut: 40)
    """

    BOOST_UNE = 30
    BOOST_TRENDING = 40

    def __init__(self, boost_une: int = 30, boost_trending: int = 40):
        """Initialise le sélecteur.

        Args:
            boost_une: Points à ajouter pour les contenus "À la Une"
            boost_trending: Points à ajouter pour les sujets tendance
        """
        self.BOOST_UNE = boost_une
        self.BOOST_TRENDING = boost_trending

    def select_top3(
        self,
        scored_contents: list[tuple[Content, float]],
        user_followed_sources: set[UUID],
        une_content_ids: set[UUID],
        trending_content_ids: set[UUID],
    ) -> list[Top3Item]:
        """Sélectionne le Top 3 avec contraintes.

        Algorithme:
        1. Appliquer les boosts d'importance
        2. Trier par score décroissant
        3. Sélectionner slots #1 et #2 (sources distinctes)
        4. Réserver slot #3 aux sources suivies (ou fallback)

        Args:
            scored_contents: Liste de tuples (Content, base_score) du ScoringEngine
            user_followed_sources: UUIDs des sources suivies par l'utilisateur
            une_content_ids: UUIDs des contenus "À la Une"
            trending_content_ids: UUIDs des contenus trending

        Returns:
            Liste de 0 à 3 Top3Item ordonnés par rang
        """
        if not scored_contents:
            logger.info("top3_selector_empty_input")
            return []

        # Étape 1: Appliquer les boosts et déterminer la raison
        boosted: list[tuple[Content, float, str]] = []

        for content, base_score in scored_contents:
            boost = 0
            reason = "Recommandé"

            # Boost "À la Une"
            if content.id in une_content_ids:
                boost += self.BOOST_UNE
                reason = "À la Une"

            # Boost "Trending" (cumulable avec Une)
            if content.id in trending_content_ids:
                boost += self.BOOST_TRENDING
                # Trending a priorité sur Une pour la raison si les deux
                if reason == "Recommandé":
                    reason = "Sujet tendance"

            # Si aucune raison spéciale (ni Une ni Trending), vérifier si Source Suivie
            if reason == "Recommandé" and content.source_id in user_followed_sources:
                reason = "Source suivie"

            final_score = base_score + boost
            boosted.append((content, final_score, reason))

        # Étape 2: Trier par score décroissant
        boosted.sort(key=lambda x: x[1], reverse=True)

        # Étape 3: Sélectionner slots #1 et #2 (sources distinctes)
        top2: list[Top3Item] = []
        used_sources: set[UUID] = set()
        selected_content_ids: set[UUID] = set()

        for content, score, reason in boosted:
            if content.source_id not in used_sources:
                top2.append(Top3Item(content=content, score=score, top3_reason=reason))
                used_sources.add(content.source_id)
                selected_content_ids.add(content.id)

            if len(top2) >= 2:
                break

        # Étape 4: Slot #3 - Réservé aux sources suivies
        slot3: Top3Item | None = None

        # Filtrer les contenus restants (non sélectionnés, source non utilisée)
        remaining = [
            (c, s, r)
            for c, s, r in boosted
            if c.id not in selected_content_ids and c.source_id not in used_sources
        ]

        # Chercher parmi les sources suivies
        from_followed = [
            (c, s, r) for c, s, r in remaining if c.source_id in user_followed_sources
        ]

        if from_followed:
            # Prendre le meilleur des sources suivies
            content, score, _ = from_followed[0]  # Déjà trié par score
            slot3 = Top3Item(
                content=content,
                score=score,
                top3_reason="Source suivie",  # Override la raison
            )
            logger.debug(
                "top3_slot3_followed_source",
                source_id=str(content.source_id),
                content_title=content.title[:50],
            )
        elif remaining:
            # Fallback: prendre le meilleur restant
            content, score, reason = remaining[0]
            slot3 = Top3Item(content=content, score=score, top3_reason=reason)
            logger.debug(
                "top3_slot3_fallback",
                source_id=str(content.source_id),
                content_title=content.title[:50],
            )

        # Construire le résultat final
        result = top2 + ([slot3] if slot3 else [])

        logger.info(
            "top3_selection_complete",
            input_count=len(scored_contents),
            output_count=len(result),
            reasons=[item.top3_reason for item in result],
            has_followed_source=any(
                item.top3_reason == "Source suivie" for item in result
            ),
        )

        return result

    def generate_top3_with_reasons(
        self,
        scored_contents: list[tuple[Content, float]],
        user_followed_sources: set[UUID],
        une_content_ids: set[UUID],
        trending_content_ids: set[UUID],
    ) -> list[dict]:
        """Génère le Top 3 avec métadonnées supplémentaires.

        Wrapper autour de select_top3 qui retourne un format dict
        plus pratique pour la sérialisation API.

        Returns:
            Liste de dicts avec: content_id, rank, top3_reason, score
        """
        top3_items = self.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=user_followed_sources,
            une_content_ids=une_content_ids,
            trending_content_ids=trending_content_ids,
        )

        return [
            {
                "content_id": item.content.id,
                "content": item.content,
                "rank": idx + 1,
                "top3_reason": item.top3_reason,
                "score": item.score,
            }
            for idx, item in enumerate(top3_items)
        ]
