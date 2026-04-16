"""Pilier Pertinence — Mesure la correspondance avec les intérêts utilisateur.

Consolide : CoreLayer (theme), ArticleTopicLayer, BehavioralLayer,
            UserCustomTopicLayer, StaticPreferenceLayer (format).
"""

from app.models.content import Content
from app.models.enums import ContentType
from app.services.recommendation.pillars.base import BasePillar, PillarContribution
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext

# Mapping thèmes slugs -> Français
THEME_LABELS = {
    "tech": "Tech & Innovation",
    "society": "Société",
    "environment": "Environnement",
    "economy": "Économie",
    "politics": "Politique",
    "culture": "Culture & Idées",
    "science": "Sciences",
    "international": "Géopolitique",
    "geopolitics": "Géopolitique",
    "society_climate": "Société",
    "culture_ideas": "Culture & Idées",
}

# Mapping 50 sous-thèmes slugs -> Français
SUBTOPIC_LABELS = {
    "ai": "IA",
    "llm": "LLM",
    "crypto": "Crypto",
    "web3": "Web3",
    "space": "Spatial",
    "biotech": "Biotech",
    "quantum": "Quantique",
    "cybersecurity": "Cybersécurité",
    "robotics": "Robotique",
    "gaming": "Gaming",
    "cleantech": "Cleantech",
    "data-privacy": "Données",
    "social-justice": "Justice sociale",
    "feminism": "Féminisme",
    "lgbtq": "LGBTQ+",
    "immigration": "Immigration",
    "health": "Santé",
    "education": "Éducation",
    "urbanism": "Urbanisme",
    "housing": "Logement",
    "work-reform": "Travail",
    "justice-system": "Justice",
    "climate": "Climat",
    "biodiversity": "Biodiversité",
    "energy-transition": "Transition énergétique",
    "pollution": "Pollution",
    "circular-economy": "Économie circulaire",
    "agriculture": "Agriculture",
    "oceans": "Océans",
    "forests": "Forêts",
    "macro": "Macro-économie",
    "finance": "Finance",
    "startups": "Startups",
    "venture-capital": "VC",
    "labor-market": "Emploi",
    "inflation": "Inflation",
    "trade": "Commerce",
    "taxation": "Fiscalité",
    "elections": "Élections",
    "institutions": "Institutions",
    "local-politics": "Politique locale",
    "activism": "Activisme",
    "democracy": "Démocratie",
    "philosophy": "Philosophie",
    "art": "Art",
    "cinema": "Cinéma",
    "media-critics": "Critique des médias",
    "fundamental-research": "Recherche",
    "applied-science": "Sciences appliquées",
    "geopolitics": "Géopolitique",
}


def _theme_label(slug: str) -> str:
    return THEME_LABELS.get(slug.lower().strip(), slug.capitalize())


def _subtopic_label(slug: str) -> str:
    return SUBTOPIC_LABELS.get(slug.lower().strip(), slug.capitalize())


def _get_effective_theme(content: Content, user_interests: set[str]) -> str | None:
    """Determine effective theme: content.theme > source.theme > secondary_themes."""
    if hasattr(content, "theme") and content.theme:
        if content.theme in user_interests:
            return content.theme
    if content.source and content.source.theme:
        if content.source.theme in user_interests:
            return content.source.theme
    if content.source and getattr(content.source, "secondary_themes", None):
        matched = set(content.source.secondary_themes) & user_interests
        if matched:
            return sorted(matched)[0]
    return None


