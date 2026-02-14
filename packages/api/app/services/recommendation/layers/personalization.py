"""Layer de personnalisation - applique les malus pour sources/thèmes/topics mutés."""

from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.models.content import Content


class PersonalizationLayer(BaseScoringLayer):
    """
    Applique les malus de personnalisation explicite définis par l'utilisateur.
    
    Poids :
    - Source mutée : -80 pts (fort impact, l'utilisateur veut clairement moins voir)
    - Type de contenu muté : -50 pts (filtre large sur le format)
    - Thème muté : -40 pts (impact modéré, peut encore apparaître si autres facteurs forts)
    - Topic muté : -30 pts (impact ciblé par sous-thème)
    """

    MUTED_SOURCE_MALUS = -80.0
    MUTED_CONTENT_TYPE_MALUS = -50.0
    MUTED_THEME_MALUS = -40.0
    MUTED_TOPIC_MALUS = -30.0
    
    @property
    def name(self) -> str:
        return "personalization"
    
    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        
        # 1. Source mutée → gros malus
        if hasattr(context, 'muted_sources') and context.muted_sources:
            if content.source_id in context.muted_sources:
                score += self.MUTED_SOURCE_MALUS
                context.add_reason(
                    content.id, 
                    self.name, 
                    self.MUTED_SOURCE_MALUS, 
                    "Tu vois moins de cette source"
                )
        
        # 2. Thème muté → malus modéré
        # Priorité au thème article ML (plus précis que le thème source)
        if hasattr(context, 'muted_themes') and context.muted_themes:
            effective_theme = None
            if hasattr(content, 'theme') and content.theme:
                effective_theme = content.theme.lower().strip()
            elif content.source and content.source.theme:
                effective_theme = content.source.theme.lower().strip()

            if effective_theme and effective_theme in context.muted_themes:
                score += self.MUTED_THEME_MALUS
                context.add_reason(
                    content.id,
                    self.name,
                    self.MUTED_THEME_MALUS,
                    f"Tu vois moins de {effective_theme}"
                )
        
        # 3. Type de contenu muté → malus large sur le format
        if hasattr(context, 'muted_content_types') and context.muted_content_types:
            ct = content.content_type
            if ct and ct.value in context.muted_content_types:
                score += self.MUTED_CONTENT_TYPE_MALUS
                ct_label = {"article": "les articles", "podcast": "les podcasts", "youtube": "les vidéos YouTube"}.get(ct.value, ct.value)
                context.add_reason(
                    content.id,
                    self.name,
                    self.MUTED_CONTENT_TYPE_MALUS,
                    f"Tu vois moins de ce format ({ct_label})"
                )

        # 4. Topics mutés → malus ciblé (cumulatif si plusieurs matches)
        if hasattr(context, 'muted_topics') and context.muted_topics:
            if content.topics:
                content_topics = {t.lower().strip() for t in content.topics if t}
                muted_matches = content_topics & set(context.muted_topics)
                
                for topic in muted_matches:
                    score += self.MUTED_TOPIC_MALUS
                    context.add_reason(
                        content.id, 
                        self.name, 
                        self.MUTED_TOPIC_MALUS, 
                        f"Tu vois moins de {topic}"
                    )
        
        return score