class PertinencePillar(BasePillar):
    """Mesure à quel point l'article correspond aux intérêts de l'utilisateur."""

    @property
    def name(self) -> str:
        return "pertinence"

    @property
    def display_name(self) -> str:
        return "Vos centres d'intérêt"

    @property
    def expected_max(self) -> float:
        return ScoringWeights.MAX_PERTINENCE_RAW

    def compute_raw(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        score = 0.0
        contributions: list[PillarContribution] = []

        # --- 1. Theme Match (3-tier) ---
        theme_score = self._score_theme(content, context)
        if theme_score[0] > 0:
            score += theme_score[0]
            contributions.append(theme_score[1])

        # --- 2. Subtopic Match (ArticleTopicLayer logic) ---
        topic_result = self._score_subtopics(content, context)
        score += topic_result[0]
        contributions.extend(topic_result[1])

        # --- 3. Behavioral Amplifier ---
        behavioral_result = self._score_behavioral(content, context)
        score += behavioral_result[0]
        contributions.extend(behavioral_result[1])

        # --- 4. Custom Topic Match ---
        custom_result = self._score_custom_topics(content, context)
        score += custom_result[0]
        contributions.extend(custom_result[1])

        # --- 5. Format Preference ---
        format_result = self._score_format(content, context)
        score += format_result[0]
        contributions.extend(format_result[1])

        # --- 6. Theme Mismatch Malus ---
        # Léger désavantage pour les articles hors des thèmes/sous-thèmes suivis,
        # sans les exclure. Ne s'applique qu'aux utilisateurs ayant déclaré des
        # préférences (cold start préservé).
        mismatch_result = self._score_theme_mismatch(
            theme_score[0], topic_result[0], custom_result[0], context
        )
        score += mismatch_result[0]
        contributions.extend(mismatch_result[1])

        return score, contributions

    def _score_theme_mismatch(
        self,
        theme_points: float,
        subtopic_points: float,
        custom_topic_points: float,
        context: ScoringContext,
    ) -> tuple[float, list[PillarContribution]]:
        """Malus léger quand aucun thème/sous-thème/custom topic ne matche."""
        has_preferences = bool(
            context.user_interests
            or context.user_subtopics
            or context.user_custom_topics
        )
        if not has_preferences:
            return 0.0, []
        if theme_points > 0 or subtopic_points > 0 or custom_topic_points > 0:
            return 0.0, []

        malus = ScoringWeights.THEME_MISMATCH_MALUS
        return malus, [
            PillarContribution(
                label="Thème non suivi",
                points=malus,
                is_positive=False,
            )
        ]

    def _score_theme(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, PillarContribution | None]:
        """3-tier theme matching: content.theme > source.theme > secondary_themes."""
        # Tier 1: Article-level theme (ML-inferred)
        if hasattr(content, "theme") and content.theme:
            if content.theme in context.user_interests:
                label = f"Thème : {_theme_label(content.theme)}"
                return ScoringWeights.THEME_MATCH, PillarContribution(
                    label=label, points=ScoringWeights.THEME_MATCH
                )

        # Tier 2: Source primary theme
        if content.source and content.source.theme:
            if content.source.theme in context.user_interests:
                label = f"Thème : {_theme_label(content.source.theme)}"
                return ScoringWeights.THEME_MATCH, PillarContribution(
                    label=label, points=ScoringWeights.THEME_MATCH
                )

        # Tier 3: Source secondary themes (70% of primary)
        if content.source and getattr(content.source, "secondary_themes", None):
            matched = set(content.source.secondary_themes) & context.user_interests
            if matched:
                theme = sorted(matched)[0]
                bonus = (
                    ScoringWeights.THEME_MATCH * ScoringWeights.SECONDARY_THEME_FACTOR
                )
                label = f"Thème secondaire : {_theme_label(theme)}"
                return bonus, PillarContribution(label=label, points=bonus)

        return 0.0, None

    def _score_subtopics(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Granular subtopic matching with weight amplification."""
        if not context.user_subtopics or not content.topics:
            return 0.0, []

        content_topics = {t.lower().strip() for t in content.topics if t}
        user_subtopics = {s.lower().strip() for s in context.user_subtopics}
        matches = content_topics & user_subtopics
        match_count = min(len(matches), ScoringWeights.TOPIC_MAX_MATCHES)

        if match_count == 0:
            return 0.0, []

        weights = context.user_subtopic_weights
        matched_list = sorted(matches)[:match_count]
        score = 0.0
        boosted_topics = []

        for topic in matched_list:
            w = weights.get(topic, 1.0)
            score += ScoringWeights.TOPIC_MATCH * w
            if w > 1.0:
                boosted_topics.append(topic)

        # Precision bonus: theme + subtopic both match
        user_interests_lower = {s.lower().strip() for s in context.user_interests}
        has_theme_match = False
        if hasattr(content, "theme") and content.theme:
            has_theme_match = content.theme.lower().strip() in user_interests_lower
        if not has_theme_match and content.source and content.source.theme:
            has_theme_match = (
                content.source.theme.lower().strip() in user_interests_lower
            )
        if (
            not has_theme_match
            and content.source
            and getattr(content.source, "secondary_themes", None)
        ):
            secondary_set = {t.lower().strip() for t in content.source.secondary_themes}
            has_theme_match = bool(secondary_set & user_interests_lower)

        if has_theme_match:
            score += ScoringWeights.SUBTOPIC_PRECISION_BONUS

        # Build contribution label
        labels = [_subtopic_label(s) for s in matched_list]
        contributions = []

        if boosted_topics:
            boosted_labels = [_subtopic_label(s) for s in boosted_topics]
            label = f"Sujet suivi : {', '.join(boosted_labels)}"
        else:
            label = f"Sujet : {', '.join(labels)}"

        contributions.append(PillarContribution(label=label, points=score))

        return score, contributions

    def _score_behavioral(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Dynamic interest weight amplification/attenuation."""
        effective_theme = _get_effective_theme(content, context.user_interests)
        if not effective_theme:
            return 0.0, []

        weight = context.user_interest_weights.get(effective_theme, 1.0)
        base_theme_score = 50.0

        if weight > 1.0:
            bonus = base_theme_score * (weight - 1.0)
            label = f"Vous lisez souvent : {_theme_label(effective_theme)}"
            return bonus, [PillarContribution(label=label, points=bonus)]

        if weight < 1.0:
            malus = base_theme_score * (1.0 - weight)
            label = f"Intérêt en baisse : {_theme_label(effective_theme)}"
            return -malus, [
                PillarContribution(label=label, points=-malus, is_positive=False)
            ]

        return 0.0, []

    def _score_custom_topics(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Custom topics from Epic 11."""
        if not context.user_custom_topics:
            return 0.0, []

        content_topics = set()
        if content.topics:
            content_topics = {t.lower().strip() for t in content.topics if t}

        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()

        best_score = 0.0
        best_topic_name = ""

        for tp in context.user_custom_topics:
            matched = False
            if tp.slug_parent in content_topics:
                matched = True
            if not matched and tp.keywords:
                for kw in tp.keywords:
                    kw_lower = kw.lower().strip()
                    if kw_lower and (kw_lower in title_lower or kw_lower in desc_lower):
                        matched = True
                        break

            if matched:
                topic_score = (
                    ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * tp.priority_multiplier
                )
                if topic_score > best_score:
                    best_score = topic_score
                    best_topic_name = tp.topic_name

        if best_score > 0:
            label = f"Votre sujet : {best_topic_name}"
            return best_score, [PillarContribution(label=label, points=best_score)]

        return 0.0, []

    def _score_format(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Format preference from onboarding."""
        format_pref = context.user_prefs.get("format_preference")
        if not format_pref:
            return 0.0, []

        bonus = 0.0
        if (format_pref == "audio" and content.content_type == ContentType.PODCAST) or (
            format_pref == "video" and content.content_type == ContentType.VIDEO
        ):
            bonus = 20.0
        elif (
            format_pref == "short"
            and content.duration_seconds
            and content.duration_seconds <= 300
        ) or (
            format_pref == "long"
            and content.duration_seconds
            and content.duration_seconds >= 900
        ):
            bonus = 15.0

        if bonus > 0:
            return bonus, [PillarContribution(label="Format préféré", points=bonus)]

        return 0.0, []
